// Opt-in: synthetic owner/staff credentials and the disposable local backend.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marugen_app/core/config/env.dart';
import 'package:marugen_app/core/router/app_router.dart';
import 'package:marugen_app/core/supabase/supabase_client.dart';
import 'package:marugen_app/features/admin/admin_shell.dart';
import 'package:marugen_app/features/admin/products/admin_product_edit_screen.dart';
import 'package:marugen_app/main.dart' as app;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android local admin modules and product save', (tester) async {
    await dotenv.load(fileName: '.env');
    // Loopback only: Android emulator host alias or iOS simulator localhost.
    expect(
      Env.supabaseUrl,
      anyOf('http://10.0.2.2:54321', 'http://127.0.0.1:54321'),
    );
    const email = String.fromEnvironment('LOCAL_TEST_EMAIL');
    const password = String.fromEnvironment('LOCAL_TEST_PASSWORD');
    const role = String.fromEnvironment('LOCAL_TEST_ROLE');
    expect(email, endsWith('@example.invalid'));
    expect(['owner', 'staff'], contains(role));
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
    await SupabaseService.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    await tester.pumpWidget(const ProviderScope(child: app.MarugenApp()));
    for (var i = 0; i < 90 && find.byType(AdminShell).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byType(AdminShell), findsOneWidget);
    // Paginated lists contain intentional looping loaders. Wait bounded
    // frames, and assert concrete state/data below instead of requiring
    // every offscreen animation to become idle.
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    debugPrint('ADMIN_STEP: shell ready');
    WidgetController.hitTestWarningShouldBeFatal = true;
    await settle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pump(const Duration(seconds: 1));

    Future<void> nav(String label) async {
      await tester.tap(
        find
            .descendant(
              of: find.byType(NavigationBar),
              matching: find.text(label),
            )
            .hitTestable(),
      );
      await settle();
    }

    Future<void> more(String label) async {
      final destinations = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byType(NavigationDestination),
      );
      await tester.tap(destinations.last);
      await settle();
      await tester.tap(find.widgetWithText(ListTile, label).hitTestable());
      await settle();
    }

    final homeTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
    await binding.takeScreenshot('android-$role-dashboard');
    await nav('Products');
    debugPrint('ADMIN_STEP: products');
    await tester.tap(find.byType(FloatingActionButton).hitTestable());
    await settle();
    expect(find.byType(AdminProductEditScreen), findsOneWidget);
    final name =
        'Android $role fixture ${DateTime.now().microsecondsSinceEpoch}';
    Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tester.ensureVisible(field('Name'));
    await tester.enterText(field('Name'), name);
    await tester.ensureVisible(field('Price (SGD)'));
    await tester.enterText(field('Price (SGD)'), '10');
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await settle();
    // Scroll the editor's own list: on tablets the first Scrollable in
    // the tree is not the form, so a generic scroll left Save off-screen.
    final save = find.widgetWithText(ElevatedButton, 'Save');
    await tester.ensureVisible(save);
    await settle();
    await tester.tap(save);
    await settle();
    for (
      var i = 0;
      i < 30 && find.byType(AdminProductEditScreen).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byType(AdminProductEditScreen), findsNothing);
    final saved = await SupabaseService.client
        .from('products')
        .select()
        .eq('name', name);
    expect(saved, hasLength(1));
    expect(saved.single['price'], 10);
    await binding.takeScreenshot('android-$role-products');
    await nav('Orders');
    debugPrint('ADMIN_STEP: orders');
    for (final tab in ['Fulfillment', 'Payments', 'All']) {
      await tester.tap(find.widgetWithText(Tab, tab).hitTestable());
      await settle();
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('android-$role-orders-${tab.toLowerCase()}');
    }
    for (final label in [
      'Knowledge',
      'Promo Codes',
      'Reviews',
      'Analytics',
      'Settings',
    ]) {
      await more(label);
      debugPrint('ADMIN_STEP: $label');
      expect(
        tester.getTopLeft(find.byType(NavigationBar)).dy,
        closeTo(homeTop, 1),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.widgetWithText(ListTile, 'Appearance').hitTestable());
    await settle();
    await tester.tap(find.text('Dark').hitTestable());
    await settle();
    await binding.takeScreenshot('android-$role-settings-dark');
    await nav('Home');
    await nav('Orders');
    debugPrint('ADMIN_STEP: orders');
    expect(
      Theme.of(tester.element(find.byType(AdminShell))).brightness,
      Brightness.dark,
    );
    await binding.takeScreenshot('android-$role-orders-dark');
    await more('Settings');
    await tester.tap(find.widgetWithText(ListTile, 'Appearance').hitTestable());
    await settle();
    await tester.tap(find.text('Light').hitTestable());
    await settle();
    await tester.scrollUntilVisible(
      find.text('Log Out'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(ListTile, 'Log Out').hitTestable());
    await settle();
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Log Out').hitTestable(),
    );
    await settle();
    expect(SupabaseService.currentUser, isNull);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(app.MarugenApp)),
    );
    container.read(routerProvider).go('/admin');
    await settle();
    expect(find.byType(AdminShell), findsNothing);
    expect(find.text('Welcome back').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
