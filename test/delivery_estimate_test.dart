import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/orders/utils/delivery_estimate.dart';

void main() {
  test('arrival dates use the Singapore calendar date', () {
    expect(
      deliveryArrivalRange(DateTime.parse('2026-10-19T18:00:00Z'), 2, 3),
      '22–23 Oct',
    );
  });
  test('month and year boundaries remain explicit', () {
    expect(
      deliveryArrivalRange(DateTime.utc(2026, 10, 29), 1, 4),
      '30 Oct – 2 Nov',
    );
    expect(
      deliveryArrivalRange(DateTime.utc(2026, 12, 30), 1, 3),
      '31 Dec 2026 – 2 Jan 2027',
    );
  });
  test('one day and invalid configuration', () {
    expect(deliveryArrivalRange(DateTime.utc(2026, 10, 20), 2, 2), '22 Oct');
    expect(deliveryArrivalRange(DateTime.utc(2026, 10, 20), 3, 2), isNull);
  });
}
