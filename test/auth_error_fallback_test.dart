// Code review 22 Nov 2026, auth: each auth screen has its own last-resort
// error line, an expired reset link says so (with a way back to Forgot
// password), and "this email already has an account" is recognised from the
// error itself, not from the copy shown for it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/data/auth_repository.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/auth/presentation/forgot_password_screen.dart';
import 'package:marugen_app/features/auth/presentation/login_screen.dart';
import 'package:marugen_app/features/auth/presentation/reset_password_screen.dart';
import 'package:marugen_app/features/auth/presentation/signup_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const alreadyRegistered =
    'An account with this email already exists. Log in, or use Forgot '
    'password.';
const expired =
    'This reset link has expired. Request a new one from Forgot password.';
const unknown = AuthException('boom', statusCode: '500');

class _Auth implements AuthRepository {
  Object? error;
  int signOuts = 0;

  @override
  Future<bool> signUpWithEmail(
    String email,
    String password, {
    String? fullName,
  }) async => throw error!;

  @override
  Future<void> signInWithEmail(String email, String password) async =>
      throw error!;

  @override
  Future<void> sendPasswordResetEmail(String email) async => throw error!;

  @override
  Future<void> updatePassword(String newPassword) async => throw error!;

  @override
  Future<void> signOut() async => signOuts++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder _field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

Future<GoRouter> _pump(
  WidgetTester tester,
  _Auth auth, {
  required String location,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, _) => const ResetPasswordScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _logIn(WidgetTester tester) async {
  await tester.enterText(_field('Email'), 'alex@example.com');
  await tester.enterText(_field('Password'), 'Password123');
  await tester.ensureVisible(find.text('Log In'));
  await tester.tap(find.text('Log In'));
  await tester.pumpAndSettle();
}

Future<void> _signUp(WidgetTester tester) async {
  await tester.enterText(_field('Full name'), 'Alex Tan');
  await tester.enterText(_field('Email'), 'alex@example.com');
  await tester.enterText(_field('Password'), 'Password123');
  await tester.ensureVisible(find.text('Sign Up'));
  await tester.tap(find.text('Sign Up'));
  await tester.pumpAndSettle();
}

Future<void> _sendReset(WidgetTester tester) async {
  await tester.enterText(_field('Email'), 'alex@example.com');
  await tester.tap(find.text('Send Reset Link'));
  await tester.pumpAndSettle();
}

Future<void> _setPassword(WidgetTester tester) async {
  await tester.enterText(_field('New password'), 'Password123');
  await tester.enterText(_field('Confirm password'), 'Password123');
  await tester.tap(find.text('Update Password'));
  await tester.pumpAndSettle();
}

void main() {
  group('an unrecognised failure reads for the screen it is on', () {
    test('each screen has its own line', () {
      expect(
        friendlyAuthError(unknown, AuthErrorScreen.login),
        'Could not log in. Please try again.',
      );
      expect(
        friendlyAuthError(unknown, AuthErrorScreen.signUp),
        'Could not create your account. Please try again.',
      );
      expect(
        friendlyAuthError(unknown, AuthErrorScreen.forgotPassword),
        'Could not send the reset email. Please try again.',
      );
      expect(
        friendlyAuthError(unknown, AuthErrorScreen.resetPassword),
        'Could not change your password. Please try again.',
      );
      // A failure that is not an AuthException falls back the same way.
      expect(
        friendlyAuthError(StateError('x'), AuthErrorScreen.signUp),
        'Could not create your account. Please try again.',
      );
    });

    testWidgets('log in', (tester) async {
      await _pump(tester, _Auth()..error = unknown, location: '/login');
      await _logIn(tester);
      expect(find.text('Could not log in. Please try again.'), findsOneWidget);
    });

    testWidgets('sign up', (tester) async {
      await _pump(tester, _Auth()..error = unknown, location: '/signup');
      await _signUp(tester);
      expect(
        find.text('Could not create your account. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('Could not log in'), findsNothing);
    });

    testWidgets('forgot password', (tester) async {
      await _pump(
        tester,
        _Auth()..error = unknown,
        location: '/forgot-password',
      );
      await _sendReset(tester);
      expect(
        find.text('Could not send the reset email. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('Could not log in'), findsNothing);
    });

    testWidgets('set new password', (tester) async {
      await _pump(tester, _Auth()..error = unknown, location: '/reset-password');
      await _setPassword(tester);
      expect(
        find.text('Could not change your password. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('Could not log in'), findsNothing);
      expect(find.text('Go to Forgot password'), findsNothing);
    });
  });

  group('an expired reset link', () {
    test('is recognised by the codes and exceptions gotrue really uses', () {
      final errors = <AuthException>[
        const AuthException(
          'Email link is invalid or has expired',
          statusCode: '403',
          code: 'otp_expired',
        ),
        const AuthException(
          'Session from session_id claim in JWT does not exist',
          statusCode: '403',
          code: 'session_not_found',
        ),
        const AuthException('x', code: 'session_missing'),
        const AuthException('x', code: 'session_expired'),
        const AuthException('x', code: 'flow_state_expired'),
        const AuthException('x', code: 'flow_state_not_found'),
        // What updateUser throws with no session: status 400, no code.
        AuthSessionMissingException(),
        const AuthException('Auth session missing!', statusCode: '400'),
      ];
      for (final error in errors) {
        for (final screen in AuthErrorScreen.values) {
          expect(
            friendlyAuthError(error, screen),
            expired,
            reason: '$error on ${screen.name}',
          );
        }
        expect(isExpiredResetLinkError(error), isTrue, reason: '$error');
      }
    });

    test('a 401 / 403 means it only while setting the new password', () {
      for (final error in const [
        AuthException('JWT expired', statusCode: '403', code: 'bad_jwt'),
        AuthException('invalid JWT', statusCode: '401'),
      ]) {
        expect(
          friendlyAuthError(error, AuthErrorScreen.resetPassword),
          expired,
        );
        expect(isExpiredResetLinkError(error, duringRecovery: true), isTrue);
        expect(isExpiredResetLinkError(error), isFalse);
        expect(
          friendlyAuthError(error, AuthErrorScreen.login),
          'Could not log in. Please try again.',
        );
      }
    });

    test('other failures on that screen are not mistaken for it', () {
      const same = AuthException('x', statusCode: '422', code: 'same_password');
      expect(isExpiredResetLinkError(same, duringRecovery: true), isFalse);
      expect(
        friendlyAuthError(same, AuthErrorScreen.resetPassword),
        "Choose a password you haven't used before.",
      );
      expect(isExpiredResetLinkError(unknown, duringRecovery: true), isFalse);
      expect(
        isExpiredResetLinkError(StateError('x'), duringRecovery: true),
        isFalse,
      );
    });

    testWidgets('the reset screen says so and leads back to Forgot password', (
      tester,
    ) async {
      final auth = _Auth()..error = AuthSessionMissingException();
      final router = await _pump(tester, auth, location: '/reset-password');
      expect(find.text('Go to Forgot password'), findsNothing);
      await _setPassword(tester);

      expect(find.text(expired), findsOneWidget);
      await tester.tap(find.text('Go to Forgot password'));
      await tester.pumpAndSettle();

      // The recovery session is ended, or the router would hold the screen.
      expect(auth.signOuts, 1);
      expect(router.routeInformationProvider.value.uri.path, '/forgot-password');
      expect(find.text('Forgot your password?'), findsOneWidget);
    });

    testWidgets('a 403 while setting the password is the same state', (
      tester,
    ) async {
      final auth = _Auth()
        ..error = const AuthException('x', statusCode: '403', code: 'bad_jwt');
      await _pump(tester, auth, location: '/reset-password');
      await _setPassword(tester);
      expect(find.text(expired), findsOneWidget);
      expect(find.text('Go to Forgot password'), findsOneWidget);
    });
  });

  test('the email send limit says to wait', () {
    expect(
      friendlyAuthError(
        const AuthException('x', code: 'over_email_send_rate_limit'),
        AuthErrorScreen.forgotPassword,
      ),
      'Too many attempts. Wait a minute and try again.',
    );
  });

  group('"this email already has an account"', () {
    test('is told from the error, not from the copy', () {
      expect(
        isEmailAlreadyRegisteredError(const EmailAlreadyRegisteredException()),
        isTrue,
      );
      for (final code in ['user_already_exists', 'email_exists']) {
        expect(
          isEmailAlreadyRegisteredError(
            AuthException('anything', statusCode: '422', code: code),
          ),
          isTrue,
          reason: code,
        );
        expect(
          friendlyAuthError(
            AuthException('anything', code: code),
            AuthErrorScreen.signUp,
          ),
          alreadyRegistered,
        );
      }
      // The same words from somewhere else are not that error.
      expect(
        isEmailAlreadyRegisteredError(
          const AuthRepositoryException(alreadyRegistered),
        ),
        isFalse,
      );
      expect(isEmailAlreadyRegisteredError(unknown), isFalse);
      expect(
        isEmailAlreadyRegisteredError(
          const AuthException('already exists', code: 'weak_password'),
        ),
        isFalse,
      );
      expect(isEmailAlreadyRegisteredError(Exception(alreadyRegistered)), isFalse);
    });

    testWidgets('a different error that happens to carry the same words '
        'offers no Go to Log In', (tester) async {
      final auth = _Auth()
        ..error = const AuthRepositoryException(alreadyRegistered);
      await _pump(tester, auth, location: '/signup');
      await _signUp(tester);
      expect(find.text(alreadyRegistered), findsOneWidget);
      expect(find.text('Go to Log In'), findsNothing);
    });

    testWidgets('the email_exists code lands in the Go to Log In state', (
      tester,
    ) async {
      final auth = _Auth()
        ..error = const AuthException('x', statusCode: '422', code: 'email_exists');
      await _pump(tester, auth, location: '/signup');
      await _signUp(tester);
      expect(find.text(alreadyRegistered), findsOneWidget);
      expect(find.text('Go to Log In'), findsOneWidget);
    });
  });
}
