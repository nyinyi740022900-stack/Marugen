import 'dart:io';
import 'dart:async';

import 'package:marugen_app/features/auth/data/auth_repository.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/core/router/unknown_route_screen.dart';
import 'package:marugen_app/features/notifications/presentation/notifications_screen.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_screen.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_providers.dart';
import 'package:marugen_app/shared/models/app_notification.dart';

import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/core/router/splash_screen.dart';
import 'package:marugen_app/core/router/setup_required_screen.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/auth/presentation/profile_screen.dart';
import 'package:marugen_app/features/auth/presentation/login_screen.dart';
import 'package:marugen_app/features/auth/presentation/signup_screen.dart';
import 'package:marugen_app/features/auth/presentation/forgot_password_screen.dart';
import 'package:marugen_app/features/auth/presentation/reset_password_screen.dart';
import 'package:marugen_app/features/profile/presentation/address_book_screen.dart';
import 'package:marugen_app/features/profile/presentation/address_providers.dart';
import 'package:marugen_app/shared/models/address.dart';
import 'package:marugen_app/shared/models/app_user.dart';

const address = Address(
  id: 'address',
  userId: 'customer',
  label: 'Family home and weekend delivery address',
  recipientName: 'Alex Tan',
  phone: '+65 8888 9999',
  line1: '123 Very Long Road, Apartment 10',
  postalCode: '123456',
  isDefault: true,
);
final capture = Platform.environment['UI_CUSTOMER_CAPTURE'] == '1';
Widget host(
  Widget child,
  Brightness brightness, {
  double keyboard = 0,
  bool defaultAddress = true,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    currentUserIdProvider.overrideWithValue('customer'),
    isLoggedInProvider.overrideWithValue(true),
    currentAppUserProvider.overrideWith(
      (ref) async => const AppUser(
        id: 'customer',
        fullName: 'Alex Tan',
        email: 'alex@example.com',
      ),
    ),
    if (defaultAddress)
      myAddressesProvider.overrideWith((ref) async => [address]),
    ...overrides,
  ],
  child: RepaintBoundary(
    key: const ValueKey('capture'),
    child: MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: child!,
      ),
      debugShowCheckedModeBanner: false,
      home: child,
    ),
  ),
);
void size(WidgetTester tester, {double height = 640}) {
  tester.view.physicalSize = Size(320, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> shot(WidgetTester tester, String name) async {
  if (!capture) return;
  await tester.runAsync(() async {
    final context = tester.element(find.byType(Scaffold).first);
    await precacheImage(const AssetImage('assets/images/logo.png'), context);
  });
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final img = await boundary.toImage();
    final bytes = await img.toByteData(format: ImageByteFormat.png);
    await Directory('output/ui-final-customer').create(recursive: true);
    await File('output/ui-final-customer/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    img.dispose();
  });
}

void main() {
  for (final screen in [
    const LoginScreen(),
    const SignupScreen(),
    const ForgotPasswordScreen(),
    const ResetPasswordScreen(),
  ]) {
    testWidgets(
      '${screen.runtimeType} ignores repeated IME submit while pending',
      (tester) async {
        size(tester);
        final repo = _DeferredAuth();
        await tester.pumpWidget(
          host(
            screen,
            Brightness.light,
            overrides: [authRepositoryProvider.overrideWithValue(repo)],
          ),
        );
        await tester.pumpAndSettle();
        await fillAuth(tester);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.showKeyboard(find.byType(TextField).last);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        final calls = repo.calls;
        repo.pending.complete();
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final screen in [const LoginScreen(), const SignupScreen()]) {
    for (final oauth in [false, true]) {
      for (final fails in [false, true]) {
        testWidgets(
          '${screen.runtimeType} completion after back is safe oauth=$oauth failure=$fails',
          (tester) async {
            size(tester);
            final repo = _DeferredAuth();
            await tester.pumpWidget(
              host(
                Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () =>
                          Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => screen)),
                      child: const Text('Open auth'),
                    ),
                  ),
                ),
                Brightness.light,
                overrides: [authRepositoryProvider.overrideWithValue(repo)],
              ),
            );
            await tester.tap(find.text('Open auth'));
            await tester.pumpAndSettle();
            if (oauth) {
              await tester.ensureVisible(find.text('Continue with Google'));
              await tester.pumpAndSettle();
              await tester.tap(find.text('Continue with Google'));
            } else {
              await fillAuth(tester);
              await tester.testTextInput.receiveAction(TextInputAction.done);
            }
            await tester.pump();
            expect(repo.calls, 1);
            Navigator.of(tester.element(find.byType(screen.runtimeType))).pop();
            await tester.pumpAndSettle();
            expect(find.text('Open auth'), findsOneWidget);
            if (fails) {
              repo.pending.completeError(StateError('offline'));
            } else {
              repo.pending.complete();
            }
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  if (capture) {
    setUpAll(() async {
      await (FontLoader('.SF Pro Text')..addFont(
            File('/System/Library/Fonts/SFNS.ttf')
                .readAsBytes()
                .then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    });
  }
  for (final brightness in Brightness.values) {
    testWidgets('reset email failure retry success and return $brightness', (
      tester,
    ) async {
      size(tester);
      final repo = _Auth();
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ForgotPasswordScreen(),
                  ),
                ),
                child: const Text('Open reset'),
              ),
            ),
          ),
          brightness,
          overrides: [authRepositoryProvider.overrideWithValue(repo)],
        ),
      );
      await tester.tap(find.text('Open reset'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'alex@example.com');
      await tester.ensureVisible(find.text('Send Reset Link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();
      expect(repo.resetCalls, 1);
      expect(find.text('Check your email'), findsNothing);
      await tester.ensureVisible(find.text('Send Reset Link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();
      expect(repo.resetCalls, 2);
      expect(find.text('Check your email'), findsOneWidget);
      await tester.ensureVisible(find.text('Back to Login'));
      await tester.pumpAndSettle();
      await shot(tester, 'reset-success-${brightness.name}');
      await tester.tap(find.text('Back to Login'));
      await tester.pumpAndSettle();
      expect(find.text('Open reset'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('profile notification failure restores switch $brightness', (
      tester,
    ) async {
      size(tester);
      await tester.pumpWidget(
        host(
          const ProfileScreen(),
          brightness,
          overrides: [authRepositoryProvider.overrideWithValue(_Auth())],
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(SwitchListTile), 150);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(
        find.textContaining('Your notification setting was restored'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
    testWidgets('unknown route returns to shop without history $brightness', (
      tester,
    ) async {
      size(tester);
      final router = GoRouter(
        initialLocation: '/missing/a-very-long-link-that-no-longer-exists',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Shop destination')),
          ),
        ],
        errorBuilder: (_, state) => UnknownRouteScreen(uri: state.uri),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: brightness == Brightness.dark
                ? AppTheme.dark
                : AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await shot(tester, 'unknown-route-${brightness.name}');
      await tester.tap(find.text('Back to Shop'));
      await tester.pumpAndSettle();
      expect(find.text('Shop destination'), findsOneWidget);
    });
    testWidgets(
      'address failed read retries and edit modal validates $brightness',
      (tester) async {
        size(tester);
        var reads = 0;
        await tester.pumpWidget(
          host(
            const AddressBookScreen(),
            brightness,
            defaultAddress: false,
            overrides: [
              myAddressesProvider.overrideWith((ref) async {
                if (reads++ == 0) throw StateError('offline');
                return [address];
              }),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Retry'));
        await tester.pumpAndSettle();
        await shot(tester, 'address-error-${brightness.name}');
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(reads, 2);
        await tester.tap(find.text('Alex Tan'));
        await tester.pumpAndSettle();
        expect(find.text('Edit Address'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(1), '');
        expect(tester.state<FormState>(find.byType(Form)).validate(), isFalse);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save Address'));
        await tester.pumpAndSettle();
        expect(find.text('Save Address').hitTestable(), findsOneWidget);
        await shot(tester, 'address-edit-${brightness.name}');
      },
    );
    testWidgets(
      'notification failed read retries then mark all read $brightness',
      (tester) async {
        size(tester);
        _Inbox.reads = 0;
        await tester.pumpWidget(
          host(
            const NotificationsScreen(),
            brightness,
            overrides: [myNotificationsProvider.overrideWith(_Inbox.new)],
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Retry'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Mark all read'), findsOneWidget);
        await shot(tester, 'notifications-${brightness.name}');
        await tester.tap(find.byTooltip('Mark all read'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Mark all read'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('wishlist failed read retries to empty $brightness', (
      tester,
    ) async {
      size(tester);
      var reads = 0;
      await tester.pumpWidget(
        host(
          const WishlistScreen(),
          brightness,
          overrides: [
            myWishlistProvider.overrideWith((ref) async {
              if (reads++ == 0) throw StateError('offline');
              return [];
            }),
            wishlistProductIdsProvider.overrideWith(_Ids.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Retry'));
      await tester.pumpAndSettle();
      await shot(tester, 'wishlist-error-${brightness.name}');
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('Retry'), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('startup fits compact large text $brightness', (tester) async {
      size(tester, height: 300);
      await tester.pumpWidget(host(const SplashScreen(), brightness));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await shot(tester, 'splash-${brightness.name}');
    });
    testWidgets('setup instructions scroll at compact large text $brightness', (
      tester,
    ) async {
      size(tester, height: 300);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        const RepaintBoundary(
          key: ValueKey('capture'),
          child: SetupRequiredScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await shot(tester, 'setup-${brightness.name}');
    });
    testWidgets('address delete confirmation cancels safely $brightness', (
      tester,
    ) async {
      size(tester);
      await tester.pumpWidget(host(const AddressBookScreen(), brightness));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Delete address'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Cancel').hitTestable(), findsOneWidget);
      await shot(tester, 'address-delete-${brightness.name}');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Alex Tan'), findsOneWidget);
    });
    testWidgets('profile logout cancellation fits short screen $brightness', (
      tester,
    ) async {
      size(tester, height: 480);
      await tester.pumpWidget(host(const ProfileScreen(), brightness));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Log Out'), 150);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Cancel'));
      await shot(tester, 'logout-${brightness.name}');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Log out?'), findsNothing);
    });
    for (final screen in [
      const LoginScreen(),
      const SignupScreen(),
      const ForgotPasswordScreen(),
      const ResetPasswordScreen(),
    ]) {
      testWidgets(
        '${screen.runtimeType} invalid submission stays readable $brightness',
        (tester) async {
          size(tester);
          await tester.pumpWidget(host(screen, brightness, keyboard: 250));
          await tester.pumpAndSettle();
          final form = tester.state<FormState>(find.byType(Form));
          expect(form.validate(), isFalse);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final error in [
            'Minimum 6 characters',
            'Minimum 8 characters',
          ]) {
            final finder = find.text(error);
            if (finder.evaluate().isNotEmpty) {
              expect(
                tester.renderObject<RenderParagraph>(finder).didExceedMaxLines,
                isFalse,
                reason: 'Show the full password requirement',
              );
            }
          }
          if (screen is SignupScreen) {
            final terms = find.byWidgetPredicate(
              (widget) =>
                  widget is RichText &&
                  widget.text.toPlainText().contains('By signing up'),
            );
            expect(tester.widget<RichText>(terms).textScaler.scale(12), 24);
          }
          final fields = find.byType(TextFormField);
          await tester.ensureVisible(fields.last);
          await tester.pumpAndSettle();
          await tester.tap(fields.last);
          await tester.pumpAndSettle();
          expect(tester.testTextInput.isVisible, isTrue);
          expect(tester.takeException(), isNull);
          await shot(tester, '${screen.runtimeType}-${brightness.name}');
          final actionLabel = switch (screen) {
            LoginScreen() => 'Log In',
            SignupScreen() => 'Sign Up',
            ForgotPasswordScreen() => 'Send Reset Link',
            _ => 'Update Password',
          };
          await tester.ensureVisible(find.text(actionLabel));
          await tester.pumpAndSettle();
          expect(find.text(actionLabel).hitTestable(), findsOneWidget);
          expect(
            tester.getBottomRight(find.text(actionLabel)).dy,
            lessThanOrEqualTo(390),
          );
        },
      );
    }
  }
}

class _Ids extends WishlistIdsNotifier {
  @override
  AsyncValue<Set<String>> build() => const AsyncData({});
}

class _Inbox extends NotificationsNotifier {
  static int reads = 0;
  @override
  AsyncValue<List<AppNotification>> build() => reads++ == 0
      ? AsyncError(StateError('offline'), StackTrace.current)
      : AsyncData([
          AppNotification(
            id: 'notice',
            title: 'Order shipped',
            body: 'Your order is on its way. View your tracking information in order details.',
            type: 'order_status',
            read: false,
            createdAt: DateTime(2026, 10, 23),
          ),
        ]);
  @override
  Future<void> markAllRead() async {
    state = AsyncData([
      for (final n in state.requireValue) n.copyWith(read: true),
    ]);
  }
}

class _Auth implements AuthRepository {
  int resetCalls = 0;
  @override
  Future<void> sendPasswordResetEmail(String email) async {
    if (resetCalls++ == 0) throw StateError('offline');
  }

  @override
  Future<void> updateNotificationsEnabled(bool enabled) async =>
      throw StateError('offline');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> fillAuth(WidgetTester tester) async {
  final fields = find.byType(TextField);
  for (final field in fields.evaluate().toList()) {
    final widget = field.widget as TextField;
    final label = widget.decoration?.labelText ?? '';
    await tester.enterText(
      find.byWidget(widget),
      label == 'Email'
          ? 'alex@example.com'
          : label == 'Full name'
          ? 'Alex Tan'
          : 'Password123',
    );
  }
  await tester.ensureVisible(fields.last);
  await tester.pumpAndSettle();
  await tester.tap(fields.last);
  await tester.pumpAndSettle();
}

class _DeferredAuth implements AuthRepository {
  final pending = Completer<void>();
  int calls = 0;
  Future<void> request() {
    calls++;
    return pending.future;
  }

  @override
  Future<void> signInWithEmail(String email, String password) => request();
  @override
  Future<void> signUpWithEmail(
    String email,
    String password, {
    String? fullName,
  }) => request();
  @override
  Future<void> sendPasswordResetEmail(String email) => request();
  @override
  Future<void> updatePassword(String password) => request();
  @override
  Future<void> signInWithGoogle() => request();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
