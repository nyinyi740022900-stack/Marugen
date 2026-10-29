import 'package:flutter/material.dart';

import '../models/order.dart';
import '../utils/price_format.dart';

class ShippingCostSummary extends StatelessWidget {
  final Order order;
  final bool showAllocation;
  const ShippingCostSummary({
    super.key,
    required this.order,
    this.showAllocation = false,
  });
  @override
  Widget build(BuildContext context) {
    if (order.shippingQuoteId == null) return const SizedBox.shrink();
    if (order.shippingCostPolicy == 'seller_100') {
      return const Text('Delivery: Free');
    }
    if (!showAllocation) {
      return Text('Delivery: ${formatPrice(order.buyerShippingCents! / 100)}');
    }
    if (order.shippingCurrency != 'SGD' ||
        order.totalShippingCents == null ||
        order.buyerShippingCents == null ||
        order.sellerShippingCents == null) {
      return const Text('Delivery cost needs review. Open the order for help.');
    }
    // A split order is billed per box, so the checkout quote understates it.
    final parcels = order.parcels;
    final parcelTotal =
        parcels.length > 1 && parcels.every((p) => p.quotedTotalCents != null)
        ? parcels.fold<int>(0, (sum, p) => sum + p.quotedTotalCents!)
        : null;
    final total = parcelTotal ?? order.totalShippingCents!;
    final shopCovers = parcelTotal == null
        ? order.sellerShippingCents!
        : (parcelTotal - order.buyerShippingCents!).clamp(0, parcelTotal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${order.shippingCarrierName ?? 'Courier'} delivery · SGD',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          parcelTotal == null
              ? 'Total shipping: ${formatPrice(total / 100)}'
              : 'Total shipping (${parcels.length} parcels): ${formatPrice(total / 100)}',
        ),
        Text(
          'Buyer paid: ${formatPrice(order.buyerShippingCents! / 100)} · Shop covers: ${formatPrice(shopCovers / 100)}',
        ),
      ],
    );
  }
}
