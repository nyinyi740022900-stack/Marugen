import '../utils/server_time.dart';

enum DiscountType { percent, fixed }

DiscountType discountTypeFromString(String value) {
  return value == 'fixed' ? DiscountType.fixed : DiscountType.percent;
}

/// What the admin's "Expiry date" stores: the chosen day stays valid until
/// 23:59:59.999 device-local time, sent as UTC. Sending the local date
/// without an offset made the database read it as UTC, so codes stopped
/// working at 08:00 Singapore time on their expiry day.
String promoExpiryStorageValue(DateTime day) => DateTime(
  day.year,
  day.month,
  day.day,
  23,
  59,
  59,
  999,
).toUtc().toIso8601String();

class PromoCode {
  final String id;
  final String code;
  final DiscountType discountType;
  final double discountValue;
  final bool active;
  final DateTime? expiresAt;

  /// Total orders allowed to use this code. Null = unlimited.
  final int? maxRedemptions;

  /// How many orders have claimed a redemption slot so far — includes
  /// orders still `pending`; released back down if one is cancelled
  /// before payment (see 0015_promo_code_limits.sql).
  final int timesRedeemed;

  /// The signed-in customer already used this code — each customer may
  /// redeem a code once. Only the checkout lookup (`check_promo_code`)
  /// reports it; admin listings leave it false.
  final bool alreadyRedeemed;

  const PromoCode({
    required this.id,
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.active,
    this.expiresAt,
    this.maxRedemptions,
    this.timesRedeemed = 0,
    this.alreadyRedeemed = false,
  });

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get isRedemptionCapReached =>
      maxRedemptions != null && timesRedeemed >= maxRedemptions!;

  bool get isUsable => active && !isExpired && !isRedemptionCapReached;

  /// The discount amount for a given [subtotal], never exceeding it.
  double discountFor(double subtotal) {
    final raw = discountType == DiscountType.percent
        ? subtotal * discountValue / 100
        : discountValue;
    return raw.clamp(0, subtotal);
  }

  factory PromoCode.fromMap(Map<String, dynamic> map) {
    return PromoCode(
      id: map['id'] as String,
      code: map['code'] as String,
      discountType: discountTypeFromString(
        map['discount_type'] as String? ?? 'percent',
      ),
      discountValue: (map['discount_value'] as num?)?.toDouble() ?? 0,
      active: map['active'] as bool? ?? true,
      expiresAt: map['expires_at'] != null
          ? parseServerTime(map['expires_at'] as String)
          : null,
      maxRedemptions: map['max_redemptions'] as int?,
      timesRedeemed: map['times_redeemed'] as int? ?? 0,
      alreadyRedeemed: map['already_redeemed'] as bool? ?? false,
    );
  }
}
