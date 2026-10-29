/// Public support details only. These records do not grant staff permissions.
enum SupportChannel { whatsapp, phone, email }

class SupportContact {
  final String id;
  final String name;
  final String category;
  final String? whatsapp;
  final String? phone;
  final String? email;

  SupportContact.fromMap(Map<String, dynamic> map)
    : id = _required(map['id'], 'ID', 64),
      name = _required(map['name'], 'Staff name', 80),
      category = _required(map['category'], 'Support responsibility', 120),
      whatsapp = _phone(map['whatsapp']),
      phone = _phone(map['phone']),
      email = _email(map['email']) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid contact ID.');
    }
    if (channels.isEmpty) {
      throw const FormatException('Add at least one contact channel.');
    }
  }

  List<SupportChannel> get channels => [
    if (whatsapp != null) SupportChannel.whatsapp,
    if (phone != null) SupportChannel.phone,
    if (email != null) SupportChannel.email,
  ];

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'category': category,
    'whatsapp': whatsapp,
    'phone': phone,
    'email': email,
  };

  Uri uri(SupportChannel channel, {String? message}) {
    if (!channels.contains(channel)) {
      throw const FormatException('This contact channel is unavailable.');
    }
    return switch (channel) {
      SupportChannel.whatsapp => Uri.https(
        'wa.me',
        '/${whatsapp!.substring(1)}',
        {'text': ?message},
      ),
      SupportChannel.phone => Uri(scheme: 'tel', path: phone),
      SupportChannel.email => Uri(
        scheme: 'mailto',
        path: email,
        queryParameters: {'body': ?message},
      ),
    };
  }

  static String _required(Object? value, String label, int max) {
    if (value is! String ||
        value.trim().isEmpty ||
        value.trim().length > max ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(value)) {
      throw FormatException('$label is required (maximum $max characters).');
    }
    return value.trim();
  }

  static String? _optional(Object? value) {
    if (value == null || value == '') return null;
    if (value is! String || RegExp(r'[\x00-\x1F\x7F]').hasMatch(value)) {
      throw const FormatException('Invalid contact channel.');
    }
    return value.trim().isEmpty ? null : value.trim();
  }

  static String? _phone(Object? value) {
    final text = _optional(value);
    if (text == null) return null;
    if (!RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(text)) {
      throw const FormatException(
        'Use an international number, e.g. +6588889999.',
      );
    }
    return text;
  }

  static String? _email(Object? value) {
    final text = _optional(value);
    if (text == null) return null;
    if (text.length > 254 ||
        !RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+$')
            .hasMatch(text)) {
      throw const FormatException('Enter a valid email address.');
    }
    return text;
  }
}

List<SupportContact> supportDirectoryFromSettings(
  Map<String, dynamic> settings, {
  bool legacyFallback = true,
}) {
  final raw = settings['support_contacts'] ?? <dynamic>[];
  if (raw is! List || raw.length > 30) {
    throw const FormatException('Invalid support directory.');
  }
  final contacts = <SupportContact>[];
  final ids = <String>{};
  for (final entry in raw) {
    if (entry is! Map<String, dynamic>) {
      throw const FormatException('Invalid support contact.');
    }
    final contact = SupportContact.fromMap(entry);
    if (!ids.add(contact.id)) {
      throw const FormatException('Duplicate support contact ID.');
    }
    contacts.add(contact);
  }
  if (contacts.isEmpty && legacyFallback) {
    final rawPhone = settings['shop_phone'];
    if (rawPhone is String && rawPhone.trim().isNotEmpty) {
      final phone = rawPhone.replaceAll(RegExp(r'[ ()-]'), '');
      // Preserve only usable legacy international shop numbers.
      if (RegExp(r'^\+?[1-9][0-9]{6,14}$').hasMatch(phone)) {
        final international = phone.startsWith('+') ? phone : '+$phone';
        contacts.add(
          SupportContact.fromMap({
            'id': 'shop',
            'name': 'Shop support',
            'category': 'General enquiries',
            'phone': international,
            'whatsapp': international,
          }),
        );
      }
    }
  }
  return List.unmodifiable(contacts);
}
