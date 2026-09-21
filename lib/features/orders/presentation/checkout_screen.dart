import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Address;
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/address.dart';
import '../../../shared/models/promo_code.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/utils/price_format.dart';
import '../../cart/domain/cart_item.dart';
import '../../cart/presentation/cart_providers.dart';
import '../../profile/presentation/address_book_screen.dart';
import '../../profile/presentation/address_providers.dart';
import '../../promo/presentation/promo_providers.dart';
import '../../shop/presentation/shell_tab_provider.dart';
import '../data/order_repository.dart';
import '../data/payment_repository.dart';
import 'orders_providers.dart';

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
  const CheckoutScreen({super.key, this.buyNowItems});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _processing = false;
  String? _error;
  String? _selectedAddressId;
  final _promoCtrl = TextEditingController();
  PromoCode? _appliedPromo;
  String? _promoError;
  bool _promoLoading = false;

  /// Buy Now mode keeps its own removable local copy — there's no
  /// provider backing it, unlike the persistent cart.
  late final List<CartItem>? _buyNowItems =
      widget.buyNowItems == null ? null : List.of(widget.buyNowItems!);

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
    if (_isBuyNow) {
      setState(() => _buyNowItems!.removeWhere((i) => i.lineKey == item.lineKey));
    } else {
      ref.read(cartProvider.notifier).remove(
            item.product.id,
            variantId: item.selectedVariant?.id,
            size: item.selectedSize,
          );
    }
  }

  @override
  void dispose() {
    _promoCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyPromo() async {
    final code = _promoCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _promoLoading = true;
      _promoError = null;
    });
    try {
      final promo = await ref.read(promoRepositoryProvider).lookupCode(code);
      if (promo == null || !promo.isUsable) {
        setState(() {
          _appliedPromo = null;
          _promoError = promo == null
              ? 'Invalid promo code.'
              : promo.isExpired
              ? 'This promo code has expired.'
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
      setState(() {
        _appliedPromo = null;
        _promoError = 'Could not check promo code.';
      });
    } finally {
      if (mounted) setState(() => _promoLoading = false);
    }
  }

  void _removePromo() {
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

  Future<void> _pay({Address? shippingAddress}) async {
    // The Pay button's disabled-while-processing state only takes effect
    // on the next rebuild frame, so a very fast double-tap could otherwise
    // invoke this twice before that frame — creating two pending orders/
    // PaymentIntents for the same cart. Guard re-entrancy directly here.
    if (_processing) return;
    final items = _isBuyNow ? _buyNowItems! : ref.read(cartProvider);
    if (items.isEmpty) return;

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
      final freshItems = _isBuyNow ? _buyNowItems! : ref.read(cartProvider);
      if (freshItems.isEmpty) return;

      final intent = await PaymentRepository().createPaymentIntent(
        currency: 'sgd',
        shippingAddress: shippingAddress?.toShippingJson(),
        promoCode: _appliedPromo?.code,
        idempotencyKey: _idempotencyKey,
        items: [
          for (final item in freshItems)
            {
              'product_id': item.product.id,
              'quantity': item.quantity,
              if (item.selectedVariant != null)
                'variant_id': item.selectedVariant!.id,
              if (item.selectedSize != null) 'size_label': item.selectedSize,
            },
        ],
      );
      pendingOrderId = intent['orderId'] as String?;

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: intent['clientSecret'] as String,
          merchantDisplayName: 'Marugen Koi Farm',
          // Required for PayNow (and any other redirect/voucher-based
          // method) to bring the customer back into the app instead of
          // stranding them in Safari — matches the `marugen` URL scheme
          // registered in ios/Runner/Info.plist.
          returnURL: 'marugen://stripe-redirect',
          // Apple Pay is deliberately left out: without a real merchant ID
          // (needs a paid Apple Developer Program membership) and the
          // matching Xcode entitlement, configuring `applePay:` here was
          // observed to crash the app when the sheet opens rather than
          // just hiding the button. Re-add once that account/entitlement
          // exists. Google Pay is Android-only — harmless to leave on here,
          // it's simply ignored on iOS.
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'SG',
            currencyCode: 'SGD',
            testEnv: true,
          ),
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      // Buy Now never touched the persistent cart, so there's nothing to
      // clear — whatever was already in the cart before this purchase
      // stays exactly as it was.
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
      if (mounted && pendingOrderId != null) {
        context.go('/orders/$pendingOrderId?justPlaced=true');
      } else if (mounted) {
        ref.read(customerTabIndexProvider.notifier).state = 2;
        context.go('/');
      }
    } on StripeException catch (e) {
      if (pendingOrderId != null) {
        try {
          await OrderRepository().cancelMyOrder(pendingOrderId);
        } catch (_) {}
      }
      setState(() => _error = e.error.localizedMessage ?? 'Payment cancelled.');
    } catch (e) {
      if (pendingOrderId != null) {
        try {
          await OrderRepository().cancelMyOrder(pendingOrderId);
        } catch (_) {}
      }
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _addAddress() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddressForm(),
    );
    ref.invalidate(myAddressesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final items = _isBuyNow ? _buyNowItems! : ref.watch(cartProvider);
    final subtotal = _isBuyNow
        ? items.fold<double>(0, (sum, i) => sum + i.subtotal)
        : ref.watch(cartTotalProvider);
    final addressesAsync = ref.watch(myAddressesProvider);
    final settingsAsync = ref.watch(shopSettingsProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(title: const Text('CHECKOUT')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                children: [
                  const Text(
                    'DELIVERY ADDRESS',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.8,
                      color: AppColors.grey,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  addressesAsync.when(
                    data: (addresses) {
                      final selectedId = _resolveSelectedId(addresses);
                      return Container(
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          boxShadow: AppShadows.card,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            if (addresses.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'You need a delivery address to check out.',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: AppColors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    OutlinedButton.icon(
                                      onPressed: _addAddress,
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('Add Address'),
                                    ),
                                  ],
                                ),
                              )
                            else ...[
                              for (final address in addresses)
                                ListTile(
                                  onTap: () => setState(
                                    () => _selectedAddressId = address.id,
                                  ),
                                  leading: Icon(
                                    address.id == selectedId
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_unchecked,
                                    color: address.id == selectedId
                                        ? AppColors.red
                                        : AppColors.greySoft,
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
                                  subtitle: Text(
                                    address.oneLine,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                              const Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                              ),
                              TextButton.icon(
                                onPressed: _addAddress,
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
                  const Text(
                    'ORDER SUMMARY',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.8,
                      color: AppColors.grey,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              item.optionLabel != null
                                  ? '${item.optionLabel} · Qty ${item.quantity}'
                                  : 'Qty ${item.quantity}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.grey,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  formatPrice(item.subtotal),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.close, size: 18, color: AppColors.grey),
                                  onPressed: () => _removeItem(item),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text(
                    'PROMO CODE',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.8,
                      color: AppColors.grey,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      boxShadow: AppShadows.card,
                    ),
                    child: _appliedPromo != null
                        ? Row(
                            children: [
                              const Icon(
                                Icons.local_offer_outlined,
                                size: 18,
                                color: AppColors.red,
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
                                onPressed: _removePromo,
                                child: const Text('Remove'),
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _promoCtrl,
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
                              SizedBox(
                                height: 52,
                                child: OutlinedButton(
                                  onPressed: _promoLoading ? null : _applyPromo,
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
                          (settings['gst_percent'] as num?)?.toDouble() ?? 0;
                      final gstIncluded =
                          settings['gst_included_in_price'] as bool? ?? true;
                      final discountAmount =
                          _appliedPromo?.discountFor(subtotal) ?? 0;
                      final netSubtotal = subtotal - discountAmount;
                      final double gstAmount;
                      final double payableTotal;
                      if (gstIncluded) {
                        gstAmount =
                            netSubtotal -
                            (netSubtotal / (1 + gstPercent / 100));
                        payableTotal = netSubtotal;
                      } else {
                        gstAmount = netSubtotal * gstPercent / 100;
                        payableTotal = netSubtotal + gstAmount;
                      }
                      return _TotalsCard(
                        subtotal: subtotal,
                        discountAmount: discountAmount,
                        gstPercent: gstPercent,
                        gstAmount: gstAmount,
                        gstIncluded: gstIncluded,
                        payableTotal: payableTotal,
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
                  color: AppColors.redSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.redDark,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _PayButton(
              processing: _processing,
              hasItems: items.isNotEmpty,
              addressesAsync: addressesAsync,
              resolveSelectedId: _resolveSelectedId,
              onPayDelivery: (address) => _pay(shippingAddress: address),
            ),
          ],
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
          const Icon(Icons.wifi_off_outlined, size: 18, color: AppColors.grey),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: const TextStyle(color: AppColors.grey, fontSize: 13)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _PayButton extends StatelessWidget {
  final bool processing;
  final bool hasItems;
  final AsyncValue<List<Address>> addressesAsync;
  final String? Function(List<Address>) resolveSelectedId;
  final void Function(Address) onPayDelivery;

  const _PayButton({
    required this.processing,
    required this.hasItems,
    required this.addressesAsync,
    required this.resolveSelectedId,
    required this.onPayDelivery,
  });

  @override
  Widget build(BuildContext context) {
    return addressesAsync.maybeWhen(
      data: (addresses) {
        final selectedId = resolveSelectedId(addresses);
        final matching = addresses.where((a) => a.id == selectedId);
        final selectedAddress = matching.isNotEmpty ? matching.first : null;
        final canPay = selectedAddress != null && !processing && hasItems;
        return ElevatedButton(
          onPressed: canPay ? () => onPayDelivery(selectedAddress) : null,
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
                  selectedAddress == null
                      ? 'Add an address to continue'
                      : 'Pay with Stripe',
                ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  final double subtotal;
  final double discountAmount;
  final double gstPercent;
  final double gstAmount;
  final bool gstIncluded;
  final double payableTotal;

  const _TotalsCard({
    required this.subtotal,
    this.discountAmount = 0,
    required this.gstPercent,
    required this.gstAmount,
    required this.gstIncluded,
    required this.payableTotal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Subtotal',
                style: TextStyle(fontSize: 13.5, color: AppColors.grey),
              ),
              Text(
                formatPrice(subtotal),
                style: const TextStyle(fontSize: 13.5),
              ),
            ],
          ),
          if (discountAmount > 0) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Promo discount',
                  style: TextStyle(fontSize: 13.5, color: AppColors.grey),
                ),
                Text(
                  '-${formatPrice(discountAmount)}',
                  style: const TextStyle(fontSize: 13.5, color: AppColors.red),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'GST (${gstPercent.toStringAsFixed(0)}%)',
                style: const TextStyle(fontSize: 13.5, color: AppColors.grey),
              ),
              Text(
                formatPrice(gstAmount),
                style: const TextStyle(fontSize: 13.5),
              ),
            ],
          ),
          const Divider(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.grey,
                    ),
                  ),
                  if (gstIncluded) ...[
                    const SizedBox(width: 4),
                    const Text(
                      '(incl. GST)',
                      style: TextStyle(fontSize: 11, color: AppColors.greySoft),
                    ),
                  ],
                ],
              ),
              Text(
                formatPrice(payableTotal),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.black,
                  fontSize: 20,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
