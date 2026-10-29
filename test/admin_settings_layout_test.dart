import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/settings/admin_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  var failSettings = false;
  setUp(() => failSettings = false);
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://ui-review.invalid',
      publishableKey: 'test-key',
      httpClient: MockClient(
        (request) async =>
            failSettings && request.url.path.contains('/rest/v1/settings')
            ? http.Response(
                '{"message":"Unavailable"}',
                503,
                headers: {'content-type': 'application/json'},
                request: request,
              )
            : http.Response(
                request.url.path.contains('/rest/v1/settings')
                    ? '{"shop_name":"Marugen Fish Farm","shop_phone":"+65 8888 9999"}'
                    : '{"connected":false}',
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              ),
      ),
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  testWidgets('owner settings retries a failed initial load', (tester) async {
    failSettings = true;
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AdminSettingsScreen())),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Retry'), findsOneWidget);
    failSettings = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      'owner settings stays scrollable above keyboard ${theme.brightness}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  viewInsets: const EdgeInsets.only(bottom: 250),
                ),
                child: child!,
              ),
              home: const AdminSettingsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Save Settings'),
          180,
          maxScrolls: 100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Save Settings').hitTestable(), findsOneWidget);
      },
    );
  }
}
