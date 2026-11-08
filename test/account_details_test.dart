import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/auth/data/auth_repository.dart';
import 'package:marugen_app/features/auth/presentation/account_details_tiles.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';

class RecordingAuth implements AuthRepository {
  final names = <String>[];
  final passwords = <String>[];
  @override
  Future<void> updateFullName(String fullName) async => names.add(fullName);
  @override
  Future<void> updatePassword(String newPassword) async =>
      passwords.add(newPassword);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> showTiles(
  WidgetTester tester,
  RecordingAuth auth, {
  bool usesPassword = true,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      currentAppUserProvider.overrideWith((ref) async => null),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: AccountDetailsTiles(
          fullName: 'Old Name',
          usesPassword: usesPassword,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('a customer can fix their name and change their password', (
    tester,
  ) async {
    final auth = RecordingAuth();
    await showTiles(tester, auth);

    await tester.tap(find.text('Edit name'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Old Name'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '  Aung Aung  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(auth.names, ['Aung Aung']);
    expect(find.text('Name updated.'), findsOneWidget);

    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'short');
    await tester.enterText(fields.at(1), 'short');
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.text('Minimum 8 characters'), findsOneWidget);
    await tester.enterText(fields.at(0), 'koifish88');
    await tester.enterText(fields.at(1), 'koifish89');
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);
    await tester.enterText(fields.at(1), 'koifish88');
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(auth.passwords, ['koifish88']);
    expect(find.text('Password changed.'), findsOneWidget);
  });

  testWidgets('Google and Apple accounts have no password to change', (
    tester,
  ) async {
    await showTiles(tester, RecordingAuth(), usesPassword: false);
    expect(find.text('Edit name'), findsOneWidget);
    expect(find.text('Change password'), findsNothing);
  });
}
