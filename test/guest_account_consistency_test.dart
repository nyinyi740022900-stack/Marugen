import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/core/router/app_router.dart';
import 'package:marugen_app/features/auth/presentation/profile_screen.dart';
import 'package:marugen_app/features/auth/presentation/login_screen.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/orders/presentation/orders_screen.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/notifications/presentation/notifications_screen.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_screen.dart';
import 'package:marugen_app/features/shop/presentation/shell_tab_provider.dart';
import 'package:marugen_app/shared/models/order.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('Guest account pages keep login placement and width consistent', (
    tester,
  ) async {
    viewport(tester, const Size(360, 800));
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      Rect? reference;
      for (final page in [
        const ProfileScreen(),
        const OrdersScreen(),
        const NotificationsScreen(),
        const WishlistScreen(),
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              isLoggedInProvider.overrideWithValue(false),
              currentAppUserProvider.overrideWith((ref) async => null),
            ],
            child: MaterialApp(theme: theme, home: page),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Log in to your account'), findsOneWidget);
        final rect = tester.getRect(
          find.widgetWithText(ElevatedButton, 'Log In'),
        );
        if (reference != null) {
          expect(rect.width, reference.width);
          expect(rect.top, closeTo(reference.top, 1));
        }
        reference = rect;
        expect(tester.takeException(), isNull);
      }
    }
  });
  testWidgets('Guest prompts stay readable with double text on a small phone', (
    tester,
  ) async {
    viewport(tester, const Size(320, 600));
    for (final page in [
      const ProfileScreen(),
      const OrdersScreen(),
      const NotificationsScreen(),
      const WishlistScreen(),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            isLoggedInProvider.overrideWithValue(false),
            currentAppUserProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: page,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Log In'));
      expect(find.text('Log In').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
    'Order summary supports large text without losing number or status',
    (tester) async {
      viewport(tester, const Size(320, 640));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isLoggedInProvider.overrideWithValue(true),
            myOrdersProvider.overrideWith(
              (ref) async => [
                Order(
                  id: 'order-id',
                  userId: 'fixture',
                  orderNumber: '14102026-0001',
                  status: OrderStatus.pending,
                  total: 20,
                  createdAt: DateTime(2026, 10, 14),
                ),
              ],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const OrdersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Order #14102026-0001'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
    },
  );
  testWidgets('Wishlist login return route exists in the production router', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        isLoggedInProvider.overrideWithValue(false),
        authStateProvider.overrideWith(
          (ref) => Stream.value(AuthState(AuthChangeEvent.signedOut, null)),
        ),
        currentAppUserProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);
    final router = container.read(routerProvider);
    router.go('/wishlist');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('Log in to your account'), findsOneWidget);
    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();
    expect(
      GoRouterState.of(tester.element(find.byType(LoginScreen)))
          .uri
          .queryParameters['redirect'],
      '/wishlist',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('Empty orders lets customer return to Shop', (tester) async {
    final container = ProviderContainer(
      overrides: [
        isLoggedInProvider.overrideWithValue(true),
        myOrdersProvider.overrideWith((ref) async => []),
      ],
    );
    addTearDown(container.dispose);
    container.read(customerTabIndexProvider.notifier).state = 2;
    final router = GoRouter(
      initialLocation: '/orders',
      routes: [
        GoRoute(path: '/orders', builder: (_, _) => const OrdersScreen()),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Shop destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse Shop'));
    await tester.pumpAndSettle();
    expect(find.text('Shop destination'), findsOneWidget);
    expect(container.read(customerTabIndexProvider), 0);
  });
}
