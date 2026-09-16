/// A saved delivery address in the customer's address book.
/// See `supabase/migrations/0002_addresses.sql`.
class Address {
  final String id;
  final String userId;
  final String label;
  final String recipientName;
  final String phone;
  final String line1;
  final String? line2;
  final String city;
  final String postalCode;
  final bool isDefault;

  const Address({
    required this.id,
    required this.userId,
    this.label = 'Home',
    required this.recipientName,
    required this.phone,
    required this.line1,
    this.line2,
    this.city = 'Singapore',
    required this.postalCode,
    this.isDefault = false,
  });

  factory Address.fromMap(Map<String, dynamic> map) {
    return Address(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      label: map['label'] as String? ?? 'Home',
      recipientName: map['recipient_name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      line1: map['line1'] as String? ?? '',
      line2: map['line2'] as String?,
      city: map['city'] as String? ?? 'Singapore',
      postalCode: map['postal_code'] as String? ?? '',
      isDefault: map['is_default'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'recipient_name': recipientName,
      'phone': phone,
      'line1': line1,
      'line2': line2,
      'city': city,
      'postal_code': postalCode,
      'is_default': isDefault,
    };
  }

  /// A short single-line summary used in checkout/order-detail displays.
  String get oneLine {
    final parts = [line1, if (line2 != null && line2!.isNotEmpty) line2, city, postalCode];
    return parts.join(', ');
  }

  /// Serialized form suitable for storing on `orders.shipping_address`.
  Map<String, dynamic> toShippingJson() {
    return {
      'label': label,
      'recipient_name': recipientName,
      'phone': phone,
      'line1': line1,
      'line2': line2,
      'city': city,
      'postal_code': postalCode,
    };
  }
}
