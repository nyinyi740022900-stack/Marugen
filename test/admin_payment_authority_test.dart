import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/shared/models/order.dart';

void main() {
  test(
    'pending admin order actions cannot assert a Stripe payment succeeded',
    () {
      expect(validNextStatuses(OrderStatus.pending), {OrderStatus.cancelled});
    },
  );
}
