import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:marugen_app/core/supabase/supabase_client.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marugen_app/main.dart' as app;
import 'package:marugen_app/features/auth/presentation/profile_screen.dart';
import 'package:marugen_app/features/shop/presentation/shop_screen.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android guest can change appearance from Profile and open login',
    (tester) async {
      // Exercise the production app/router without installing crash handlers
      // that would intercept the integration runner's assertion reporting.
      await dotenv.load(fileName: '.env');
      await SupabaseService.init();
      expect(
        SupabaseService.currentUser,
        isNull,
        reason: 'Use a signed-out emulator for this guest smoke test.',
      );
      await tester.pumpWidget(const ProviderScope(child: app.MarugenApp()));
      WidgetController.hitTestWarningShouldBeFatal = true;
      for (var i = 0; i < 120 && find.text('Shop').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('Shop'), findsOneWidget);
      expect(find.byTooltip('Appearance'), findsNothing);
      // The server-managed promotion can arrive after the first shop frame.
      await ProviderScope.containerOf(
        tester.element(find.byType(app.MarugenApp)),
      ).read(shopSettingsProvider.future);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      final promoClose = find.byTooltip('Close');
      if (promoClose.evaluate().isNotEmpty) {
        await tester.tap(promoClose);
        await tester.pumpAndSettle();
      }

      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(seconds: 1));
      await binding.takeScreenshot('android-shop');

      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.byIcon(Icons.person_outline),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Appearance'), findsOneWidget);
      expect(find.text('THIS DEVICE'), findsNothing);
      expect(find.text('Appearance'), findsNothing);
      await binding.takeScreenshot('android-profile-light');

      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(ProfileScreen))).brightness,
        Brightness.dark,
      );
      await binding.takeScreenshot('android-profile-dark');
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.byIcon(Icons.storefront_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(ShopScreen))).brightness,
        Brightness.dark,
      );
      expect(find.byTooltip('Appearance'), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.byIcon(Icons.person_outline),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google').hitTestable(), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await binding.takeScreenshot('android-login');
      expect(tester.takeException(), isNull);
    },
  );
}
