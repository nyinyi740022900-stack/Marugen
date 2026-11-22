// Page review 22 Nov 2026, auth: sign-up with an existing email, safe error
// copy on every auth screen, and error banners a screen reader announces.
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
import 'package:marugen_app/features/profile/data/address_repository.dart';
import 'package:marugen_app/features/profile/presentation/address_book_screen.dart';
import 'package:marugen_app/features/profile/presentation/address_providers.dart';
import 'package:marugen_app/shared/models/address.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const alreadyRegistered =
    'An account with this email already exists. Log in, or use Forgot '
    'password.';

class _Auth implements AuthRepository {
  Object? signUpError;
  Object? signInError;
  Object? resetError;
  Object? updateError;
  bool needsConfirmation = true;

  @override
  Future<bool> signUpWithEmail(
    String email,
    String password, {
    String? fullName,
  }) async {
    if (signUpError != null) throw signUpError!;
    return needsConfirmation;
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    if (signInError != null) throw signInError!;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    if (resetError != null) throw resetError!;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    if (updateError != null) throw updateError!;
  }

  int signOuts = 0;

  @override
  Future<void> signOut() async => signOuts++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingAddresses implements AddressRepository {
  @override
  Future<Address> createAddress(Address address) async =>
      throw Exception('duplicate key value violates unique constraint');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

User _user({List<Map<String, dynamic>>? identities}) => User.fromJson({
  'id': 'user-1',
  'app_metadata': <String, dynamic>{},
  'user_metadata': <String, dynamic>{},
  'aud': 'authenticated',
  'created_at': '2026-11-01T00:00:00Z',
  'identities': identities,
})!;

Finder _field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

/// The banner showing [message] sits in a live region.
Finder _announced(String message) => find.ancestor(
  of: find.text(message),
  matching: find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.liveRegion == true,
  ),
);

Future<GoRouter> _pumpAuth(
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
      GoRoute(
        path: '/login',
        builder: (_, state) =>
            LoginScreen(initialEmail: state.uri.queryParameters['email']),
      ),
      GoRoute(
        path: '/signup',
        builder: (_, _) =>
            const SignupScreen(resendCooldown: Duration(seconds: 30)),
      ),
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

Future<void> _signUp(WidgetTester tester) async {
  await tester.enterText(_field('Full name'), 'Alex Tan');
  await tester.enterText(_field('Email'), ' alex@example.com ');
  await tester.enterText(_field('Password'), 'Password123');
  await tester.ensureVisible(find.text('Sign Up'));
  await tester.tap(find.text('Sign Up'));
  await tester.pump();
  await tester.pump();
}

String _emailOnLogin(WidgetTester tester) =>
    tester.widget<TextField>(_field('Email')).controller!.text;

void main() {
  group('sign-up response for an address that already has an account', () {
    test('no session and an empty identities list means already registered', () {
      expect(
        signUpEmailAlreadyRegistered(AuthResponse(user: _user(identities: []))),
        isTrue,
      );
    });

    test('a new account awaiting confirmation is not', () {
      expect(
        signUpEmailAlreadyRegistered(
          AuthResponse(
            user: _user(
              identities: [
                {
                  'id': 'identity-1',
                  'user_id': 'user-1',
                  'identity_data': <String, dynamic>{},
                  'identity_id': 'identity-1',
                  'provider': 'email',
                  'created_at': '2026-11-01T00:00:00Z',
                  'last_sign_in_at': '2026-11-01T00:00:00Z',
                  'updated_at': '2026-11-01T00:00:00Z',
                },
              ],
            ),
          ),
        ),
        isFalse,
      );
      // Identities not reported at all: nothing to conclude.
      expect(signUpEmailAlreadyRegistered(AuthResponse(user: _user())), isFalse);
      expect(signUpEmailAlreadyRegistered(AuthResponse()), isFalse);
    });

    test('the exception carries the customer copy', () {
      expect(const EmailAlreadyRegisteredException().message, alreadyRegistered);
      expect(
        friendlyAuthError(const EmailAlreadyRegisteredException(), AuthErrorScreen.login),
        alreadyRegistered,
      );
    });
  });

  group('sign-up screen with an existing email', () {
    testWidgets('stays on the form with the message, never "we sent a link"', (
      tester,
    ) async {
      final auth = _Auth()
        ..signUpError = const EmailAlreadyRegisteredException();
      await _pumpAuth(tester, auth, location: '/signup');
      await _signUp(tester);

      expect(find.text('Confirm your email'), findsNothing);
      expect(find.textContaining('We sent a link'), findsNothing);
      expect(find.text(alreadyRegistered), findsOneWidget);
      expect(_announced(alreadyRegistered), findsOneWidget);
      // The form is still there to correct the address.
      expect(_field('Email'), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
      expect(find.text('Go to Log In'), findsOneWidget);
    });

    testWidgets('Go to Log In from a direct link opens Log In with the email '
        'filled in', (tester) async {
      final auth = _Auth()
        ..signUpError = const EmailAlreadyRegisteredException();
      final router = await _pumpAuth(
        tester,
        auth,
        location: '/signup?redirect=%2Fcart',
      );
      await _signUp(tester);
      await tester.ensureVisible(find.text('Go to Log In'));
      await tester.tap(find.text('Go to Log In'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(_emailOnLogin(tester), 'alex@example.com');
      final uri = router.routeInformationProvider.value.uri;
      expect(uri.path, '/login');
      expect(uri.queryParameters['redirect'], '/cart');
    });

    testWidgets('Go to Log In returns to the Log In it came from with the '
        'email filled in', (tester) async {
      final auth = _Auth()
        ..signUpError = const EmailAlreadyRegisteredException();
      await _pumpAuth(tester, auth, location: '/login?redirect=%2Fcart');
      await tester.enterText(_field('Email'), 'old@example.com');
      await tester.enterText(_field('Password'), 'something');
      await tester.ensureVisible(find.text('Sign up'));
      await tester.tap(find.text('Sign up'));
      await tester.pumpAndSettle();
      await _signUp(tester);
      await tester.ensureVisible(find.text('Go to Log In'));
      await tester.tap(find.text('Go to Log In'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(_emailOnLogin(tester), 'alex@example.com');
      expect(
        tester.widget<TextField>(_field('Password')).controller!.text,
        isEmpty,
      );
    });

    testWidgets('the confirm-your-email state also carries the email to '
        'Log In', (tester) async {
      await _pumpAuth(tester, _Auth(), location: '/signup');
      await _signUp(tester);
      expect(find.text('Confirm your email'), findsOneWidget);
      await tester.tap(find.text('Go to Log In'));
      await tester.pumpAndSettle();
      expect(_emailOnLogin(tester), 'alex@example.com');
    });

    testWidgets('a Supabase "already registered" error lands in the same '
        'state', (tester) async {
      final auth = _Auth()
        ..signUpError = const AuthException(
          'User already registered',
          statusCode: '422',
          code: 'user_already_exists',
        );
      await _pumpAuth(tester, auth, location: '/signup');
      await _signUp(tester);
      expect(find.text(alreadyRegistered), findsOneWidget);
      expect(find.text('Go to Log In'), findsOneWidget);
    });

    testWidgets('any other failure shows no Go to Log In', (tester) async {
      final auth = _Auth()
        ..signUpError = const AuthException('boom', statusCode: '500');
      await _pumpAuth(tester, auth, location: '/signup');
      await _signUp(tester);
      expect(
        find.text('Could not create your account. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Could not log in. Please try again.'), findsNothing);
      expect(find.text('Go to Log In'), findsNothing);
    });
  });

  group('auth error copy', () {
    test('a rate limit says to wait', () {
      const copy = 'Too many attempts. Wait a minute and try again.';
      expect(
        friendlyAuthError(
          const AuthException(
            'For security purposes, you can only request this after 49 '
            'seconds.',
            statusCode: '429',
            code: 'over_email_send_rate_limit',
          ),
          AuthErrorScreen.login,
        ),
        copy,
      );
      expect(
        friendlyAuthError(const AuthException('x', statusCode: '429'), AuthErrorScreen.login),
        copy,
      );
      expect(
        friendlyAuthError(
          const AuthException('x', code: 'over_request_rate_limit'),
          AuthErrorScreen.login,
        ),
        copy,
      );
    });

    test('reusing the current password has its own line', () {
      expect(
        friendlyAuthError(
          const AuthException(
            'New password should be different from the old password.',
            statusCode: '422',
            code: 'same_password',
          ),
          AuthErrorScreen.login,
        ),
        "Choose a password you haven't used before.",
      );
    });

    test('raw Supabase or database text never reaches the screen', () {
      const raw = [
        AuthException(
          'Database error saving new user: duplicate key value violates '
          'unique constraint "profiles_pkey"',
          statusCode: '500',
        ),
        AuthException('Signups not allowed for this instance'),
        AuthException('JWT expired', statusCode: '403', code: 'bad_jwt'),
      ];
      for (final error in raw) {
        expect(
          friendlyAuthError(error, AuthErrorScreen.login),
          'Could not log in. Please try again.',
          reason: error.message,
        );
      }
      // An anonymous Exception is not one AuthRepository wrote for people.
      expect(
        friendlyAuthError(Exception('PlatformException(sign_in_failed, 10)'), AuthErrorScreen.login),
        'Could not log in. Please try again.',
      );
      expect(
        friendlyAuthError(StateError('Bad state: no element'), AuthErrorScreen.login),
        'Could not log in. Please try again.',
      );
    });

    test('only AuthRepository messages pass through', () {
      expect(
        friendlyAuthError(const AuthRepositoryException('Sign-in was cancelled.'), AuthErrorScreen.login),
        'Sign-in was cancelled.',
      );
    });

    test('a build without Google sign-in says so without developer copy', () {
      expect(
        googleSignInUnavailableMessage,
        "Google sign-in isn't available right now. Use email instead.",
      );
      final shown = friendlyAuthError(
        const AuthRepositoryException(googleSignInUnavailableMessage),
        AuthErrorScreen.login,
      );
      expect(shown, googleSignInUnavailableMessage);
      expect(shown.contains('.env'), isFalse);
      expect(shown.contains('README'), isFalse);
    });

    test('known cases keep their copy', () {
      expect(
        friendlyAuthError(
          const AuthException(
            'Invalid login credentials',
            statusCode: '400',
            code: 'invalid_credentials',
          ),
          AuthErrorScreen.login,
        ),
        startsWith('Email or password is incorrect.'),
      );
      expect(
        friendlyAuthError(
          const AuthException('Email not confirmed', code: 'email_not_confirmed'),
          AuthErrorScreen.login,
        ),
        'Please confirm your email from the link we sent, then try again.',
      );
      expect(
        friendlyAuthError(
          const AuthException('Password is too weak', code: 'weak_password'),
          AuthErrorScreen.login,
        ),
        startsWith('Please choose a stronger password'),
      );
      expect(
        friendlyAuthError(Exception('SocketException: Failed host lookup'), AuthErrorScreen.login),
        'Network error — check your connection and try again.',
      );
    });
  });

  group('error banners are announced', () {
    testWidgets('log in', (tester) async {
      final auth = _Auth()
        ..signInError = const AuthException('x', statusCode: '429');
      await _pumpAuth(tester, auth, location: '/login');
      await tester.enterText(_field('Email'), 'alex@example.com');
      await tester.enterText(_field('Password'), 'Password123');
      await tester.ensureVisible(find.text('Log In'));
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle();
      const copy = 'Too many attempts. Wait a minute and try again.';
      expect(find.text(copy), findsOneWidget);
      expect(_announced(copy), findsOneWidget);
    });

    testWidgets('forgot password', (tester) async {
      final auth = _Auth()
        ..resetError = const AuthException('x', statusCode: '429');
      await _pumpAuth(tester, auth, location: '/forgot-password');
      await tester.enterText(_field('Email'), 'alex@example.com');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();
      const copy = 'Too many attempts. Wait a minute and try again.';
      expect(_announced(copy), findsOneWidget);
    });

    testWidgets('set new password', (tester) async {
      final auth = _Auth()
        ..updateError = const AuthException('x', code: 'same_password');
      await _pumpAuth(tester, auth, location: '/reset-password');
      await tester.enterText(_field('New password'), 'Password123');
      await tester.enterText(_field('Confirm password'), 'Password123');
      await tester.tap(find.text('Update Password'));
      await tester.pumpAndSettle();
      const copy = "Choose a password you haven't used before.";
      expect(find.text(copy), findsOneWidget);
      expect(_announced(copy), findsOneWidget);
    });

    testWidgets('address form', (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('customer'),
            addressRepositoryProvider.overrideWithValue(_FailingAddresses()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: AddressForm()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(_field('Recipient name'), 'Alex Tan');
      await tester.enterText(_field('Phone'), '81234567');
      await tester.enterText(_field('Address line 1'), '1 Street');
      await tester.enterText(_field('Postal code'), '123456');
      await tester.ensureVisible(find.text('Save Address'));
      await tester.tap(find.text('Save Address'));
      await tester.pumpAndSettle();
      const copy = "Couldn't save this address. Please try again.";
      expect(find.text(copy), findsOneWidget);
      expect(_announced(copy), findsOneWidget);
    });
  });
}
