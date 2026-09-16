import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Address;
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/address.dart';
import '../../../shared/models/promo_code.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../cart/presentation/cart_providers.dart';
import '../../profile/presentation/address_book_screen.dart';
import '../../profile/presentation/address_providers.dart';
import '../../promo/presentation/promo_providers.dart';
import '../../shop/presentation/shell_tab_provider.dart';
import '../data/order_repository.dart';
import '../data/payment_repository.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

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
    return defaultAddress.isNotEmpty ? defaultAddress.first.id : addresses.first.id;
  }

  Future<void> _pay(Address shippingAddress, double payableTotal, double discountAmount) async {
    final items = ref.read(cartProvider);
    if (items.isEmpty) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      // 1. Ask our Edge Function (server-side Stripe secret key) for a
      //    PaymentIntent client secret.
      final intent = await PaymentRepository().createPaymentIntent(
        amount: payableTotal,
        currency: 'sgd',
        items: [
          for (final item in items)
            {
              'product_id': item.product.id,
              'product_name': item.product.name,
              'quantity': item.quantity,
              'unit_price': item.unitPrice,
            },
        ],
      );

      // 2. Present Stripe's PaymentSheet (card / Apple Pay / Google Pay /
      //    PayNow, depending on what's enabled on the Stripe SG account).
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: intent['clientSecret'] as String,
          merchantDisplayName: 'Marugen Koi Farm',
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      // 3. Record the order. (The Stripe webhook Edge Function is the
      //    source of truth for payment confirmation; this call lets the
      //    customer see the order immediately.)
      await OrderRepository().createOrder(
        items: [
          for (final item in items)
            {
              'product_id': item.product.id,
              'product_name': item.product.name,
              'quantity': item.quantity,
              'unit_price': item.unitPrice,
              if (item.selectedVariant != null) 'variant_id': item.selectedVariant!.id,
              if (item.selectedVariant != null) 'variant_label': item.selectedVariant!.label,
            },
        ],
        total: payableTotal,
        stripePaymentIntentId: intent['paymentIntentId'] as String? ?? '',
        shippingAddress: shippingAddress.toShippingJson(),
        promoCode: _appliedPromo?.code,
        discountAmount: discountAmount > 0 ? discountAmount : null,
      );

      ref.read(cartProvider.notifier).clear();
      ref.read(customerTabIndexProvider.notifier).state = 2; // Orders tab
      if (mounted) {
        context.go('/');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment successful — order placed!')),
        );
      }
    } on StripeException catch (e) {
      setState(() => _error = e.error.localizedMessage ?? 'Payment cancelled.');
    } catch (e) {
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
    final items = ref.watch(cartProvider);
    final subtotal = ref.watch(cartTotalProvider);
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
                  const Text('DELIVERY ADDRESS',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.8,
                          color: AppColors.grey)),
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
                                      style: TextStyle(fontSize: 13.5, color: AppColors.grey),
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
                                  onTap: () => setState(() => _selectedAddressId = address.id),
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
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                                  ),
                                  subtitle: Text(address.oneLine, style: const TextStyle(fontSize: 12.5)),
                                ),
                              const Divider(height: 1, indent: 16, endIndent: 16),
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
                    error: (e, _) => Text('Error loading addresses: $e'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('ORDER SUMMARY',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.8,
                          color: AppColors.grey)),
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
                            title: Text(item.product.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text(
                                item.selectedVariant != null
                                    ? '${item.selectedVariant!.label} · Qty ${item.quantity}'
                                    : 'Qty ${item.quantity}',
                                style: const TextStyle(fontSize: 12.5, color: AppColors.grey)),
                            trailing: Text('S\$${item.subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('PROMO CODE',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.8,
                          color: AppColors.grey)),
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
                              const Icon(Icons.local_offer_outlined, size: 18, color: AppColors.red),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  '"${_appliedPromo!.code}" applied',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                                ),
                              ),
                              TextButton(onPressed: _removePromo, child: const Text('Remove')),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _promoCtrl,
                                  textCapitalization: TextCapitalization.characters,
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
                                          child: CircularProgressIndicator(strokeWidth: 2),
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
                      final gstPercent = (settings['gst_percent'] as num?)?.toDouble() ?? 0;
                      final gstIncluded = settings['gst_included_in_price'] as bool? ?? true;
                      final discountAmount =
                          _appliedPromo?.discountFor(subtotal) ?? 0;
                      final netSubtotal = subtotal - discountAmount;
                      final double gstAmount;
                      final double payableTotal;
                      if (gstIncluded) {
                        gstAmount = netSubtotal - (netSubtotal / (1 + gstPercent / 100));
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
                    error: (e, _) => Text('Error loading settings: $e'),
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
                child: Text(_error!, style: const TextStyle(color: AppColors.redDark, fontSize: 13)),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            addressesAsync.maybeWhen(
              data: (addresses) => settingsAsync.maybeWhen(
                data: (settings) {
                  final selectedId = _resolveSelectedId(addresses);
                  final matching = addresses.where((a) => a.id == selectedId);
                  final selectedAddress = matching.isNotEmpty ? matching.first : null;
                  final gstPercent = (settings['gst_percent'] as num?)?.toDouble() ?? 0;
                  final gstIncluded = settings['gst_included_in_price'] as bool? ?? true;
                  final discountAmount = _appliedPromo?.discountFor(subtotal) ?? 0;
                  final netSubtotal = subtotal - discountAmount;
                  final payableTotal = gstIncluded
                      ? netSubtotal
                      : netSubtotal + (netSubtotal * gstPercent / 100);
                  final canPay = selectedAddress != null && !_processing;

                  return ElevatedButton(
                    onPressed: canPay
                        ? () => _pay(selectedAddress, payableTotal, discountAmount)
                        : null,
                    child: _processing
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                          )
                        : Text(selectedAddress == null
                            ? 'Add an address to continue'
                            : 'Pay with Stripe'),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
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
              const Text('Subtotal',
                  style: TextStyle(fontSize: 13.5, color: AppColors.grey)),
              Text('S\$${subtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13.5)),
            ],
          ),
          if (discountAmount > 0) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Promo discount',
                    style: TextStyle(fontSize: 13.5, color: AppColors.grey)),
                Text('-S\$${discountAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 13.5, color: AppColors.red)),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('GST (${gstPercent.toStringAsFixed(0)}%)',
                  style: const TextStyle(fontSize: 13.5, color: AppColors.grey)),
              Text('S\$${gstAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13.5)),
            ],
          ),
          const Divider(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('Total',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.grey)),
                  if (gstIncluded) ...[
                    const SizedBox(width: 4),
                    const Text('(incl. GST)',
                        style: TextStyle(fontSize: 11, color: AppColors.greySoft)),
                  ],
                ],
              ),
              Text('S\$${payableTotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.black, fontSize: 20)),
            ],
          ),
        ],
      ),
    );
  }
}
