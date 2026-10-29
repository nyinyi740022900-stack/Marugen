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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${order.shippingCarrierName ?? 'Courier'} delivery · SGD',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text('Total shipping: ${formatPrice(order.totalShippingCents! / 100)}'),
        Text(
          'Buyer paid: ${formatPrice(order.buyerShippingCents! / 100)} · Shop covers: ${formatPrice(order.sellerShippingCents! / 100)}',
        ),
      ],
    );
  }
}
