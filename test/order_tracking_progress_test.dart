import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/shared/models/order.dart';

Order tracked({required int code, int? progress}) => Order.fromMap({
  'id': 'tracked-order',
  'status': 'shipped',
  'total': 1,
  'created_at': '2026-10-24T00:00:00Z',
  'tracking_provider': 'easyparcel',
  'tracking_registered': true,
  'qxpress_tracking_no': 'TEST-AWB',
  'tracking_status_code': code,
  'tracking_progress': ?progress,
});

void main() {
  test('a hold after recorded collection cannot display awaiting pickup', () {
    expect(tracked(code: 8, progress: 1).awaitingCourierPickup, isFalse);
    expect(tracked(code: 7, progress: 1).awaitingCourierPickup, isFalse);
  });
  test('legacy scheduled and collected rows retain their distinction', () {
    expect(tracked(code: 7).awaitingCourierPickup, isTrue);
    expect(tracked(code: 3).awaitingCourierPickup, isFalse);
  });
}
