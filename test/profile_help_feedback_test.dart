import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/auth/presentation/profile_screen.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/shared/providers/app_version_provider.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:marugen_app/shared/widgets/support_contact_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _version = AppVersion(version: '1.0.27', build: '32');

List<Override> _overrides({required bool signedIn, AppVersion? version}) => [
  isLoggedInProvider.overrideWithValue(signedIn),
  currentUserIdProvider.overrideWithValue(signedIn ? 'customer' : null),
  currentAppUserProvider.overrideWith(
    (ref) async =>
        signedIn ? AppUser(id: 'customer', email: 'alex@example.com') : null,
  ),
  shopSettingsProvider.overrideWith(
    (ref) async => {'shop_phone': '+6588889999'},
  ),
  appVersionProvider.overrideWith(
    (ref) async => version ?? (throw StateError('no platform')),
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  required bool signedIn,
  AppVersion? version = _version,
  Size size = const Size(360, 800),
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const ProfileScreen()),
      for (final page in ['faq', 'terms', 'privacy', 'login'])
        GoRoute(
          path: '/$page',
          builder: (_, _) => Scaffold(body: Text('page:$page')),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(signedIn: signedIn, version: version),
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapRow(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(
    find.text(title),
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  test('feedback message names the version and build', () {
    expect(
      feedbackMessagePrefix(_version),
      'Feedback on Marugen app 1.0.27 (32): ',
    );
    expect(feedbackMessagePrefix(null), 'Feedback on Marugen app: ');
    expect(const AppVersion(version: '1.0.27', build: '').label, '1.0.27');
  });

  for (final signedIn in [false, true]) {
    final who = signedIn ? 'signed-in customer' : 'guest';

    testWidgets('$who sees help, legal, feedback and the version', (
      tester,
    ) async {
      await _pump(tester, signedIn: signedIn);
      expect(
        find.text('Log in to your account'),
        signedIn ? findsNothing : findsOneWidget,
      );
      for (final title in [
        'FAQ & Support',
        'Send feedback',
        'Terms of Service',
        'Privacy Policy',
      ]) {
        await tester.scrollUntilVisible(
          find.text(title),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(title), findsOneWidget);
      }
      await tester.scrollUntilVisible(
        find.text('Version 1.0.27 (32)'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Version 1.0.27 (32)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$who can open FAQ, Terms and Privacy', (tester) async {
      for (final (title, page) in [
        ('FAQ & Support', 'faq'),
        ('Terms of Service', 'terms'),
        ('Privacy Policy', 'privacy'),
      ]) {
        await _pump(tester, signedIn: signedIn);
        await _tapRow(tester, title);
        expect(find.text('page:$page'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('$who sends feedback through the support picker with the '
        'version prefilled', (tester) async {
      await _pump(tester, signedIn: signedIn);
      await _tapRow(tester, 'Send feedback');
      expect(find.text('Contact Support'), findsOneWidget);
      final picker = tester.widget<SupportContactPicker>(
        find.byType(SupportContactPicker),
      );
      expect(picker.message, 'Feedback on Marugen app 1.0.27 (32): ');
      // Not withheld from a guest: nothing in it belongs to an account.
      expect(find.textContaining('Account changed'), findsNothing);
      expect(find.text('WhatsApp'), findsOneWidget);
    });
  }

  testWidgets('a platform that cannot report the version hides the footer '
      'and still lets feedback through', (tester) async {
    await _pump(tester, signedIn: false, version: null);
    expect(find.textContaining('Version'), findsNothing);
    await _tapRow(tester, 'Send feedback');
    expect(
      tester
          .widget<SupportContactPicker>(find.byType(SupportContactPicker))
          .message,
      'Feedback on Marugen app: ',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest profile fits a small phone at double text size', (
    tester,
  ) async {
    await _pump(
      tester,
      signedIn: false,
      size: const Size(320, 600),
      textScale: 2,
    );
    await tester.scrollUntilVisible(
      find.text('Version 1.0.27 (32)'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an order message is still withheld from a guest', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(signedIn: false),
        child: const MaterialApp(
          home: Scaffold(body: SupportContactPicker(message: 'Order #123')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('WhatsApp'), findsNothing);
    expect(find.textContaining('Account changed'), findsOneWidget);
  });
}
