import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/utils/order_remarks.dart';

void main() {
  test(
    'order requests trim edges while preserving Myanmar and line breaks',
    () {
      expect(
        normaliseOrderRemarks('  မရောက်ခင် ဖုန်းဆက်ပေးပါ။\nRing the bell.  '),
        'မရောက်ခင် ဖုန်းဆက်ပေးပါ။\nRing the bell.',
      );
      expect(normaliseOrderRemarks(' \n '), isNull);
      expect(normaliseOrderRemarks(null), isNull);
    },
  );
  test(
    'requests reject excess Unicode characters and unsupported null bytes',
    () {
      expect(normaliseOrderRemarks('🐟' * 500), '🐟' * 500);
      expect(() => normaliseOrderRemarks('🐟' * 501), throwsFormatException);
      expect(
        () => normaliseOrderRemarks('Call\u0000me'),
        throwsFormatException,
      );
    },
  );
  test('new and old order records parse requests without breaking history', () {
    final row = <String, dynamic>{
      'id': 'order-12345',
      'user_id': 'customer',
      'status': 'paid',
      'total': 20,
      'created_at': '2026-10-10T00:00:00Z',
    };
    expect(Order.fromMap(row).customerRemarks, isNull);
    expect(
      Order.fromMap({...row, 'customer_remarks': 'Call before delivery'})
          .customerRemarks,
      'Call before delivery',
    );
  });
}
