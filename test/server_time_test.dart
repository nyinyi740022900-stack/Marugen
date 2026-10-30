import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:marugen_app/shared/models/app_notification.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/models/promo_code.dart';
import 'package:marugen_app/shared/models/review.dart';
import 'package:marugen_app/shared/utils/server_time.dart';

void main() {
  // 07:30 on 30 October in Singapore is still 29 October in UTC.
  const raw = '2026-10-29T23:30:00+00:00';
  final instant = DateTime.parse(raw);
  String shown(DateTime value) =>
      DateFormat.yMMMd('en_US').add_jm().format(value);

  test('server timestamps become device-local without moving the instant', () {
    final local = parseServerTime(raw);
    expect(local.isUtc, isFalse);
    expect(local.isAtSameMomentAs(instant), isTrue);
    expect(tryParseServerTime(raw)!.isUtc, isFalse);
    expect(tryParseServerTime(null), isNull);
    expect(tryParseServerTime('not a date'), isNull);
  });

  test('orders, notifications and reviews show local wall-clock time', () {
    final expected = shown(instant.toLocal());
    final order = Order.fromMap({
      'id': 'order-1',
      'user_id': 'customer',
      'status': 'paid',
      'total': 20,
      'created_at': raw,
      'tracking_updated_at': raw,
    });
    final notification = AppNotification.fromMap({
      'id': 'n1',
      'title': 'Order shipped',
      'body': 'On its way',
      'created_at': raw,
    });
    final review = ProductReview.fromMap({
      'id': 'r1',
      'product_id': 'p1',
      'user_id': 'customer',
      'rating': 5,
      'created_at': raw,
      'admin_reply_at': raw,
    });
    for (final value in [
      order.createdAt,
      order.trackingUpdatedAt!,
      notification.createdAt,
      review.createdAt,
      review.shopReplyAt!,
    ]) {
      expect(value.isUtc, isFalse);
      expect(shown(value), expected);
    }
  });

  test(
    'a Singapore order placed before 08:00 keeps its Singapore date',
    () {
      final order = Order.fromMap({
        'id': 'order-1',
        'user_id': 'customer',
        'status': 'paid',
        'total': 20,
        'created_at': raw,
      });
      // CLDR separates "AM" with a narrow no-break space.
      expect(
        shown(order.createdAt).replaceAll(' ', ' '),
        'Oct 30, 2026 7:30 AM',
      );
    },
    skip: DateTime.now().timeZoneOffset == const Duration(hours: 8)
        ? false
        : 'Needs a Singapore-time (+08:00) test machine',
  );

  test('promo expiry stays on the chosen local day through a save', () {
    final stored = promoExpiryStorageValue(DateTime(2026, 11, 30));
    expect(stored, endsWith('Z'));
    final reloaded = PromoCode.fromMap({
      'id': 'p1',
      'code': 'SAVE10',
      'discount_type': 'percent',
      'discount_value': 10,
      'expires_at': stored,
    }).expiresAt!;
    expect([reloaded.year, reloaded.month, reloaded.day], [2026, 11, 30]);
    expect([reloaded.hour, reloaded.minute], [23, 59]);
    // Re-saving an unchanged code must not move its expiry.
    expect(promoExpiryStorageValue(reloaded), stored);
  });
}
