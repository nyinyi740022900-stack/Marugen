enum DiscountType { percent, fixed }

DiscountType discountTypeFromString(String value) {
  return value == 'fixed' ? DiscountType.fixed : DiscountType.percent;
}

class PromoCode {
  final String id;
  final String code;
  final DiscountType discountType;
  final double discountValue;
  final bool active;
  final DateTime? expiresAt;

  const PromoCode({
    required this.id,
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.active,
    this.expiresAt,
  });

  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get isUsable => active && !isExpired;

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
      discountType: discountTypeFromString(map['discount_type'] as String? ?? 'percent'),
      discountValue: (map['discount_value'] as num?)?.toDouble() ?? 0,
      active: map['active'] as bool? ?? true,
      expiresAt:
          map['expires_at'] != null ? DateTime.parse(map['expires_at'] as String) : null,
    );
  }
}
