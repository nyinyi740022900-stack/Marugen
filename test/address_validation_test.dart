import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/profile/data/address_repository.dart';
import 'package:marugen_app/features/profile/presentation/address_book_screen.dart';
import 'package:marugen_app/features/profile/presentation/address_providers.dart';
import 'package:marugen_app/shared/models/address.dart';
import 'package:marugen_app/shared/utils/sg_address.dart';

class SavedAddresses implements AddressRepository {
  final created = <Address>[];
  @override
  Future<List<Address>> fetchMyAddresses() async => created;
  @override
  Future<Address> createAddress(Address address) async {
    created.add(address);
    return address;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test('phone and postal rules match the delivery server', () {
    expect(normalizeSgPhone('+65 9123-4567'), '91234567');
    expect(normalizeSgPhone('(6) 123 4567'), '61234567');
    for (final ok in ['91234567', '+65 8123 4567', '3123-4567', '61234567']) {
      expect(validateSgPhone(ok), isNull, reason: ok);
    }
    for (final bad in ['12345678', '9123456', '912345678', '+66 91234567']) {
      expect(validateSgPhone(bad), 'Enter an 8-digit Singapore number');
    }
    expect(validateSgPhone('  '), 'Required');
    expect(validateSgPostalCode('018956'), isNull);
    expect(validateSgPostalCode('12345'), 'Enter the 6-digit postal code');
    expect(validateSgPostalCode('12345a'), 'Enter the 6-digit postal code');
    expect(validateSgPostalCode(''), 'Required');

    const valid = Address(
      id: 'a',
      userId: 'u',
      recipientName: 'Customer',
      phone: '+65 9123 4567',
      line1: '1 Street',
      postalCode: '018956',
    );
    expect(valid.isDeliverable, isTrue);
    expect(
      const Address(
        id: 'b',
        userId: 'u',
        recipientName: 'Customer',
        phone: '12345678',
        line1: '1 Street',
        postalCode: '018956',
      ).isDeliverable,
      isFalse,
    );
  });

  testWidgets('address form refuses a bad phone or postal code and saves '
      'the phone the way the server reads it', (tester) async {
    final repo = SavedAddresses();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWith((ref) => 'u'),
          addressRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const AddressForm(),
                ),
                child: const Text('Add'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.widgetWithText(TextFormField, label);
    await tester.enterText(field('Recipient name'), 'Customer');
    await tester.enterText(field('Phone'), '1234 5678');
    await tester.enterText(field('Address line 1'), '1 Street');
    await tester.enterText(field('Postal code'), '01a89');
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: field('Postal code'),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      '0189',
    );
    await tester.ensureVisible(find.text('Save Address'));
    await tester.tap(find.text('Save Address'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an 8-digit Singapore number'), findsOneWidget);
    expect(find.text('Enter the 6-digit postal code'), findsOneWidget);
    expect(repo.created, isEmpty);

    await tester.enterText(field('Phone'), '+65 9123-4567');
    await tester.enterText(field('Postal code'), '0189561');
    await tester.ensureVisible(find.text('Save Address'));
    await tester.tap(find.text('Save Address'));
    await tester.pumpAndSettle();
    expect(repo.created.single.phone, '91234567');
    expect(repo.created.single.postalCode, '018956');
    expect(repo.created.single.city, 'Singapore');
  });
}
