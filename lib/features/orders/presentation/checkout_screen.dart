import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart' hide Address;
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
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

enum _Fulfillment { delivery, pickup }

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _processing = false;
  String? _error;
  String? _selectedAddressId;
  _Fulfillment _fulfillment = _Fulfillment.delivery;
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

  Future<bool> _revalidateCart() async {
    final result = await ref.read(cartProvider.notifier).refreshFromServer();
    if (!mounted) return false;
    if (result.isEmpty) {
      setState(() => _error = 'Your cart is empty or items are no longer available.');
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
    final items = ref.read(cartProvider);
    if (items.isEmpty) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    String? pendingOrderId;
    try {
      if (!await _revalidateCart()) return;
      final freshItems = ref.read(cartProvider);
      if (freshItems.isEmpty) return;

      final intent = await PaymentRepository().createPaymentIntent(
        currency: 'sgd',
        fulfillment: _fulfillment == _Fulfillment.pickup ? 'pickup' : 'delivery',
        shippingAddress: _fulfillment == _Fulfillment.delivery
            ? shippingAddress?.toShippingJson()
            : null,
        promoCode: _appliedPromo?.code,
        items: [
          for (final item in freshItems)
            {
              'product_id': item.product.id,
              'quantity': item.quantity,
              if (item.selectedVariant != null) 'variant_id': item.selectedVariant!.id,
            },
        ],
      );
      pendingOrderId = intent['orderId'] as String?;

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: intent['clientSecret'] as String,
          merchantDisplayName: 'Marugen Koi Farm',
          applePay: Platform.isIOS && Env.appleMerchantId.isNotEmpty
              ? const PaymentSheetApplePay(merchantCountryCode: 'SG')
              : null,
          googlePay: Platform.isAndroid
              ? PaymentSheetGooglePay(
                  merchantCountryCode: 'SG',
                  testEnv: Env.isStripeTestMode,
                )
              : null,
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      ref.read(cartProvider.notifier).clear();
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
                  const Text('FULFILLMENT',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.8,
                          color: AppColors.grey)),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      boxShadow: AppShadows.card,
                    ),
                    child: SegmentedButton<_Fulfillment>(
                      segments: const [
                        ButtonSegment(
                          value: _Fulfillment.delivery,
                          label: Text('Delivery'),
                          icon: Icon(Icons.local_shipping_outlined, size: 18),
                        ),
                        ButtonSegment(
                          value: _Fulfillment.pickup,
                          label: Text('Pickup'),
                          icon: Icon(Icons.storefront_outlined, size: 18),
                        ),
                      ],
                      selected: {_fulfillment},
                      onSelectionChanged: (s) =>
                          setState(() => _fulfillment = s.first),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_fulfillment == _Fulfillment.delivery) ...[
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
                                    onTap: () =>
                                        setState(() => _selectedAddressId = address.id),
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
                                          fontWeight: FontWeight.w600, fontSize: 13.5),
                                    ),
                                    subtitle: Text(address.oneLine,
                                        style: const TextStyle(fontSize: 12.5)),
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
                  ] else
                    settingsAsync.when(
                      data: (settings) {
                        final farm = (settings['shop_address'] as String?)?.trim();
                        final phone = (settings['shop_phone'] as String?)?.trim();
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            boxShadow: AppShadows.card,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('PICKUP LOCATION',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      letterSpacing: 0.8,
                                      color: AppColors.grey)),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                farm?.isNotEmpty == true ? farm! : 'Farm address TBD — contact shop.',
                                style: const TextStyle(fontSize: 13.5, height: 1.4),
                              ),
                              if (phone != null && phone.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(phone,
                                    style: const TextStyle(
                                        fontSize: 12.5, color: AppColors.grey)),
                              ],
                            ],
                          ),
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (e, _) => Text('Error: $e'),
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
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text(
                                item.selectedVariant != null
                                    ? '${item.selectedVariant!.label} · Qty ${item.quantity}'
                                    : 'Qty ${item.quantity}',
                                style: const TextStyle(
                                    fontSize: 12.5, color: AppColors.grey)),
                            trailing: Text('S\$${item.subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14)),
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
                              const Icon(Icons.local_offer_outlined,
                                  size: 18, color: AppColors.red),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  '"${_appliedPromo!.code}" applied',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 13.5),
                                ),
                              ),
                              TextButton(
                                  onPressed: _removePromo, child: const Text('Remove')),
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
                      final gstPercent =
                          (settings['gst_percent'] as num?)?.toDouble() ?? 0;
                      final gstIncluded =
                          settings['gst_included_in_price'] as bool? ?? true;
                      final discountAmount = _appliedPromo?.discountFor(subtotal) ?? 0;
                      final netSubtotal = subtotal - discountAmount;
                      final double gstAmount;
                      final double payableTotal;
                      if (gstIncluded) {
                        gstAmount =
                            netSubtotal - (netSubtotal / (1 + gstPercent / 100));
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
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.redDark, fontSize: 13)),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _PayButton(
              fulfillment: _fulfillment,
              processing: _processing,
              addressesAsync: addressesAsync,
              resolveSelectedId: _resolveSelectedId,
              onPayDelivery: (address) => _pay(shippingAddress: address),
              onPayPickup: () => _pay(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayButton extends StatelessWidget {
  final _Fulfillment fulfillment;
  final bool processing;
  final AsyncValue<List<Address>> addressesAsync;
  final String? Function(List<Address>) resolveSelectedId;
  final void Function(Address) onPayDelivery;
  final VoidCallback onPayPickup;

  const _PayButton({
    required this.fulfillment,
    required this.processing,
    required this.addressesAsync,
    required this.resolveSelectedId,
    required this.onPayDelivery,
    required this.onPayPickup,
  });

  @override
  Widget build(BuildContext context) {
    if (fulfillment == _Fulfillment.pickup) {
      return ElevatedButton(
        onPressed: processing ? null : onPayPickup,
        child: processing
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.white),
              )
            : const Text('Pay with Stripe'),
      );
    }

    return addressesAsync.maybeWhen(
      data: (addresses) {
        final selectedId = resolveSelectedId(addresses);
        final matching = addresses.where((a) => a.id == selectedId);
        final selectedAddress = matching.isNotEmpty ? matching.first : null;
        final canPay = selectedAddress != null && !processing;
        return ElevatedButton(
          onPressed: canPay ? () => onPayDelivery(selectedAddress) : null,
          child: processing
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.white),
                )
              : Text(selectedAddress == null
                  ? 'Add an address to continue'
                  : 'Pay with Stripe'),
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
              const Text('Subtotal',
                  style: TextStyle(fontSize: 13.5, color: AppColors.grey)),
              Text('S\$${subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 13.5)),
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
              Text('S\$${gstAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 13.5)),
            ],
          ),
          const Divider(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('Total',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.grey)),
                  if (gstIncluded) ...[
                    const SizedBox(width: 4),
                    const Text('(incl. GST)',
                        style: TextStyle(fontSize: 11, color: AppColors.greySoft)),
                  ],
                ],
              ),
              Text('S\$${payableTotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.black,
                      fontSize: 20)),
            ],
          ),
        ],
      ),
    );
  }
}
