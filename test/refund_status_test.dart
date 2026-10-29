import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/shared/models/order.dart';

Order order({
  String status = 'paid',
  String? refund,
  num returned = 0,
  num pending = 0,
}) => Order.fromMap({
  'id': '12345678-order',
  'user_id': 'buyer',
  'status': status,
  'total': 20,
  'created_at': '2026-10-19T12:00:00Z',
  'refund_status': refund,
  'refund_amount': returned,
  'refund_pending_amount': pending,
});

void main() {
  test('pending and failed refunds never claim completion', () {
    final waiting = order(refund: 'pending', pending: 20);
    expect(waiting.refundStatusLabel, 'Refund pending');
    expect(waiting.status, OrderStatus.paid);
    expect(waiting.refundAmount, 0);
    expect(waiting.refundPendingAmount, 20);
    expect(waiting.canRequestRefund, isFalse);
    expect(
      order(refund: 'failed').refundStatusLabel,
      'Refund failed — contact shop',
    );
    expect(
      order(refund: 'requires_action').refundStatusLabel,
      'Refund needs attention — contact shop',
    );
  });
  test(
    'partial refunds reduce paid revenue without claiming a full refund',
    () {
      final partial = order(refund: 'partially_refunded', returned: 5);
      expect(partial.netPaidAmount, 15);
      expect(partial.refundStatusLabel, 'Partially refunded');
      expect(partial.canRequestRefund, isFalse);
      expect(
        order(
          status: 'refunded',
          refund: 'succeeded',
          returned: 20,
        ).netPaidAmount,
        0,
      );
    },
  );
  test('unpaid and canceled orders do not count as revenue', () {
    expect(order(status: 'pending').netPaidAmount, 0);
    expect(order(status: 'cancelled').netPaidAmount, 0);
    expect(order(status: 'paid').netPaidAmount, 20);
    expect(order(status: 'paid').canRequestRefund, isTrue);
  });
  test('old orders without new refund fields remain readable', () {
    final old = order(status: 'refunded');
    expect(old.refundStatusLabel, isNull);
    expect(old.netPaidAmount, 0);
    expect(old.canRequestRefund, isFalse);
  });
  test('verified incomplete legacy refund cannot claim money was returned', () {
    final legacy = order(
      status: 'refunded',
      refund: 'partially_refunded',
      returned: 5,
    );
    expect(legacy.netPaidAmount, 15);
    expect(legacy.fulfillmentStatusLabel, 'Partially refunded');
    expect(legacy.needsRefundReview, isTrue);
  });
}
