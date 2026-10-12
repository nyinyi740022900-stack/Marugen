import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marugen_app/features/auth/presentation/profile_screen.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/knowledge/presentation/knowledge_screen.dart';
import 'package:marugen_app/features/knowledge/presentation/knowledge_providers.dart';
import 'package:marugen_app/shared/models/knowledge.dart';
import 'package:marugen_app/features/admin/delivery/admin_delivery_screen.dart';
import 'package:marugen_app/features/admin/delivery/easyparcel_providers.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/widgets/empty_state.dart';
import 'package:marugen_app/features/shop/presentation/customer_shell.dart';

void main() {
  testWidgets('tablet rail continues toolbar below the status bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(820, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = -1;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(padding: const EdgeInsets.only(top: 24, left: 44)),
          child: child!,
        ),
        home: AdaptiveCustomerNavigation(
          index: 1,
          onSelected: (value) => selected = value,
          body: Scaffold(
            appBar: AppBar(title: const Text('Guide title')),
            body: const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pump();
    final rail = tester.getRect(find.byType(NavigationRail));
    final toolbar = tester.getRect(find.byType(AppBar));
    expect(rail.top, toolbar.bottom);
    expect(rail.top, 24 + kToolbarHeight);
    expect(rail.left, 44);
    expect(rail.width, 104);
    await tester.tap(find.text('Shop'));
    expect(selected, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet destinations stay fixed when modules change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(820, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var index = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StatefulBuilder(
          builder: (context, setState) => AdaptiveCustomerNavigation(
            index: index,
            onSelected: (value) => setState(() => index = value),
            body: Scaffold(
              appBar: AppBar(title: Text('Module $index')),
              body: const SizedBox(),
            ),
          ),
        ),
      ),
    );
    final positions = <String, Offset>{
      for (final label in ['Shop', 'Guide', 'Orders', 'Profile'])
        label: tester.getTopLeft(find.text(label)),
    };
    for (final module in ['Guide', 'Orders', 'Profile', 'Shop']) {
      await tester.tap(find.text(module));
      await tester.pumpAndSettle();
      for (final entry in positions.entries) {
        expect(
          tester.getTopLeft(find.text(entry.key)),
          entry.value,
          reason: '${entry.key} moved after switching to $module',
        );
      }
    }
    expect(tester.takeException(), isNull);
  });

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      'compact guest profile preserves login and appearance in ${theme.brightness}',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(320, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final router = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const ProfileScreen()),
            GoRoute(
              path: '/login',
              builder: (_, _) =>
                  const Scaffold(body: Text('Login destination')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              isLoggedInProvider.overrideWithValue(false),
              currentAppUserProvider.overrideWith((ref) async => null),
            ],
            child: MaterialApp.router(
              theme: theme,
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Log in to your account'), findsOneWidget);
        await tester.tap(find.byTooltip('Appearance'));
        await tester.pumpAndSettle();
        expect(find.text('Use your device appearance'), findsOneWidget);
        Navigator.of(tester.element(find.text('Use your device appearance')))
            .pop();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Log In'),
          -160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Log In'));
        await tester.pumpAndSettle();
        expect(find.text('Login destination'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
    for (final scenario in [(320.0, 2.0), (720.0, 1.4), (820.0, 2.0)]) {
      testWidgets(
        'guide fits width ${scenario.$1}, scale ${scenario.$2}, ${theme.brightness}',
        (tester) async {
          tester.view.physicalSize = Size(scenario.$1, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                varietiesProvider(null).overrideWith(
                  (ref) async => const [
                    Variety(
                      id: '1',
                      name: 'Koromo (Ai Goromo / Budo Goromo)',
                      category: 'koi',
                    ),
                    Variety(
                      id: '2',
                      name: 'Golden Crossback Arowana',
                      category: 'arowana',
                    ),
                  ],
                ),
              ],
              child: MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scenario.$2)),
                  child: child!,
                ),
                home: const KnowledgeScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Golden Crossback Arowana'), findsOneWidget);
        },
      );
    }
  }

  testWidgets(
    'tablet varieties use columns and filter without losing detail access',
    (tester) async {
      tester.view.physicalSize = const Size(820, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            varietiesProvider(null).overrideWith(
              (ref) async => const [
                Variety(id: '1', name: 'Kohaku', category: 'koi'),
                Variety(id: '2', name: 'Super Red', category: 'arowana'),
              ],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const KnowledgeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Kohaku')).dy,
        tester.getTopLeft(find.text('Super Red')).dy,
      );
      await tester.tap(find.byKey(const ValueKey('variety-filter-arowana')));
      await tester.pumpAndSettle();
      expect(find.text('Kohaku'), findsNothing);
      tester.view.physicalSize = const Size(620, 1000);
      await tester.pumpAndSettle();
      expect(find.text('Kohaku'), findsNothing);
      tester.view.physicalSize = const Size(820, 1000);
      await tester.pumpAndSettle();
      expect(find.text('Kohaku'), findsNothing);
      await tester.tap(find.text('Super Red'));
      await tester.pumpAndSettle();
      expect(find.text('Super Red'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('fulfillment identifies the order before secondary actions', (
    tester,
  ) async {
    final order = Order(
      id: 'order-12345',
      userId: 'customer',
      status: OrderStatus.paid,
      total: 20,
      createdAt: DateTime(2026, 10, 10),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminOrdersProvider.overrideWith((ref) async => [order]),
          easyParcelConnectedProvider.overrideWith((ref) async => true),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: AdminDeliveryPane()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Order #${order.displayNumber}')).dy,
      lessThan(tester.getTopLeft(find.text('Print Packing Slip')).dy),
    );
    expect(find.text('Add tracking number'), findsOneWidget);
    expect(find.text('Mark as delivered'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('tablet empty-state actions remain bounded', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: EmptyState(
            icon: Icons.person,
            title: 'Account',
            actionLabel: 'Log In',
            onAction: () {},
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(ElevatedButton)).width,
      lessThanOrEqualTo(480),
    );
  });
}
