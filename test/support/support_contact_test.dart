import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/shared/models/support_contact.dart';

void main() {
  Map<String, dynamic> entry() => {
    'id': 'staff-1',
    'name': 'Mei',
    'category': 'Orders and delivery',
    'whatsapp': '+6588889999',
    'phone': '+6562223333',
    'email': 'help@example.com',
  };
  test('contact channels produce safe recipient URIs with order context', () {
    final contact = SupportContact.fromMap(entry());
    expect(
      contact.uri(SupportChannel.whatsapp, message: 'Order #123?').toString(),
      'https://wa.me/6588889999?text=Order+%23123%3F',
    );
    expect(contact.uri(SupportChannel.phone).toString(), 'tel:+6562223333');
    expect(
      contact
          .uri(SupportChannel.email, message: 'Order #123?')
          .queryParameters['body'],
      'Order #123?',
    );
  });
  test('invalid identities, channels and unsafe addresses are rejected', () {
    for (final update in [
      {'id': ''},
      {'name': ' '},
      {'category': ''},
      {'whatsapp': '88889999'},
      {'phone': '+65\n88889999'},
      {'email': 'a@example.com?bcc=evil@example.com'},
      {'whatsapp': null, 'phone': null, 'email': null},
      {'phone': 1234},
    ]) {
      expect(
        () => SupportContact.fromMap({...entry(), ...update}),
        throwsFormatException,
      );
    }
  });
  test('directory rejects duplicate ids and malformed stored data', () {
    expect(
      () => supportDirectoryFromSettings({
        'support_contacts': [entry(), entry()],
      }),
      throwsFormatException,
    );
    expect(
      () => supportDirectoryFromSettings({'support_contacts': 'invalid'}),
      throwsFormatException,
    );
  });
  test('empty directory uses existing shop number without inventing staff', () {
    final contacts = supportDirectoryFromSettings({
      'support_contacts': [],
      'shop_phone': '+65 8888 9999',
    });
    expect(contacts.single.name, 'Shop support');
    expect(contacts.single.phone, '+6588889999');
    expect(supportDirectoryFromSettings({'support_contacts': []}), isEmpty);
  });
}
