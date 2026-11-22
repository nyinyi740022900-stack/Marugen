// Admin Settings, GST: the shop is not GST-registered, so the field says to
// leave it at 0 and turning GST on is confirmed in its own words. Other GST
// changes keep the existing confirm.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marugen_app/features/admin/settings/admin_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

/// A button (or any text) inside the confirm dialog.
Finder inDialog(String text) => find.descendant(
  // AlertDialog.adaptive builds a subclass, which byType would not match.
  of: find.byWidgetPredicate((w) => w is AlertDialog),
  matching: find.text(text),
);

void main() {
  final settingsWrites = <http.Request>[];
  // What the server holds; a save stores the new rate, as the real one does.
  var storedGst = 0;
  setUp(() {
    settingsWrites.clear();
    storedGst = 0;
  });
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://settings-gst.invalid',
      publishableKey: 'test-key',
      httpClient: MockClient((request) async {
        final settings = request.url.path.contains('/rest/v1/settings');
        if (settings && request.method != 'GET') settingsWrites.add(request);
        return http.Response(
          settings
              ? jsonEncode({
                  'shop_name': 'Marugen Fish Farm',
                  'gst_percent': storedGst,
                  'gst_included_in_price': true,
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

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AdminSettingsScreen())),
    );
    await tester.pumpAndSettle();
  }

  Map<dynamic, dynamic> lastWrite() {
    final body = jsonDecode(settingsWrites.last.body);
    return (body is List ? body.single : body) as Map;
  }

  testWidgets('the GST field says to leave it at 0', (tester) async {
    await open(tester);
    expect(tester.widget<TextField>(field('GST %')).controller!.text, '0');
    expect(
      find.text('Leave at 0 unless the shop is GST-registered with IRAS.'),
      findsOneWidget,
    );
  });

  testWidgets('going from 0 to a positive rate asks "Charge GST?" and '
      'Cancel saves nothing', (tester) async {
    await open(tester);
    await tester.enterText(field('GST %'), '9');
    await tester.tap(find.text('Save Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Charge GST?'), findsOneWidget);
    expect(
      find.text(
        'Only a GST-registered business may charge GST. Prices and invoices '
        'will show GST from now on.',
      ),
      findsOneWidget,
    );
    expect(find.text('Change GST for the whole shop?'), findsNothing);
    expect(inDialog('Cancel'), findsOneWidget);
    expect(inDialog('Charge GST'), findsOneWidget);

    await tester.tap(inDialog('Cancel'));
    await tester.pumpAndSettle();
    expect(settingsWrites, isEmpty);
    expect(find.text('Settings saved'), findsNothing);

    // Asked again, and confirming saves the rate.
    await tester.tap(find.text('Save Settings'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog('Charge GST'));
    await tester.pumpAndSettle();
    expect(find.text('Settings saved'), findsOneWidget);
    expect(lastWrite()['gst_percent'], 9);
  });

  testWidgets('other GST changes keep the existing confirm', (tester) async {
    storedGst = 9;
    await open(tester);
    await tester.enterText(field('GST %'), '0');
    await tester.tap(find.text('Save Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Change GST for the whole shop?'), findsOneWidget);
    expect(find.text('Charge GST?'), findsNothing);
    expect(inDialog('Change GST'), findsOneWidget);
    await tester.tap(inDialog('Change GST'));
    await tester.pumpAndSettle();
    expect(lastWrite()['gst_percent'], 0);
  });

  testWidgets('a save that leaves GST at 0 asks nothing', (tester) async {
    await open(tester);
    await tester.enterText(field('Shop name'), 'Marugen');
    await tester.tap(find.text('Save Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Charge GST?'), findsNothing);
    expect(find.text('Change GST for the whole shop?'), findsNothing);
    expect(find.text('Settings saved'), findsOneWidget);
  });
}
