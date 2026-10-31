import 'dart:developer' as developer;
import 'dart:convert';
import 'dart:math';

import '../utils/delivery_estimate.dart';

import 'package:flutter/material.dart';

import '../../../shared/widgets/content_width.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Address;
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/address.dart';
import '../../../shared/models/promo_code.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/utils/price_format.dart';
import '../../../shared/utils/order_remarks.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../cart/domain/cart_item.dart';
import '../../cart/presentation/cart_providers.dart';
import '../../profile/presentation/address_book_screen.dart';
import '../../profile/presentation/address_providers.dart';
import '../../promo/presentation/promo_providers.dart';
import '../../shop/presentation/shop_providers.dart';
import '../data/payment_repository.dart';
import '../utils/payment_confirmation.dart';
import '../utils/payment_sheet.dart';
import '../utils/checkout_totals.dart';
import 'orders_providers.dart';
import 'purchase_intent.dart';
import 'shipping_quote_providers.dart';
import '../domain/shipping_quote.dart';
import '../../../shared/utils/error_message.dart';
import '../../../shared/widgets/undo_snack_bar.dart';

/// A random per-attempt key for `create-payment-intent` — see
/// CheckoutScreen's `_idempotencyKey` doc. Just needs to be unique per
/// attempt, not a spec-compliant UUID, so a plain random hex string avoids
/// pulling in a uuid package for this alone.
String _randomIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class CheckoutScreen extends ConsumerStatefulWidget {
  /// When set (Buy Now — see product_detail_screen.dart's `_buyNow`), this
  /// screen charges ONLY these items and never touches the persistent
  /// cart at all: not read from it, not cleared on success. When null
  /// (the normal "Cart" screen's Checkout button), it reads/clears
  /// [cartProvider] as before. This mirrors how Amazon/Shopee/Lazada's
  /// "Buy Now" works — an isolated single-purchase flow that never mixes
  /// with or mutates whatever is already sitting in the cart.
  final List<CartItem>? buyNowItems;
  final String? purchaseIntentId;
  const CheckoutScreen({super.key, this.buyNowItems, this.purchaseIntentId});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _processing = false;
  String? _error;
  String? _selectedAddressId;
  final _promoCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  int _remarksRevision = 0;
  String? _remarksError;
  PromoCode? _appliedPromo;
  String? _promoError;
  bool _promoLoading = false;

  /// Buy Now mode keeps its own removable local copy — there's no
  /// provider backing it, unlike the persistent cart.
  late final List<CartItem>? _buyNowItems;
  late final String? _checkoutOwner;

  @override
  void initState() {
    super.initState();
    _checkoutOwner = ref.read(currentUserIdProvider);
    final notifier = ref.read(purchaseIntentProvider.notifier);
    final pendingId = ref.read(purchaseIntentProvider)?.id;
    final saved = notifier.peek(widget.purchaseIntentId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(purchaseIntentProvider)?.id == pendingId) {
        notifier.consume(widget.purchaseIntentId);
      }
    });
    _buyNowItems = widget.buyNowItems == null
        ? saved
        : List.of(widget.buyNowItems!);
  }

  bool get _ownsCheckout =>
      mounted && ref.read(currentUserIdProvider) == _checkoutOwner;

  bool get _isBuyNow => _buyNowItems != null;

  /// One key per checkout *attempt* — this screen instance. Every retry of
  /// `_pay()` (a second tap after an error, or the app itself retrying a
  /// dropped network response) reuses it so the server can recognize "this
  /// is the same attempt" and return the already-reserved order/PaymentIntent
  /// instead of creating a duplicate. Re-entering checkout (a new screen
  /// instance) gets a fresh key, as it should — that's a genuinely new
  /// attempt, possibly against a changed cart.
  late final String _idempotencyKey = _randomIdempotencyKey();

  void _removeItem(CartItem item) {
    if (_processing || !_ownsCheckout) return;
    if (_isBuyNow) {
      final index = _buyNowItems!.indexWhere((i) => i.lineKey == item.lineKey);
      if (index < 0) return;
      setState(() => _buyNowItems.removeAt(index));
      showUndoSnackBar(
        ScaffoldMessenger.of(context),
        message: '${item.product.name} removed',
        onAction: () {
          if (!_ownsCheckout ||
              _processing ||
              _buyNowItems.any((i) => i.lineKey == item.lineKey)) {
            return;
          }
          setState(
            () =>
                _buyNowItems.insert(index.clamp(0, _buyNowItems.length), item),
          );
        },
      );
    } else {
      ref
          .read(cartProvider.notifier)
          .remove(
            item.product.id,
            variantId: item.selectedVariant?.id,
            size: item.selectedSize,
          );
      final ownerId = _checkoutOwner;
      showUndoSnackBar(
        ScaffoldMessenger.of(context),
        message: '${item.product.name} removed',
        onAction: () {
          if (!_ownsCheckout || _processing) return;
          final restored = ref
              .read(cartProvider.notifier)
              .restoreRemoved(item, ownerId: ownerId);
          if (!restored && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'This item could not be restored. Check your cart and availability.',
                ),
              ),
            );
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _promoCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyPromo() async {
    if (_processing || _promoLoading || !_ownsCheckout) return;
    final code = _promoCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _promoLoading = true;
      _promoError = null;
    });
    try {
      final promo = await ref.read(promoRepositoryProvider).lookupCode(code);
      if (!_ownsCheckout) return;
      if (promo == null || !promo.isUsable || promo.alreadyRedeemed) {
        setState(() {
          _appliedPromo = null;
          _promoError = promo == null
              ? 'Invalid promo code.'
              : promo.isExpired
              ? 'This promo code has expired.'
              : promo.alreadyRedeemed
              ? 'You have already used this promo code.'
              : promo.isRedemptionCapReached
              ? 'This promo code has reached its usage limit.'
              : 'This promo code is no longer active.';
        });
      } else {
        setState(() {
          _appliedPromo = promo;
          _promoError = null;
        });
      }
    } catch (e) {
      if (!_ownsCheckout) return;
      setState(() {
        _appliedPromo = null;
        _promoError = 'Could not check promo code.';
      });
    } finally {
      if (mounted) setState(() => _promoLoading = false);
    }
  }

  void _removePromo() {
    if (_processing || _promoLoading) return;
    setState(() {
      _appliedPromo = null;
      _promoError = null;
      _promoCtrl.clear();
    });
  }

  String? _resolveSelectedId(List<Address> addresses) {
    if (addresses.isEmpty) return null;
    if (_selectedAddressId != null &&
        addresses.any((a) => a.id == _selectedAddressId)) {
      return _selectedAddressId;
    }
    final defaultAddress = addresses.where((a) => a.isDefault).toList();
    return defaultAddress.isNotEmpty
        ? defaultAddress.first.id
        : addresses.first.id;
  }

  Future<bool> _revalidateCart() async {
    final result = await ref.read(cartProvider.notifier).refreshFromServer();
    if (!mounted) return false;
    if (result.isEmpty) {
      setState(
        () => _error = 'Your cart is empty or items are no longer available.',
      );
      return false;
    }
    if (result.changed) {
      final parts = <String>[];
      if (result.removed > 0) {
        parts.add('${result.removed} item(s) removed (sold out)');
      }
      if (result.adjusted > 0) {
        parts.add('stock or price updated');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cart updated: ${parts.join(', ')}.')),
      );
      setState(() => _error = 'Cart changed — review totals, then pay again.');
      return false;
    }
    return true;
  }

  String _shippingKey(List<CartItem> items, Address address) => jsonEncode({
    'user_id': _checkoutOwner,
    'items': [
      for (final item in items)
        {
          'product_id': item.product.id,
          'quantity': item.quantity,
          if (item.selectedVariant != null)
            'variant_id': item.selectedVariant!.id,
          if (item.selectedSize != null) 'size_label': item.selectedSize,
        },
    ],
    'shipping_address': address.toShippingJson(),
    'all_couriers': true,
    if (_appliedPromo != null) 'promo_code': _appliedPromo!.code,
  });

  Future<void> _pay({Address? shippingAddress}) async {
    // The Pay button's disabled-while-processing state only takes effect
    // on the next rebuild frame, so a very fast double-tap could otherwise
    // invoke this twice before that frame — creating two pending orders/
    // PaymentIntents for the same cart. Guard re-entrancy directly here.
    if (_processing ||
        _promoLoading ||
        !_ownsCheckout ||
        ref.read(shopSettingsProvider).isLoading ||
        ref.read(shopSettingsProvider).hasError ||
        !ref.read(shopSettingsProvider).hasValue ||
        shippingAddress == null) {
      return;
    }
    if (shippingAddress.userId != _checkoutOwner) {
      setState(
        () => _error = 'Choose a delivery address for your current account.',
      );
      return;
    }
    final items = _isBuyNow ? _buyNowItems! : ref.read(cartProvider);
    if (items.isEmpty) return;
    final shippingKey = _shippingKey(items, shippingAddress);
    final quoteAsync = ref.read(checkoutShippingQuoteProvider(shippingKey));
    final quote = quoteAsync.valueOrNull;
    if (quote == null ||
        quoteAsync.isLoading ||
        quoteAsync.hasError ||
        quote.isExpired) {
      setState(
        () => _error = 'Wait for a current delivery quote before paying.',
      );
      return;
    }
    final remarksError = orderRemarksValidationError(_remarksCtrl.text);
    if (remarksError != null) {
      setState(() => _remarksError = remarksError);
      return;
    }
    final remarks = normaliseOrderRemarks(_remarksCtrl.text);
    final remarksRevision = _remarksRevision;

    if (!ref.read(authRepositoryProvider).isEmailVerified) {
      await _showVerifyEmailDialog();
      return;
    }

    setState(() {
      _processing = true;
      _error = null;
    });

    String? pendingOrderId;
    try {
      // Buy Now items were just picked from the product page moments ago
      // and aren't backed by a persisted cart to re-sync against —
      // create-payment-intent still independently revalidates stock/price
      // server-side regardless (see supabase/functions/create-payment-intent),
      // so skipping this client-side pre-check here is safe.
      if (!_isBuyNow && !await _revalidateCart()) return;
      if (!_ownsCheckout) return;
      final freshItems = _isBuyNow ? _buyNowItems! : ref.read(cartProvider);
      if (freshItems.isEmpty) return;
      if (_shippingKey(freshItems, shippingAddress) != shippingKey) {
        setState(
          () => _error =
              'Cart changed. Review shipping and totals before paying.',
        );
        return;
      }

      final intent = await ref
          .read(paymentRepositoryProvider)
          .createPaymentIntent(
            currency: 'sgd',
            shippingQuoteId: quote.quoteId,
            shippingAddress: shippingAddress.toShippingJson(),
            promoCode: _appliedPromo?.code,
            idempotencyKey: _idempotencyKey,
            customerRemarks: remarks,
            customerRemarksRevision: remarksRevision,
            items: [
              for (final item in freshItems)
                {
                  'product_id': item.product.id,
                  'quantity': item.quantity,
                  if (item.selectedVariant != null)
                    'variant_id': item.selectedVariant!.id,
                  if (item.selectedSize != null)
                    'size_label': item.selectedSize,
                },
            ],
          );
      pendingOrderId = intent['orderId'] as String?;
      if (!mounted || !_ownsCheckout) return;

      if (pendingOrderId == null) throw StateError('Payment order missing');
      final settings = ref.read(shopSettingsProvider).requireValue;
      final subtotal = freshItems.fold<double>(
        0,
        (sum, item) => sum + item.subtotal,
      );
      final totals = checkoutTotals(
        subtotal: subtotal,
        discount: _appliedPromo?.discountFor(subtotal) ?? 0,
        gstPercent: (settings['gst_percent'] as num?)?.toDouble() ?? 0,
        gstIncluded: settings['gst_included_in_price'] as bool? ?? true,
      );
      final expectedCents = totals.payableCents(quote.buyerShippingCents);
      if (intent['paymentStatus'] == null &&
          (intent['amountCents'] != expectedCents ||
              intent['currency']?.toString().toLowerCase() != 'sgd')) {
        // Nothing was charged: release the reserved stock (a live fish
        // especially) now instead of holding it for the 30-minute cleanup.
        await _releasePendingOrder(pendingOrderId);
        throw StateError(
          'Checkout total changed. Review your order before paying.',
        );
      }

      await presentPendingPayment(
        intent: intent,
        ownsCheckout: () => _ownsCheckout,
        presentPayment: (clientSecret) => showStripePaymentSheet(
          clientSecret,
          brightness: Theme.of(context).brightness,
          stillWanted: () => _ownsCheckout,
        ),
      );

      // Bought (or reserved) stock changed: the shop must not keep showing
      // a sold koi as available.
      ref.invalidate(productListProvider);

      // Buy Now never touched the persistent cart, so there's nothing to
      // clear — whatever was already in the cart before this purchase
      // stays exactly as it was.
      if (!_ownsCheckout) return;
      final confirmed = await confirmOrderPayment(
        orderId: pendingOrderId,
        ownerId: _checkoutOwner,
        ownsCheckout: () => _ownsCheckout,
        fetchOrder: ref.read(orderRepositoryProvider).fetchOrderById,
      );
      if (!mounted || !_ownsCheckout) return;
      if (!confirmed) {
        ref.invalidate(myOrdersProvider);
        context.go('/orders/$pendingOrderId');
        return;
      }
      if (!_isBuyNow) ref.read(cartProvider.notifier).clear();
      // The Orders list is a plain (non-autoDispose) FutureProvider, so
      // without this it keeps showing whatever it last fetched — a
      // customer who'd already opened "My Orders" before checking out
      // would place an order successfully (see the order-detail screen
      // that follows) but then find it missing from their order history
      // until something else happened to invalidate it. Same reasoning
      // for admin's list, since staff may have it open at the same time.
      ref.invalidate(myOrdersProvider);
      refreshAdminOrders(ref);
      // Land on the order itself (with a success banner) instead of
      // dumping the customer back to the shop grid with only a toast —
      // the order confirmation *is* the order detail screen, not a
      // separate page, so there's nothing else to keep in sync.
      if (mounted) context.go('/orders/$pendingOrderId?justPlaced=true');
    } on StripeException catch (e) {
      if (pendingOrderId != null &&
          e.error.code == FailureCode.Canceled &&
          _ownsCheckout) {
        await _releasePendingOrder(pendingOrderId);
      }
      if (_ownsCheckout && e.error.code == FailureCode.Canceled) {
        ref.invalidate(checkoutShippingQuoteProvider(shippingKey));
      }
      if (mounted) {
        setState(
          () => _error = e.error.code == FailureCode.Canceled
              ? 'Payment was dismissed. Your items are saved. Check Orders before trying again.'
              : 'Payment could not be completed. Check your payment details and try again.',
        );
      }
    } catch (e) {
      if (_ownsCheckout) {
        ref.invalidate(checkoutShippingQuoteProvider(shippingKey));
      }
      developer.log('Checkout failed', name: 'CheckoutScreen', error: e);
      if (mounted) {
        setState(
          () => _error = e is StateError
              ? e.message.toString()
              : friendlyErrorMessage(
                  e,
                  fallback: 'We couldn’t complete checkout. Check your connection and try again. If payment was taken, check My Orders before retrying.',
                  context: 'checkout.payment',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Cancels an unpaid order this checkout created so its stock is free
  /// again. Best-effort: on failure the order stays `pending` and is
  /// auto-cancelled by cancel-stale-pending-orders after 30 minutes (see
  /// 0014_stale_order_cleanup.sql) rather than crashing the failure path —
  /// logged so a real recurring failure isn't invisible.
  Future<void> _releasePendingOrder(String orderId) async {
    try {
      await ref.read(orderRepositoryProvider).cancelMyOrder(orderId);
    } catch (cancelError) {
      developer.log(
        'Could not cancel unpaid pending order',
        name: 'CheckoutScreen',
        error: cancelError,
      );
    }
  }

  /// Blocks checkout for an email/password account that never confirmed
  /// its address (see AuthRepository.isEmailVerified) — an unconfirmed
  /// email can't receive order/shipping notifications and is a common
  /// vector for throwaway/fraudulent accounts. Offers to resend the
  /// confirmation link right from here rather than sending the customer
  /// away to find it themselves.
  Future<void> _showVerifyEmailDialog() async {
    if (!mounted) return;
    var sending = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Verify your email first'),
          content: const Text(
            'Please confirm your email address before checking out — check '
            'your inbox for the confirmation link we sent when you signed up.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      setDialogState(() => sending = true);
                      try {
                        await ref
                            .read(authRepositoryProvider)
                            .resendVerificationEmail();
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            const SnackBar(
                              content: Text('Confirmation email sent.'),
                            ),
                          );
                          Navigator.of(dialogContext).pop();
                        }
                      } catch (e) {
                        setDialogState(() => sending = false);
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not send the email. Check your connection and try again.',
                              ),
                            ),
                          );
                        }
                      }
                    },
              child: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Resend email'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addAddress() async {
    if (_processing) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddressForm(),
    );
    if (mounted) ref.invalidate(myAddressesProvider);
  }

  /// Opens a saved address the server would reject (see
  /// [Address.isDeliverable]) so the customer can fix it here.
  Future<void> _editAddress(Address address) async {
    if (_processing) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddressForm(existing: address),
    );
    if (mounted) ref.invalidate(myAddressesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final ownerValid = ref.watch(currentUserIdProvider) == _checkoutOwner;
    final compactSummary =
        MediaQuery.sizeOf(context).width < 500 &&
        MediaQuery.textScalerOf(context).scale(14) > 20;
    final items = !ownerValid
        ? <CartItem>[]
        : _isBuyNow
        ? _buyNowItems!
        : ref.watch(cartProvider);
    final subtotal = items.fold<double>(0, (sum, i) => sum + i.subtotal);
    final addressesAsync = ref.watch(myAddressesProvider);
    final settingsAsync = ref.watch(shopSettingsProvider);
    final settingsReady =
        settingsAsync.hasValue &&
        !settingsAsync.isLoading &&
        !settingsAsync.hasError;
    final settings = settingsReady ? settingsAsync.requireValue : null;
    final addresses = addressesAsync.valueOrNull ?? <Address>[];
    final selectedId = _resolveSelectedId(addresses);
    final selected = addresses.where(
      (address) => address.id == selectedId && address.userId == _checkoutOwner,
    );
    final addressNeedsFix =
        selected.isNotEmpty && !selected.first.isDeliverable;
    final quoteKey =
        ownerValid &&
            settingsReady &&
            items.isNotEmpty &&
            selected.isNotEmpty &&
            !addressNeedsFix &&
            !addressesAsync.isLoading &&
            !addressesAsync.hasError
        ? _shippingKey(items, selected.first)
        : null;
    final shippingAsync = quoteKey == null
        ? null
        : ref.watch(checkoutShippingQuoteProvider(quoteKey));
    final quote = shippingAsync?.valueOrNull;
    final shippingReady =
        quote != null &&
        shippingAsync!.hasValue &&
        !shippingAsync.isLoading &&
        !shippingAsync.hasError &&
        !quote.isExpired;
    final shippingFailed = shippingAsync?.hasError ?? false;
    final totalsReady = settingsReady && shippingReady;
    final totals = settings == null
        ? null
        : checkoutTotals(
            subtotal: subtotal,
            discount: _appliedPromo?.discountFor(subtotal) ?? 0,
            gstPercent: (settings['gst_percent'] as num?)?.toDouble() ?? 0,
            gstIncluded: settings['gst_included_in_price'] as bool? ?? true,
          );
    final payable = totalsReady
        ? totals!.payableCents(quote.buyerShippingCents) / 100
        : null;

    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: AppBar(title: const Text('CHECKOUT')),
      body: ContentWidth(
        maxWidth: 760,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      Text(
                        'DELIVERY ADDRESS',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.8,
                          color: AppPalette.of(context).textMuted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      addressesAsync.when(
                        data: (addresses) {
                          final selectedId = _resolveSelectedId(addresses);
                          return Container(
                            decoration: BoxDecoration(
                              color: AppPalette.of(context).surface,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              boxShadow: AppShadows.card,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                if (addresses.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.lg,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'You need a delivery address to check out.',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            color: AppPalette.of(context)
                                                .textMuted,
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        OutlinedButton.icon(
                                          onPressed: _processing
                                              ? null
                                              : _addAddress,
                                          icon: const Icon(Icons.add, size: 18),
                                          label: const Text('Add Address'),
                                        ),
                                      ],
                                    ),
                                  )
                                else ...[
                                  for (final address in addresses)
                                    Material(
                                      color: AppPalette.of(context).surface,
                                      child: ListTile(
                                        onTap: _processing
                                            ? null
                                            : () => setState(
                                                () => _selectedAddressId =
                                                    address.id,
                                              ),
                                        leading: Icon(
                                          address.id == selectedId
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_unchecked,
                                          color: address.id == selectedId
                                              ? AppPalette.of(context).accent
                                              : AppPalette.of(context)
                                                    .textMuted,
                                        ),
                                        title: Text(
                                          '${address.label} — ${address.recipientName}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        subtitle: Text.rich(
                                          TextSpan(
                                            text: address.oneLine,
                                            children: [
                                              if (!address.isDeliverable)
                                                TextSpan(
                                                  text: '\nUpdate the phone or postal code to deliver here',
                                                  style: TextStyle(
                                                    color: AppPalette.of(
                                                      context,
                                                    ).accent,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                          ),
                                        ),
                                        trailing: address.isDeliverable
                                            ? null
                                            : TextButton(
                                                onPressed: _processing
                                                    ? null
                                                    : () =>
                                                          _editAddress(address),
                                                child: const Text('Edit'),
                                              ),
                                      ),
                                    ),
                                  const Divider(
                                    height: 1,
                                    indent: 16,
                                    endIndent: 16,
                                  ),
                                  TextButton.icon(
                                    onPressed: _processing ? null : _addAddress,
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Add new address'),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (e, _) => _InlineRetryError(
                          message: "Couldn't load your addresses.",
                          onRetry: () => ref.invalidate(myAddressesProvider),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _DeliveryPromise(
                        shopDelivery: items.any(
                          (item) => item.product.isLiveFish,
                        ),
                        settings: settings,
                        shippingReady: shippingReady,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (quoteKey != null && shippingAsync != null)
                        shippingAsync.when(
                          data: (_) => const SizedBox.shrink(),
                          loading: () =>
                              const Text('Calculating SGD delivery cost…'),
                          error: (error, _) => _InlineRetryError(
                            message: 'We couldn’t get a delivery price. Retry or contact the shop.',
                            onRetry: () => ref.invalidate(
                              checkoutShippingQuoteProvider(quoteKey),
                            ),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'ORDER SUMMARY',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.8,
                          color: AppPalette.of(context).textMuted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        decoration: BoxDecoration(
                          color: AppPalette.of(context).surface,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          boxShadow: AppShadows.card,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (final item in items)
                              ListTile(
                                title: Text(
                                  item.product.name,
                                  maxLines: compactSummary ? 3 : 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.optionLabel != null
                                          ? '${item.optionLabel} · Qty ${item.quantity}'
                                          : 'Qty ${item.quantity}',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: AppPalette.of(context).textMuted,
                                      ),
                                    ),
                                    if (compactSummary)
                                      Text(
                                        formatPrice(item.subtotal),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!compactSummary)
                                      Text(
                                        formatPrice(item.subtotal),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    IconButton(
                                      tooltip: 'Remove',
                                      visualDensity: VisualDensity.standard,
                                      icon: Icon(
                                        Icons.close,
                                        size: 18,
                                        color: AppPalette.of(context).textMuted,
                                      ),
                                      onPressed: _processing
                                          ? null
                                          : () => _removeItem(item),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (ownerValid) ...[
                        Text(
                          'ORDER REQUESTS',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0.8,
                            color: AppPalette.of(context).textMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: AppPalette.of(context).surface,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            boxShadow: AppShadows.card,
                          ),
                          child: TextField(
                            key: const ValueKey('order-remarks'),
                            controller: _remarksCtrl,
                            enabled: !_processing,
                            minLines: 3,
                            maxLines: 5,
                            maxLength: maxOrderRemarksLength,
                            maxLengthEnforcement: MaxLengthEnforcement.none,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              labelText: 'Order requests / remarks (optional)',
                              hintText: 'e.g. Please call before delivery.',
                              helperText: 'Delivery instructions or other requests for the shop.',
                              helperMaxLines: 3,
                              errorText: _remarksError,
                              errorMaxLines: 3,
                              alignLabelWithHint: true,
                            ),
                            buildCounter:
                                (
                                  context, {
                                  required currentLength,
                                  required isFocused,
                                  required maxLength,
                                }) => Text(
                                  '${_remarksCtrl.text.trim().runes.length}/$maxOrderRemarksLength',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppPalette.of(context).textMuted,
                                  ),
                                ),
                            onChanged: (value) => setState(() {
                              _remarksRevision++;
                              _remarksError = orderRemarksValidationError(
                                value,
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      Text(
                        'PROMO CODE',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.8,
                          color: AppPalette.of(context).textMuted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppPalette.of(context).surface,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          boxShadow: AppShadows.card,
                        ),
                        child: _appliedPromo != null
                            ? Row(
                                children: [
                                  Icon(
                                    Icons.local_offer_outlined,
                                    size: 18,
                                    color: AppPalette.of(context).accent,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      '"${_appliedPromo!.code}" applied',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _processing
                                        ? null
                                        : _removePromo,
                                    child: const Text('Remove'),
                                  ),
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: TextField(
                                      key: const ValueKey('promo-code'),
                                      controller: _promoCtrl,
                                      enabled: !_processing && !_promoLoading,
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      decoration: InputDecoration(
                                        hintText: 'Enter code',
                                        errorText: _promoError,
                                        isDense: true,
                                      ),
                                      onSubmitted: (_) => _applyPromo(),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 52,
                                    ),
                                    child: OutlinedButton(
                                      onPressed: _promoLoading || _processing
                                          ? null
                                          : _applyPromo,
                                      child: _promoLoading
                                          ? const SizedBox(
                                              height: 16,
                                              width: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('Apply'),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      settingsAsync.when(
                        data: (settings) {
                          final gstPercent =
                              (settings['gst_percent'] as num?)?.toDouble() ??
                              0;
                          final gstIncluded =
                              settings['gst_included_in_price'] as bool? ??
                              true;
                          final amount = checkoutTotals(
                            subtotal: subtotal,
                            discount: _appliedPromo?.discountFor(subtotal) ?? 0,
                            gstPercent: gstPercent,
                            gstIncluded: gstIncluded,
                          );
                          return _TotalsCard(
                            subtotal: subtotal,
                            discountAmount: amount.discountCents / 100,
                            gstPercent: gstPercent,
                            gstAmount: amount.gstCents / 100,
                            gstIncluded: gstIncluded,
                            payableTotal: shippingReady
                                ? amount.payableCents(
                                        quote.buyerShippingCents,
                                      ) /
                                      100
                                : null,
                            shippingQuote: shippingReady ? quote : null,
                            shippingFailed: shippingFailed,
                          );
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (e, _) => _InlineRetryError(
                          message: "Couldn't load checkout totals.",
                          onRetry: () => ref.invalidate(shopSettingsProvider),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppPalette.of(context).accentSoft,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: AppPalette.of(context).accent,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                _PayButton(
                  processing: _processing,
                  shippingFailed: shippingFailed,
                  onRetryShipping: quoteKey == null
                      ? null
                      : () => ref.invalidate(
                          checkoutShippingQuoteProvider(quoteKey),
                        ),
                  totalsReady: totalsReady,
                  promoLoading: _promoLoading,
                  payable: payable,
                  hasItems: items.isNotEmpty,
                  remarksValid: _remarksError == null,
                  addressesAsync: addressesAsync,
                  resolveSelectedId: _resolveSelectedId,
                  onPayDelivery: (address) => _pay(shippingAddress: address),
                  onFixAddress: _editAddress,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact inline error+retry for a section nested inside the checkout
/// list — a full-page [ErrorState] would look oversized here since this
/// only replaces one card's worth of content, not the whole screen.
class _InlineRetryError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineRetryError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(
            Icons.wifi_off_outlined,
            size: 18,
            color: AppPalette.of(context).textMuted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppPalette.of(context).textMuted,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _PayButton extends StatelessWidget {
  final bool shippingFailed;
  final VoidCallback? onRetryShipping;
  final bool remarksValid;
  final bool processing;
  final bool hasItems;
  final bool totalsReady;
  final bool promoLoading;
  final double? payable;
  final AsyncValue<List<Address>> addressesAsync;
  final String? Function(List<Address>) resolveSelectedId;
  final void Function(Address) onPayDelivery;
  final void Function(Address) onFixAddress;

  const _PayButton({
    required this.shippingFailed,
    this.onRetryShipping,
    required this.processing,
    required this.hasItems,
    required this.remarksValid,
    required this.totalsReady,
    required this.promoLoading,
    required this.payable,
    required this.addressesAsync,
    required this.resolveSelectedId,
    required this.onPayDelivery,
    required this.onFixAddress,
  });

  @override
  Widget build(BuildContext context) {
    return addressesAsync.maybeWhen(
      data: (addresses) {
        final selectedId = resolveSelectedId(addresses);
        final matching = addresses.where((a) => a.id == selectedId);
        final selectedAddress = matching.isNotEmpty ? matching.first : null;
        final addressNeedsFix =
            hasItems &&
            remarksValid &&
            selectedAddress != null &&
            !selectedAddress.isDeliverable;
        final canPay =
            remarksValid &&
            checkoutCanPay(
              hasItems: hasItems,
              hasAddress: selectedAddress != null,
              totalsReady: totalsReady,
              promoLoading: promoLoading,
              processing: processing,
            );
        return ElevatedButton(
          onPressed: addressNeedsFix
              ? (processing ? null : () => onFixAddress(selectedAddress))
              : shippingFailed &&
                    !processing &&
                    hasItems &&
                    selectedAddress != null
              ? onRetryShipping
              : canPay
              ? () => onPayDelivery(selectedAddress!)
              : null,
          child: processing
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.white,
                  ),
                )
              : Text(
                  !hasItems
                      ? 'No items to check out'
                      : !remarksValid
                      ? 'Review your order requests'
                      : addressNeedsFix
                      ? 'Update delivery address'
                      : shippingFailed
                      ? 'Retry delivery'
                      : !totalsReady
                      ? 'Waiting for totals'
                      : promoLoading
                      ? 'Checking promo code…'
                      : selectedAddress == null
                      ? 'Add an address to continue'
                      : 'Pay ${formatPrice(payable!)} with Stripe',
                ),
        );
      },
      orElse: () => const ElevatedButton(
        onPressed: null,
        child: Text('Waiting for delivery address'),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  final double subtotal;
  final double discountAmount;
  final double gstPercent;
  final double gstAmount;
  final bool gstIncluded;
  final double? payableTotal;
  final ShippingQuote? shippingQuote;
  final bool shippingFailed;

  const _TotalsCard({
    required this.subtotal,
    this.discountAmount = 0,
    required this.gstPercent,
    required this.gstAmount,
    required this.gstIncluded,
    required this.payableTotal,
    this.shippingQuote,
    this.shippingFailed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppPalette.of(context).surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          _SummaryLine(label: 'Subtotal', amount: formatPrice(subtotal)),
          const SizedBox(height: 6),
          _SummaryLine(
            label: 'Delivery',
            amount: shippingFailed
                ? 'Unavailable'
                : shippingQuote == null
                ? 'Calculating…'
                : shippingQuote!.isShopDelivery
                ? 'Free'
                : formatPrice(shippingQuote!.buyerShippingCents / 100),
          ),
          if (discountAmount > 0) ...[
            const SizedBox(height: 6),
            _SummaryLine(
              label: 'Promo discount',
              amount: '-${formatPrice(discountAmount)}',
              amountColor: AppPalette.of(context).accent,
            ),
          ],
          const SizedBox(height: 6),
          _SummaryLine(
            label: 'GST (${gstPercent.toStringAsFixed(0)}%)',
            amount: formatPrice(gstAmount),
          ),
          const Divider(height: AppSpacing.lg),
          _SummaryLine(
            label: gstIncluded ? 'Total (incl. GST)' : 'Total',
            amount: shippingFailed
                ? 'Delivery unavailable'
                : payableTotal == null
                ? 'Waiting for shipping'
                : formatPrice(payableTotal!),
            isTotal: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String amount;
  final Color? amountColor;
  final bool isTotal;
  const _SummaryLine({
    required this.label,
    required this.amount,
    this.amountColor,
    this.isTotal = false,
  });
  @override
  Widget build(BuildContext context) {
    final labelWidget = Text(
      label,
      style: TextStyle(
        fontSize: 13.5,
        color: AppPalette.of(context).textMuted,
        fontWeight: isTotal ? FontWeight.w600 : FontWeight.normal,
      ),
    );
    final amountWidget = Text(
      amount,
      style: TextStyle(
        fontSize: isTotal ? 20 : 13.5,
        color: amountColor ?? AppPalette.of(context).text,
        fontWeight: isTotal ? FontWeight.w700 : FontWeight.normal,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) > 18) {
          return SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelWidget, const SizedBox(height: 4), amountWidget],
            ),
          );
        }
        return Row(
          children: [
            Expanded(child: labelWidget),
            const SizedBox(width: 12),
            Flexible(child: amountWidget),
          ],
        );
      },
    );
  }
}

/// The customer sees timing and the payable fee; allocation stays server-side.
class _DeliveryPromise extends StatelessWidget {
  final bool shopDelivery;
  final bool shippingReady;
  final Map<String, dynamic>? settings;
  const _DeliveryPromise({
    required this.shopDelivery,
    required this.settings,
    required this.shippingReady,
  });
  @override
  Widget build(BuildContext context) {
    final min = (settings?['delivery_lead_days_min'] as num?)?.toInt() ?? 2;
    final max = (settings?['delivery_lead_days_max'] as num?)?.toInt() ?? 5;
    final range = settings == null
        ? null
        : deliveryArrivalRange(DateTime.now(), min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DELIVERY',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.8,
            color: AppPalette.of(context).textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (shopDelivery) ...[
          const Text(
            'Shop delivery',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const Text(
            'Free delivery. We’ll contact you to arrange the delivery time.',
          ),
          const Text(
            'Live fish and other items in this order arrive together.',
          ),
        ] else if (shippingReady && range != null)
          Text(
            'Estimated arrival: $range',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}
