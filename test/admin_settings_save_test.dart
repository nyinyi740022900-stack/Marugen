// Page review 22 Nov 2026, admin Settings: a shop with a sender postcode
// can save, the postcode problem shows on its field, and typed text is
// guarded without Settings catching Android back on other tabs.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marugen_app/features/admin/admin_shell.dart';
import 'package:marugen_app/features/admin/settings/admin_settings_screen.dart';
import 'package:marugen_app/shared/widgets/back_to_first_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Finder field(String label, {bool offstage = false}) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
  skipOffstage: !offstage,
);

/// The shell's back handling around two tabs: a placeholder Home and the
/// real Settings screen, kept alive in an IndexedStack as in AdminShell.
class _MiniShell extends ConsumerWidget {
  const _MiniShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(adminTabIndexProvider);
    return BackToFirstTab(
      index: index,
      onBackToFirst: () => adminShellBackToHome(ref),
      child: IndexedStack(
        index: index == kAdminSettingsTab ? 2 : index,
        children: const [
          Scaffold(body: Text('home tab')),
          Scaffold(body: Text('products tab')),
          AdminSettingsScreen(),
        ],
      ),
    );
  }
}

void main() {
  final settingsWrites = <http.Request>[];
  setUp(settingsWrites.clear);
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://settings-save.invalid',
      publishableKey: 'test-key',
      httpClient: MockClient((request) async {
        final settings = request.url.path.contains('/rest/v1/settings');
        if (settings && request.method != 'GET') settingsWrites.add(request);
        return http.Response(
          settings
              ? jsonEncode({
                  'shop_name': 'Marugen Fish Farm',
                  'shop_phone': '+65 8888 9999',
                  'gst_percent': 9,
                  'shop_postcode': '738343',
                })
              : '{"connected":false}',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<ProviderContainer> open(WidgetTester tester, {int tab = 6}) async {
    tester.view.physicalSize = const Size(400, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [adminTabIndexProvider.overrideWith((ref) => tab)],
        child: const MaterialApp(home: _MiniShell()),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(_MiniShell)));
  }

  Map<dynamic, dynamic> lastWrite() {
    final body = jsonDecode(settingsWrites.last.body);
    return (body is List ? body.single : body) as Map;
  }

  testWidgets('settings save when the sender postcode is filled in', (
    tester,
  ) async {
    await open(tester);
    expect(
      tester.widget<TextField>(field('Postcode')).controller!.text,
      '738343',
    );
    await tester.enterText(field('Phone'), '+65 9000 1111');
    await tester.tap(find.text('Save Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings saved'), findsOneWidget);
    expect(lastWrite()['shop_postcode'], '738343');
    expect(lastWrite()['shop_phone'], '+65 9000 1111');
  });

  testWidgets('the postcode takes six digits only, and a short one is '
      'explained on the field without saving', (tester) async {
    await open(tester);
    await tester.enterText(field('Postcode'), '73 83-43999');
    await tester.pump();
    expect(
      tester.widget<TextField>(field('Postcode')).controller!.text,
      '738343',
    );
    final formatters = tester
        .widget<TextField>(field('Postcode'))
        .inputFormatters!;
    expect(
      formatters.whereType<LengthLimitingTextInputFormatter>().single.maxLength,
      6,
    );

    await tester.enterText(field('Postcode'), '7383');
    await tester.tap(find.text('Save Settings'));
    await tester.pumpAndSettle();
    expect(settingsWrites, isEmpty);
    expect(
      tester.widget<TextField>(field('Postcode')).decoration!.errorText,
      'Shop postcode must be 6 digits (Singapore).',
    );
    // Typing clears the field error again.
    await tester.enterText(field('Postcode'), '73834');
    await tester.pump();
    expect(
      tester.widget<TextField>(field('Postcode')).decoration!.errorText,
      isNull,
    );
  });

  testWidgets('typed text is guarded: Android back on Settings asks before '
      'leaving, and Discard puts the saved values back', (tester) async {
    final container = await open(tester);
    await tester.enterText(field('Shop name'), 'Typed but not saved');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(adminTabIndexProvider), kAdminSettingsTab);
    expect(
      tester.widget<TextField>(field('Shop name')).controller!.text,
      'Typed but not saved',
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(container.read(adminTabIndexProvider), 0);
    expect(
      tester
          .widget<TextField>(field('Shop name', offstage: true))
          .controller!
          .text,
      'Marugen Fish Farm',
    );
    expect(container.read(adminSettingsLeaveGuardProvider), isNull);
  });

  testWidgets('unsaved Settings do not catch Android back on another tab', (
    tester,
  ) async {
    final container = await open(tester);
    await tester.enterText(
      field('Shop name', offstage: true),
      'Typed but not saved',
    );
    await tester.pump();
    container.read(adminTabIndexProvider.notifier).state = 1;
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(container.read(adminTabIndexProvider), 0);
    // Nothing was thrown away: the tab keeps its edits.
    expect(
      tester
          .widget<TextField>(field('Shop name', offstage: true))
          .controller!
          .text,
      'Typed but not saved',
    );
  });
}
