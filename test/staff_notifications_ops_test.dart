// Page review 22 Nov 2026, Notifications (staff): ops monitoring alerts
// look like warnings and lead somewhere useful, or say that they do not.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/admin_shell.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/notifications/data/notification_repository.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/features/notifications/presentation/notifications_screen.dart';
import 'package:marugen_app/shared/models/app_notification.dart';
import 'package:marugen_app/shared/models/app_user.dart';

AppNotification _alert(
  String id,
  String title, {
  String? key,
  String? orderId,
  String body = 'Details.',
}) => AppNotification.fromMap({
  'id': id,
  'title': title,
  'body': body,
  'type': 'admin_alert',
  'read': false,
  'created_at': '2026-11-22T02:00:00Z',
  'key': key,
  'order_id': orderId,
});

class _Inbox implements NotificationRepository {
  _Inbox(this.items);
  final List<AppNotification> items;
  @override
  Future<List<AppNotification>> fetchMine() async => items;
  @override
  Future<void> markRead(String id) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('the key is read from the row, and tells an ops alert from an '
      'ordinary staff notice', () {
    final order = _alert('1', 'Refund failed', key: 'ops:refund_failed:re_1');
    final shop = _alert(
      '2',
      'EasyParcel disconnected',
      key: 'ops-daily:easyparcel_disconnected:2026-11-22',
    );
    final delivery = _alert('3', 'Out for delivery', key: 'shipped:order-1');
    final none = _alert('4', 'Out for delivery');
    expect(order.key, 'ops:refund_failed:re_1');
    expect(order.isOpsAlert, isTrue);
    expect(order.shopWideFinding, isNull);
    expect(shop.isOpsAlert, isTrue);
    expect(shop.shopWideFinding, 'easyparcel_disconnected');
    expect(delivery.isOpsAlert, isFalse);
    expect(none.isOpsAlert, isFalse);
    expect(shop.copyWith(read: true).key, shop.key);
    // A customer notification is never an ops alert, whatever its key.
    expect(
      AppNotification.fromMap({
        'id': '5',
        'title': 'Order shipped',
        'body': 'On its way.',
        'type': 'order_status',
        'created_at': '2026-11-22T02:00:00Z',
        'key': 'ops:odd',
      }).isOpsAlert,
      isFalse,
    );
  });

  Future<ProviderContainer> show(
    WidgetTester tester,
    List<AppNotification> items,
  ) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/notifications',
      routes: [
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/admin',
          builder: (_, _) => const Scaffold(body: Text('admin shell')),
        ),
        GoRoute(
          path: '/orders/:id',
          builder: (_, state) =>
              Scaffold(body: Text('order ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isLoggedInProvider.overrideWithValue(true),
          currentUserIdProvider.overrideWithValue('owner'),
          currentAppUserProvider.overrideWith(
            (ref) async => const AppUser(id: 'owner', role: UserRole.owner),
          ),
          notificationRepositoryProvider.overrideWithValue(_Inbox(items)),
          notificationInsertsProvider.overrideWith(
            (ref, owner) => const Stream.empty(),
          ),
          notificationBadgeWriterProvider.overrideWithValue((_) async {}),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(NotificationsScreen)),
    );
  }

  Finder tile(String title) => find.ancestor(
    of: find.text(title),
    matching: find.byType(InkWell),
  );
  Finder inTile(String title, Finder what) =>
      find.descendant(of: tile(title), matching: what);

  final all = [
    _alert('1', 'Refund failed', key: 'ops:refund_failed:re_1', orderId: 'o-1'),
    _alert(
      '2',
      'EasyParcel disconnected',
      key: 'ops-daily:easyparcel_disconnected:2026-11-22',
    ),
    _alert(
      '3',
      'Payment check not running',
      key: 'ops-daily:reconcile_failing:2026-11-22',
      body: 'Ask your developer to check the reconcile-pending-orders logs.',
    ),
    _alert('4', 'Out for delivery', orderId: 'o-4'),
  ];

  testWidgets('ops alerts carry a warning icon; delivery notices keep the '
      'truck', (tester) async {
    await show(tester, all);
    for (final title in [
      'Refund failed',
      'EasyParcel disconnected',
      'Payment check not running',
    ]) {
      expect(
        inTile(title, find.byIcon(Icons.warning_amber_rounded)),
        findsOneWidget,
        reason: title,
      );
      expect(
        inTile(title, find.byIcon(Icons.local_shipping_outlined)),
        findsNothing,
      );
    }
    expect(
      inTile('Out for delivery', find.byIcon(Icons.local_shipping_outlined)),
      findsOneWidget,
    );
  });

  testWidgets('"EasyParcel disconnected" opens admin Settings', (tester) async {
    final container = await show(tester, all);
    expect(
      inTile('EasyParcel disconnected', find.byIcon(Icons.chevron_right)),
      findsOneWidget,
    );
    expect(find.text('Tap to open Settings.'), findsOneWidget);
    await tester.tap(find.text('EasyParcel disconnected'));
    await tester.pumpAndSettle();
    expect(find.text('admin shell'), findsOneWidget);
    expect(container.read(adminTabIndexProvider), kAdminSettingsTab);
  });

  testWidgets('"Payment check not running" has no chevron, says there is '
      'nothing to open, and stays put when tapped', (tester) async {
    await show(tester, all);
    expect(
      inTile('Payment check not running', find.byIcon(Icons.chevron_right)),
      findsNothing,
    );
    expect(
      find.text('There is nothing to open in the app for this alert.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Payment check not running'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.text('admin shell'), findsNothing);
  });

  testWidgets('an order-scoped ops alert still opens its order', (
    tester,
  ) async {
    await show(tester, all);
    expect(
      inTile('Refund failed', find.byIcon(Icons.chevron_right)),
      findsOneWidget,
    );
    await tester.tap(find.text('Refund failed'));
    await tester.pumpAndSettle();
    expect(find.text('order o-1'), findsOneWidget);
  });
}
