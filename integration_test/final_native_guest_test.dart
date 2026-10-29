import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:marugen_app/core/config/env.dart';

import 'support/read_only_http_client.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
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
    'native guest navigation, input focus and login validation remain usable',
    (tester) async {
      // Exercise the production app/router without installing crash handlers
      // that would intercept the integration runner's assertion reporting.
      await dotenv.load(fileName: '.env');
      final readOnlyClient = ReadOnlyHttpClient(http.Client());
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabaseAnonKey,
        httpClient: readOnlyClient,
      );
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
      await binding.takeScreenshot('native-shop');

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
      final profileLoginRect = tester.getRect(
        find.text('Log In').hitTestable(),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.byIcon(Icons.receipt_long_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Log in to your account').hitTestable(), findsOneWidget);
      final orderLoginRect = tester.getRect(find.text('Log In').hitTestable());
      expect(orderLoginRect.top, closeTo(profileLoginRect.top, 1));
      expect(orderLoginRect.width, profileLoginRect.width);
      await binding.takeScreenshot('native-orders-guest');
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.byIcon(Icons.person_outline),
        ),
      );
      await tester.pumpAndSettle();
      await binding.takeScreenshot('native-profile-light');

      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(ProfileScreen))).brightness,
        Brightness.dark,
      );
      await binding.takeScreenshot('native-profile-dark');
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
      await binding.takeScreenshot('native-login');
      // Native Flutter focus/action bridge; the integration runner may
      // suppress the software IME. No credentials or auth writes.
      Finder loginField(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
      await tester.ensureVisible(loginField('Email'));
      await tester.tap(loginField('Email'));
      await tester.enterText(loginField('Email'), 'invalid-email');
      await tester.pump(const Duration(seconds: 1));
      await binding.takeScreenshot('native-login-focused-input');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.ensureVisible(loginField('Password'));
      await tester.enterText(loginField('Password'), '123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(find.text('Minimum 6 characters'), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tester.pump(const Duration(seconds: 1));
      await tester.ensureVisible(find.text('Minimum 6 characters'));
      await binding.takeScreenshot('native-login-validation');

      await tester.ensureVisible(find.text('Privacy Policy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();
      expect(find.text('marugenfishfarmaiagent@gmail.com'), findsOneWidget);
      expect(find.text('Email a privacy request'), findsOneWidget);
      expect(find.textContaining('placeholder'), findsNothing);
      await binding.takeScreenshot('native-privacy-policy');
      expect(tester.takeException(), isNull);
      expect(
        readOnlyClient.blockedWrites,
        greaterThanOrEqualTo(1),
        reason:
            'Guest app-visit analytics must be intercepted rather than sent.',
      );
    },
  );
  testWidgets('native Stripe SDK initializes without a charge', (tester) async {
    expect(Env.stripePublishableKey, isNotEmpty);
    Stripe.publishableKey = Env.stripePublishableKey;
    Stripe.urlScheme = 'marugen';
    await Stripe.instance.applySettings().timeout(const Duration(seconds: 15));
    expect(tester.takeException(), isNull);
  });
}
