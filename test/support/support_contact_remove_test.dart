// Page review 22 Nov 2026: removing a support contact is saved and public
// at once, so it asks first.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/support/support_directory_settings.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _jwt(String userId) {
  String part(Map<String, dynamic> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': userId, 'exp': exp, 'role': 'authenticated'})}.sig';
}

void main() {
  final writes = <Map<String, dynamic>>[];
  setUp(writes.clear);
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://support-remove.invalid',
      publishableKey: 'test-key',
      httpClient: MockClient((request) async {
        http.Response json(Object body) => http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
        if (request.url.path.contains('/auth/v1/token')) {
          return json({
            'access_token': _jwt('owner'),
            'token_type': 'bearer',
            'expires_in': 3600,
            'refresh_token': 'refresh',
            'user': {
              'id': 'owner',
              'aud': 'authenticated',
              'email': 'owner@example.com',
              'app_metadata': <String, dynamic>{},
              'user_metadata': <String, dynamic>{},
              'created_at': '2026-01-01T00:00:00Z',
            },
          });
        }
        if (request.url.path.contains('/rest/v1/settings')) {
          if (request.method != 'GET') {
            final body = jsonDecode(request.body);
            writes.add(
              ((body is List ? body.single : body) as Map)
                  .cast<String, dynamic>(),
            );
            return json([]);
          }
          return json({
            'support_contacts': [
              {
                'id': 'c1',
                'name': 'Aung',
                'category': 'Orders and delivery',
                'phone': '+6581234567',
              },
              {
                'id': 'c2',
                'name': 'Mei',
                'category': 'Fish health',
                'phone': '+6587654321',
              },
            ],
          });
        }
        return json({});
      }),
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
    await Supabase.instance.client.auth.setSession('refresh');
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets('Remove asks with the contact\'s name; only "Remove" in the '
      'dialog saves the shorter list', (tester) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAppUserProvider.overrideWith(
            (ref) async => const AppUser(id: 'owner', role: UserRole.owner),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SupportDirectorySettingsTile()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support contacts'));
    await tester.pumpAndSettle();
    expect(find.text('Aung'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Remove').first);
    await tester.pumpAndSettle();
    expect(find.text('Remove Aung?'), findsOneWidget);
    expect(
      find.text('Customers will no longer see this contact.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    expect(find.text('Aung'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Remove').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove').last);
    await tester.pumpAndSettle();
    final saved = writes.single['support_contacts'] as List;
    expect([for (final c in saved) (c as Map)['name']], ['Mei']);
    expect(find.text('Aung'), findsNothing);
  });
}
