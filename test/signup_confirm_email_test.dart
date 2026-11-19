import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/data/auth_repository.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/auth/presentation/signup_screen.dart';

class _Auth implements AuthRepository {
  _Auth({this.needsConfirmation = true});
  final bool needsConfirmation;
  final resentTo = <String?>[];
  Completer<void>? heldResend;
  Object? resendError;

  @override
  Future<bool> signUpWithEmail(
    String email,
    String password, {
    String? fullName,
  }) async => needsConfirmation;

  @override
  Future<void> resendVerificationEmail({String? email}) async {
    resentTo.add(email);
    await heldResend?.future;
    if (resendError != null) throw resendError!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<GoRouter> _pump(
  WidgetTester tester,
  _Auth auth, {
  String location = '/signup',
  bool fromLogin = false,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: fromLogin ? '/login?redirect=%2Fcart' : location,
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, state) => Scaffold(
          body: Text('login:${state.uri.queryParameters['redirect']}'),
        ),
      ),
      GoRoute(
        path: '/signup',
        builder: (_, _) =>
            const SignupScreen(resendCooldown: Duration(seconds: 30)),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
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
  if (fromLogin) {
    router.push(location);
    await tester.pumpAndSettle();
  }
  return router;
}

Future<void> _signUp(WidgetTester tester) async {
  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  await tester.enterText(field('Full name'), 'Alex Tan');
  await tester.enterText(field('Email'), ' alex@example.com ');
  await tester.enterText(field('Password'), 'Password123');
  await tester.ensureVisible(find.text('Sign Up'));
  await tester.tap(find.text('Sign Up'));
  await tester.pump();
  await tester.pump();
}

// By type: while sending, the label gives way to a spinner.
OutlinedButton _resendButton(WidgetTester tester) =>
    tester.widget(find.byType(OutlinedButton));

void main() {
  testWidgets('sign-up that needs confirmation replaces the form with the '
      'confirm-your-email state', (tester) async {
    await _pump(tester, _Auth());
    await _signUp(tester);
    expect(find.text('Confirm your email'), findsOneWidget);
    expect(
      find.text(
        'We sent a link to alex@example.com. Open it, then come back and '
        'log in.',
      ),
      findsOneWidget,
    );
    expect(find.text('Go to Log In'), findsOneWidget);
    // The form is gone: nothing left to fill in or submit twice.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Sign Up'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign-up that returns a session keeps the form for the router '
      'to move on from', (tester) async {
    await _pump(tester, _Auth(needsConfirmation: false));
    await _signUp(tester);
    expect(find.text('Confirm your email'), findsNothing);
    expect(find.text('Sign Up'), findsOneWidget);
  });

  testWidgets('Go to Log In keeps the redirect from a direct link', (
    tester,
  ) async {
    await _pump(tester, _Auth(), location: '/signup?redirect=%2Fcart');
    await _signUp(tester);
    await tester.tap(find.text('Go to Log In'));
    await tester.pumpAndSettle();
    expect(find.text('login:/cart'), findsOneWidget);
  });

  testWidgets('Go to Log In returns to the Log In screen it came from', (
    tester,
  ) async {
    final router = await _pump(
      tester,
      _Auth(),
      location: '/signup?redirect=%2Fcart',
      fromLogin: true,
    );
    await _signUp(tester);
    await tester.tap(find.text('Go to Log In'));
    await tester.pumpAndSettle();
    expect(find.text('login:/cart'), findsOneWidget);
    expect(router.canPop(), isFalse, reason: 'no second Log In was stacked');
  });

  testWidgets('Resend waits out the cooldown, sends once per tap, confirms '
      'and cools down again', (tester) async {
    final auth = _Auth();
    await _pump(tester, auth);
    await _signUp(tester);

    // The sign-up email just went out, so resend starts cooling down.
    expect(find.text('Resend email in 30s'), findsOneWidget);
    expect(_resendButton(tester).onPressed, isNull);
    await tester.pump(const Duration(seconds: 29));
    expect(find.text('Resend email in 1s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend email'), findsOneWidget);

    auth.heldResend = Completer<void>();
    await tester.tap(find.text('Resend email'));
    await tester.pump();
    // In flight: the button is disabled, a second tap sends nothing.
    expect(_resendButton(tester).onPressed, isNull);
    await tester.tap(find.byType(OutlinedButton), warnIfMissed: false);
    await tester.pump();
    expect(auth.resentTo, ['alex@example.com']);

    auth.heldResend!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Email sent again.'), findsOneWidget);
    expect(find.text('Resend email in 30s'), findsOneWidget);
    expect(_resendButton(tester).onPressed, isNull);

    // Leaving mid-cooldown must not leave a timer running.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed resend shows friendly copy and can be retried', (
    tester,
  ) async {
    final auth = _Auth()..resendError = const SocketException('offline');
    await _pump(tester, auth);
    await _signUp(tester);
    await tester.pump(const Duration(seconds: 30));
    await tester.tap(find.text('Resend email'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Network problem — check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('SocketException'), findsNothing);
    expect(find.text('Email sent again.'), findsNothing);
    // No cooldown after a failure: the customer can try again at once.
    expect(_resendButton(tester).onPressed, isNotNull);

    auth.resendError = null;
    await tester.tap(find.text('Resend email'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Email sent again.'), findsOneWidget);
    expect(find.textContaining('Network problem'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('confirm state fits a small phone at double text size', (
    tester,
  ) async {
    await _pump(tester, _Auth(), size: const Size(320, 600), textScale: 2);
    await _signUp(tester);
    expect(find.text('Confirm your email'), findsOneWidget);
    await tester.ensureVisible(find.textContaining('Resend email'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
