import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/orders/presentation/order_detail_screen.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/shared/models/order.dart';

Order fixture(OrderStatus status, {String? userId = 'customer'}) => Order(
  id: 'order-12345',
  userId: userId,
  status: status,
  total: 20,
  createdAt: DateTime(2026, 10, 10),
);
Future<void> showDetail(
  WidgetTester tester,
  Future<Order?> Function() fetch, {
  String? userId = 'customer',
  UserRole role = UserRole.customer,
  Order? snapshot,
  Future<AppUser?> Function()? fetchUser,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => const Stream.empty()),
        currentUserIdProvider.overrideWithValue(userId),
        currentAppUserProvider.overrideWith(
          (ref) async => fetchUser != null
              ? await fetchUser()
              : userId == null
              ? null
              : AppUser(id: userId, role: role),
        ),
        orderByIdProvider('order-12345').overrideWith((ref) => fetch()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: OrderDetailScreen(
          orderId: 'order-12345',
          order: snapshot ?? fixture(OrderStatus.paid),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('router snapshot is replaced by authoritative status', (
    tester,
  ) async {
    await showDetail(tester, () async => fixture(OrderStatus.shipped));
    await tester.pumpAndSettle();
    expect(find.text('Shipped'), findsWidgets);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    final button = find.widgetWithText(OutlinedButton, 'Cancel Order');
    expect(button, findsNothing);
  });
  testWidgets('failed authoritative fetch hides snapshot and retries', (
    tester,
  ) async {
    var failed = true;
    await showDetail(tester, () async {
      if (failed) throw Exception('offline');
      return fixture(OrderStatus.shipped);
    });
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('View / Download Invoice'), findsNothing);
    failed = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Shipped'), findsWidgets);
  });
  testWidgets('failed session role fetch hides details and offers retry', (
    tester,
  ) async {
    await showDetail(
      tester,
      () async => fixture(OrderStatus.paid),
      fetchUser: () async => throw Exception('offline'),
    );
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('View / Download Invoice'), findsNothing);
  });
  testWidgets('guest cannot read a router snapshot', (tester) async {
    await showDetail(
      tester,
      () async => fixture(OrderStatus.paid),
      userId: null,
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in to view your order'), findsOneWidget);
    expect(find.text('View / Download Invoice'), findsNothing);
  });
  testWidgets('another customer cannot read snapshot or fetched order', (
    tester,
  ) async {
    await showDetail(
      tester,
      () async => fixture(OrderStatus.paid),
      userId: 'other',
    );
    await tester.pumpAndSettle();
    expect(find.text('Order not found'), findsOneWidget);
    expect(find.text('View / Download Invoice'), findsNothing);
  });
  testWidgets('admin can read retained order after account deletion', (
    tester,
  ) async {
    await showDetail(
      tester,
      () async => fixture(OrderStatus.shipped, userId: null),
      userId: 'admin',
      role: UserRole.owner,
    );
    await tester.pumpAndSettle();
    expect(find.text('Shipped'), findsWidgets);
  });
  testWidgets('refresh never restores an older router status', (tester) async {
    final refreshed = Completer<Order?>();
    var calls = 0;
    await showDetail(
      tester,
      () => ++calls == 1
          ? Future.value(fixture(OrderStatus.shipped))
          : refreshed.future,
      snapshot: fixture(OrderStatus.pending),
    );
    await tester.pumpAndSettle();
    final pending = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    expect(find.text('Pending'), findsNothing);
    expect(find.text('Cancel Order'), findsNothing);
    refreshed.complete(fixture(OrderStatus.delivered));
    await pending;
    await tester.pumpAndSettle();
  });
  for (final changeIdentity in [false, true]) {
    testWidgets(
      'cancel dialog closes when ${changeIdentity ? 'identity' : 'authority'} changes',
      (tester) async {
        final activeId = StateProvider<String?>((ref) => 'customer');
        final currentStatus = StateProvider<OrderStatus>(
          (ref) => OrderStatus.pending,
        );
        final container = ProviderContainer(
          overrides: [
            authStateProvider.overrideWith((ref) => const Stream.empty()),
            currentUserIdProvider.overrideWith((ref) => ref.watch(activeId)),
            currentAppUserProvider.overrideWith((ref) async {
              final id = ref.watch(activeId);
              return id == null
                  ? null
                  : AppUser(id: id, role: UserRole.customer);
            }),
            orderByIdProvider('order-12345')
                .overrideWith((ref) async => fixture(ref.watch(currentStatus))),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light,
              home: const OrderDetailScreen(orderId: 'order-12345'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Cancel Order'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Cancel Order'));
        await tester.pumpAndSettle();
        expect(find.text('Cancel this order?'), findsOneWidget);
        if (changeIdentity) {
          container.read(activeId.notifier).state = 'other';
        } else {
          container.read(currentStatus.notifier).state = OrderStatus.shipped;
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Cancel this order?'), findsNothing);
      },
    );
  }
  testWidgets('refresh failure replaces loaded details with retry', (
    tester,
  ) async {
    var calls = 0;
    await showDetail(tester, () async {
      if (++calls > 1) throw Exception('offline');
      return fixture(OrderStatus.pending);
    });
    await tester.pumpAndSettle();
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('View / Download Invoice'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('refresh awaits fetched status and disables stale actions', (
    tester,
  ) async {
    final refreshed = Completer<Order?>();
    var calls = 0;
    await showDetail(
      tester,
      () => ++calls == 1
          ? Future.value(fixture(OrderStatus.paid))
          : refreshed.future,
    );
    await tester.pumpAndSettle();
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final pending = refresh.onRefresh();
    await tester.pump();
    expect(find.text('Updating order…'), findsOneWidget);
    refreshed.complete(fixture(OrderStatus.cancelled));
    await pending;
    await tester.pumpAndSettle();
    expect(find.text('Cancelled'), findsWidgets);
  });
}
