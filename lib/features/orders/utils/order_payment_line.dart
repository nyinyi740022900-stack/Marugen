import '../../../shared/models/order.dart';
import '../../../shared/utils/price_format.dart';

/// How a payment line should be coloured.
enum PaymentLineTone { neutral, pending, problem }

/// One short sentence about an order's money for staff: what was paid and
/// what, if anything, went back. Display only: every figure is the server's.
class OrderPaymentLine {
  final String text;
  final PaymentLineTone tone;
  const OrderPaymentLine(this.text, [this.tone = PaymentLineTone.neutral]);
}

OrderPaymentLine orderPaymentLine(Order order) {
  // A refund that needs a person comes first, whatever was already returned.
  switch (order.refundStatus) {
    case 'requires_action':
      return const OrderPaymentLine(
        'Refund needs attention',
        PaymentLineTone.problem,
      );
    case 'failed':
      return const OrderPaymentLine('Refund failed', PaymentLineTone.problem);
    case 'pending':
      return const OrderPaymentLine('Refund pending', PaymentLineTone.pending);
  }
  if (order.refundPendingAmount > 0) {
    return const OrderPaymentLine('Refund pending', PaymentLineTone.pending);
  }
  if (order.refundAmount > 0) {
    return OrderPaymentLine(
      order.refundAmount >= order.total
          ? 'Refunded ${formatPrice(order.total)}'
          : 'Refunded ${formatPrice(order.refundAmount)} of '
                '${formatPrice(order.total)}',
    );
  }
  if (order.status == OrderStatus.refunded) {
    return const OrderPaymentLine('Refunded');
  }
  const paidStatuses = {
    OrderStatus.paid,
    OrderStatus.packing,
    OrderStatus.shipped,
    OrderStatus.delivered,
  };
  if (paidStatuses.contains(order.status)) {
    return OrderPaymentLine('Paid ${formatPrice(order.netPaidAmount)}');
  }
  return const OrderPaymentLine('Unpaid');
}
