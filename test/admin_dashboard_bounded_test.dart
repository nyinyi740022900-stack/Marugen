import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/features/admin/admin_shell.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/dashboard/admin_dashboard_screen.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Order _order(int n, {OrderStatus status = OrderStatus.paid}) => Order(
  id: '${n.toString().padLeft(8, '0')}-abcdef',
  userId: 'buyer',
  orderNumber: 'ORD-$n',
  status: status,
  total: 10,
  createdAt: DateTime.now().subtract(Duration(hours: n + 1)),
  stripePaymentIntentId: 'pi_$n',
);

/// The order repository as the dashboard uses it, counting every call.
class _Dashboard implements OrderRepository {
  _Dashboard({this.hasRpcs = true, this.stuckTotal = 0});

  /// False for a database before migration 0078.
  final bool hasRpcs;
  int stuckTotal;
  Object? paymentsFailure;
  Object? summaryFailure;
  AdminPaymentsSummary payments = const AdminPaymentsSummary(
    transactionCount: 45,
    collected: 8123.5,
  );

  /// Replaces the generated recent orders when set.
  List<Order>? recent;
  int allOrdersFetches = 0;
  final pageRequests = <(int, int)>[];
  final stuckRequests = <(DateTime, int)>[];

  @override
  Future<AdminOrderSummary> fetchAdminOrderSummary() async {
    if (summaryFailure != null) throw summaryFailure!;
    return const AdminOrderSummary(
      openOrders: 2,
      totalRevenue: 9000,
      weekRevenue: 700,
    );
  }

  @override
  Future<AdminPaymentsSummary?> fetchAdminPaymentsSummary() async {
    if (paymentsFailure != null) throw paymentsFailure!;
    return hasRpcs ? payments : null;
  }

  @override
  Future<List<TopProductSales>?> fetchAdminTopProducts({
    required int limit,
  }) async => hasRpcs ? const [] : null;

  @override
  Future<List<Order>> fetchFulfillmentOrders() async => const [];

  @override
  Future<List<Order>> fetchAllOrders({OrderStatus? status}) async {
    allOrdersFetches++;
    return [for (var n = 0; n < 3; n++) _order(n)];
  }

  @override
  Future<List<Order>> fetchAllOrdersPage({
    OrderStatus? status,
    required int offset,
    required int limit,
  }) async {
    pageRequests.add((offset, limit));
    if (recent != null) return recent!;
    return [for (var n = 0; n < limit; n++) _order(n)];
  }

