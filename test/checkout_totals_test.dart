import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/orders/utils/checkout_totals.dart';

void main() {
  test('exclusive GST half-cent rounds the same as server',(){
    final t=checkoutTotals(subtotal:30.50,discount:0,gstPercent:9,gstIncluded:false);
    expect(t.merchandiseCents,3325);
  });
  test(
    'percentage promo rounds discount before subtracting for inclusive GST',
    () {
      final t = checkoutTotals(
        subtotal: 9.95,
        discount: .995,
        gstPercent: 9,
        gstIncluded: true,
      );
      expect(t.discountCents, 100);
      expect(t.merchandiseCents, 895);
      expect(t.payableCents(202), 1097);
    },
  );
  test('percentage promo and exclusive GST round in server order', () {
    final t = checkoutTotals(
      subtotal: 20.05,
      discount: 2.0050000000000003,
      gstPercent: 9,
      gstIncluded: false,
    );
    expect(t.discountCents, 201);
    expect(t.merchandiseCents, 1966);
    expect(t.payableCents(202), 2168);
  });
}
