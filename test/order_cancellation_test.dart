import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/shared/models/order.dart';

Map<String, dynamic> orderMap([Map<String, dynamic> changes = const {}]) => {
  'id': 'order-1234',
  'user_id': 'customer',
  'status': 'paid',
  'total': 20,
  'created_at': '2026-10-26T10:00:00Z',
  'stripe_payment_intent_id': 'pi_paid',
  'fulfillment_method': 'courier',
  ...changes,
};

void main() {
  test('paid and packing unbooked payments allow a cancellation request', () {
    for (final status in ['paid', 'packing']) {
      expect(
        Order.fromMap(orderMap({'status': status})).canRequestCancellation,
        isTrue,
      );
    }
    for (final status in [
      'pending',
      'shipped',
      'delivered',
      'cancelled',
      'refunded',
    ]) {
      expect(
        Order.fromMap(orderMap({'status': status})).canRequestCancellation,
        isFalse,
      );
    }
  });

  test('any booking, physical milestone or refund prevents a new request', () {
    for (final fields in [
      {'easyparcel_booking_state': 'submitting'},
      {'easyparcel_booking_started_at': '2026-10-26T10:00:00Z'},
      {'tracking_registered': true},
      {'tracking_provider': 'easyparcel'},
      {'qxpress_tracking_no': 'Q123'},
      {'easyparcel_shipment_id': 'S123'},
      {'tracking_progress': 1},
      {'refund_status': 'pending'},
      {'stripe_payment_intent_id': null},
      {
        'parcels': [
          {'id': 'parcel', 'state': 'booking'},
        ],
      },
      {
        'parcels': [
          {'id': 'parcel', 'state': 'draft', 'tracking_number': 'Q123'},
        ],
      },
    ]) {
      expect(
        Order.fromMap(orderMap(fields)).canRequestCancellation,
        isFalse,
        reason: '$fields',
      );
    }
    expect(
      Order.fromMap(
        orderMap({
          'parcels': [
            {'id': 'p', 'state': 'draft'},
          ],
        }),
      ).canRequestCancellation,
      isTrue,
    );
  });

  test(
    'request holds fulfillment and survives object or array relation shapes',
    () {
      final request = {
        'order_id': 'order-1234',
        'status': 'requested',
        'reason': 'Changed my mind',
        'requested_at': '2026-10-26T10:00:00Z',
      };
      for (final relation in [
        request,
        [request],
      ]) {
        final order = Order.fromMap(
          orderMap({'order_cancellation_requests': relation}),
        );
        expect(order.cancellationRequest?.reason, 'Changed my mind');
        expect(order.hasCancellationHold, isTrue);
        expect(order.canRequestCancellation, isFalse);
        expect(order.fulfillmentStatusLabel, 'Cancellation requested');
        expect(order.canSplitIntoParcels, isFalse);
      }
    },
  );

  test('approved is held until verified refund; rejected remains final without a hold', () {
    for (final status in ['approved', 'rejected']) {
      final order = Order.fromMap(
        orderMap({
          'order_cancellation_requests': {'status': status},
        }),
      );
      expect(order.hasCancellationHold, status == 'approved');
      expect(order.canRequestCancellation, isFalse);
    }
    final order = Order.fromMap(
      orderMap({
        'status': 'refunded',
        'refund_status': 'succeeded',
        'order_cancellation_requests': {'status': 'approved'},
      }),
    );
    expect(order.fulfillmentStatusLabel, 'Refunded');
  });
}