  @override
  Future<StuckPendingOrders> fetchStuckPendingOrders({
    required DateTime createdBefore,
    int limit = kStuckPendingLimit,
  }) async {
    stuckRequests.add((createdBefore, limit));
    final shown = stuckTotal < limit ? stuckTotal : limit;
    return StuckPendingOrders(
      orders: [
        for (var n = 0; n < shown; n++)
          _order(100 + n, status: OrderStatus.pending),
      ],
      total: stuckTotal,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> showDashboard(
    WidgetTester tester,
    _Dashboard repo, {
    int gstPercent = 9,
  }) async {
    tester.view.physicalSize = const Size(400, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderRepositoryProvider.overrideWithValue(repo),
          productListProvider.overrideWith((ref) async => []),
          adminAllProductsProvider.overrideWith((ref) async => []),
          unreadNotificationCountProvider.overrideWith((ref) => 0),
          shopSettingsProvider.overrideWith(
            (ref) async => {'gst_percent': gstPercent},
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Column(
                children: [
                  TextButton(
                    onPressed: () => refreshAdminOrders(ref),
                    child: const Text('after a mutation'),
                  ),
                  const Expanded(child: AdminDashboardScreen()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a shop at 0% GST: the sales caption does not mention GST', (
    tester,
  ) async {
    await showDashboard(tester, _Dashboard(stuckTotal: 0), gstPercent: 0);
    expect(find.text('Includes delivery fees'), findsOneWidget);
    expect(find.textContaining('GST'), findsNothing);
  });

  testWidgets('opening the dashboard never downloads every order when the '
      'server functions exist', (tester) async {
    final repo = _Dashboard(stuckTotal: 2);
    await showDashboard(tester, repo);

    expect(repo.allOrdersFetches, 0);
    expect(repo.pageRequests, [(0, kRecentOrdersLimit)]);
    expect(repo.stuckRequests, hasLength(1));
    // Same rule as before: pending for more than 30 minutes.
    final (cutoff, limit) = repo.stuckRequests.single;
    expect(limit, kStuckPendingLimit);
    expect(
      DateTime.now().difference(cutoff).inSeconds,
      inInclusiveRange(30 * 60 - 5, 30 * 60 + 60),
    );

    // Five recent rows, two stuck ones.
    expect(find.text('#ORD-0'), findsOneWidget);
    expect(find.text('#ORD-4'), findsOneWidget);
    expect(find.text('#ORD-5'), findsNothing);
    expect(find.text('#ORD-100'), findsOneWidget);
    expect(find.text('#ORD-101'), findsOneWidget);
    expect(find.textContaining('more in Orders'), findsNothing);

    // One money card: sales, the last week, and the Stripe part of it
    // only because it differs from the total.
    expect(find.text('Sales after refunds'), findsOneWidget);
    expect(find.text('S\$9000.00'), findsOneWidget);
    expect(find.text('Last 7 days: S\$700.00'), findsOneWidget);
    expect(find.text('Includes delivery fees and GST'), findsOneWidget);
    expect(
      find.text(
        'S\$8123.50 of this was collected through Stripe · 45 paid orders',
      ),
      findsOneWidget,
    );
    expect(find.text('Total Revenue'), findsNothing);
    expect(find.text('Revenue This Week'), findsNothing);
    expect(find.text('Collected through Stripe'), findsNothing);
    // Stuck rows give their age in words, not a minute count.
    expect(find.textContaining('min ago'), findsNothing);
    expect(find.text('S\$10.00 · created 4 days ago'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    // The card opens Orders, not Analytics.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdminDashboardScreen)),
    );
    await tester.tap(find.text('Sales after refunds'));
    await tester.pump();
    expect(container.read(adminTabIndexProvider), 2);
  });

  testWidgets('more stuck orders than the limit show the real count and a '
      'way to the rest', (tester) async {
    final repo = _Dashboard(stuckTotal: 57);
    await showDashboard(tester, repo);
    expect(find.text('57'), findsOneWidget);
    expect(find.text('Cancel now'), findsNWidgets(kStuckPendingLimit));
    expect(find.text('+37 more in Orders'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdminDashboardScreen)),
    );
    await tester.tap(find.text('+37 more in Orders'));
    await tester.pump();
    expect(container.read(adminOrderStatusFilterProvider), OrderStatus.pending);
    expect(container.read(requestedOrdersTabProvider), 0);
  });

  testWidgets('refreshAdminOrders reloads the recent and stuck lists', (
    tester,
  ) async {
    final repo = _Dashboard(stuckTotal: 1);
    await showDashboard(tester, repo);
    expect(find.text('#ORD-100'), findsOneWidget);

    repo
      ..stuckTotal = 0
      ..pageRequests.clear()
      ..stuckRequests.clear();
    await tester.tap(find.text('after a mutation'));
    await tester.pumpAndSettle();

    expect(repo.pageRequests, contains((0, kRecentOrdersLimit)));
    expect(repo.stuckRequests, hasLength(1));
    expect(find.text('#ORD-100'), findsNothing);
    expect(find.text('STUCK PENDING ORDERS'), findsNothing);
    expect(repo.allOrdersFetches, 0);
  });

  testWidgets('before migration 0078 the Stripe figure is added up from '
      'every order, in one fetch', (tester) async {
    final repo = _Dashboard(hasRpcs: false);
    await showDashboard(tester, repo);
    // Shared by the payments summary and the top-products fallback.
    expect(repo.allOrdersFetches, 1);
    expect(
      find.text(
        'S\$30.00 of this was collected through Stripe · 3 paid orders',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a shop paid only through Stripe reads one amount, with the '
      'paid-order count beside it', (tester) async {
    final repo = _Dashboard()
      ..payments = const AdminPaymentsSummary(
        transactionCount: 1,
        collected: 9000,
      );
    await showDashboard(tester, repo);
    expect(find.text('S\$9000.00'), findsOneWidget);
    expect(find.text('1 paid order'), findsOneWidget);
    expect(find.textContaining('collected through Stripe'), findsNothing);
  });

  testWidgets('when the sales summary cannot load, Home says so and '
      'retries', (tester) async {
    final repo = _Dashboard()..summaryFailure = StateError('offline');
    await showDashboard(tester, repo);
    expect(
      find.text('Could not load sales. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('offline'), findsNothing);

    repo.summaryFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('S\$9000.00'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a recent order shows who it is for and its status in words, '
      'and opens the order', (tester) async {
    final repo = _Dashboard()
      ..recent = [
        Order(
          id: 'order-abc',
          userId: 'buyer',
          orderNumber: 'ORD-7',
          status: OrderStatus.shipped,
          fulfillmentMethod: 'shop_delivery',
          total: 84.5,
          createdAt: DateTime.now(),
          shippingAddress: const {'recipient_name': 'Mei Ling'},
        ),
      ];
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const AdminDashboardScreen()),
        GoRoute(
          path: '/orders/:id',
          builder: (_, state) =>
              Scaffold(body: Text('order ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(400, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderRepositoryProvider.overrideWithValue(repo),
          productListProvider.overrideWith((ref) async => []),
          adminAllProductsProvider.overrideWith((ref) async => []),
          unreadNotificationCountProvider.overrideWith((ref) => 0),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('#ORD-7 · Mei Ling'), findsOneWidget);
    expect(
      find.text(repo.recent!.single.fulfillmentStatusLabel),
      findsOneWidget,
    );
    expect(find.text('SHIPPED'), findsNothing);

    await tester.tap(find.text('#ORD-7 · Mei Ling'));
    await tester.pumpAndSettle();
    expect(find.text('order order-abc'), findsOneWidget);
  });

  test('ages read in the largest unit that fits', () {
    expect(timeAgoLabel(const Duration(seconds: 20)), 'just now');
    expect(timeAgoLabel(const Duration(minutes: 45)), '45 min ago');
    expect(timeAgoLabel(const Duration(minutes: 60)), '1 hour ago');
    expect(timeAgoLabel(const Duration(hours: 5)), '5 hours ago');
    expect(timeAgoLabel(const Duration(minutes: 4320)), '3 days ago');
    expect(timeAgoLabel(const Duration(hours: 30)), '1 day ago');
  });

  test('the fallback counts only orders that add to the collected sum', () {
    Order order(
      OrderStatus status, {
      String? intent = 'pi_1',
      String? refundStatus,
      double refundAmount = 0,
    }) => Order(
      id: 'o-${status.name}-$refundStatus-$intent',
      userId: 'buyer',
      status: status,
      total: 100,
      createdAt: DateTime(2026, 11, 1),
      stripePaymentIntentId: intent,
      refundStatus: refundStatus,
      refundAmount: refundAmount,
    );
    final summary = AdminPaymentsSummary.fromOrders([
      order(OrderStatus.paid),
      order(OrderStatus.packing),
      order(OrderStatus.shipped),
      order(OrderStatus.delivered, refundAmount: 30),
      // Refund not yet confirmed by Stripe: the money is still held.
      order(OrderStatus.refunded, refundStatus: 'pending', refundAmount: 100),
      order(OrderStatus.refunded, refundStatus: 'failed', refundAmount: 40),
      // None of these collected anything.
      order(OrderStatus.pending),
      order(OrderStatus.cancelled),
      order(OrderStatus.refunded, refundStatus: 'succeeded', refundAmount: 100),
      order(OrderStatus.refunded),
      order(OrderStatus.paid, intent: null),
      order(OrderStatus.paid, intent: ''),
    ]);
    expect(summary.transactionCount, 6);
    expect(summary.collected, 100 + 100 + 100 + 70 + 0 + 60);
  });

  testWidgets('a failed Stripe figure says so and retries on tap', (
    tester,
  ) async {
    final repo = _Dashboard()
      ..paymentsFailure = const PostgrestException(
        message: 'boom',
        code: '42501',
      );
    await showDashboard(tester, repo);
    expect(find.text('Could not load the Stripe figure.'), findsOneWidget);
    // Sales themselves loaded and stay on screen.
    expect(find.text('S\$9000.00'), findsOneWidget);
    expect(find.textContaining('S\$8123.50'), findsNothing);
    expect(find.textContaining('boom'), findsNothing);

    repo.paymentsFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('S\$8123.50'), findsOneWidget);
  });

  test('the stuck query is filtered, bounded and counted on the '
      'server', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode([
            {
              'id': 'o1-12345678',
              'user_id': 'buyer',
              'status': 'pending',
              'total': 12,
              'created_at': '2026-11-01T00:00:00Z',
            },
          ]),
          206,
          headers: {
            'content-type': 'application/json',
            'content-range': '0-0/57',
          },
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);

    final cutoff = DateTime.utc(2026, 11, 19, 3, 30);
    final stuck = await OrderRepository(client: client)
        .fetchStuckPendingOrders(createdBefore: cutoff, limit: 20);

    expect(stuck.orders.single.status, OrderStatus.pending);
    expect(stuck.total, 57);
    final request = requests.single;
    expect(request.url.path, '/rest/v1/orders');
    expect(request.url.queryParameters['status'], 'eq.pending');
    expect(
      request.url.queryParameters['created_at'],
      'lt.2026-11-19T03:30:00.000Z',
    );
    expect(request.url.queryParameters['limit'], '20');
    // No order lines: the dashboard row does not show them.
    expect(request.url.queryParameters['select'], '*');
    expect(
      request.headers.entries
          .firstWhere((h) => h.key.toLowerCase() == 'prefer')
          .value,
      contains('count=exact'),
    );
  });
}
