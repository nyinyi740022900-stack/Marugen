import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/dashboard/admin_dashboard_screen.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/order.dart';
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
  int allOrdersFetches = 0;
  final pageRequests = <(int, int)>[];
  final stuckRequests = <(DateTime, int)>[];

  @override
  Future<AdminOrderSummary> fetchAdminOrderSummary() async =>
      const AdminOrderSummary(
        openOrders: 2,
        totalRevenue: 9000,
        weekRevenue: 700,
      );

  @override
  Future<AdminPaymentsSummary?> fetchAdminPaymentsSummary() async {
    if (paymentsFailure != null) throw paymentsFailure!;
    return hasRpcs
        ? const AdminPaymentsSummary(transactionCount: 45, collected: 8123.5)
        : null;
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
  Future<void> showDashboard(WidgetTester tester, _Dashboard repo) async {
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

    // The Stripe figure sits beside revenue under its own name.
    expect(find.text('Total Revenue'), findsOneWidget);
    expect(find.text('S\$9000'), findsOneWidget);
    expect(find.text('Collected through Stripe'), findsOneWidget);
    expect(find.text('S\$8123.50'), findsOneWidget);
    expect(
      find.text('After refunds · 45 Stripe transactions'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
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
    expect(find.text('S\$30.00'), findsOneWidget);
    expect(find.text('After refunds · 3 Stripe transactions'), findsOneWidget);
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
    expect(find.text('Could not load. Tap to retry.'), findsOneWidget);
    expect(find.text('S\$8123.50'), findsNothing);
    expect(find.textContaining('boom'), findsNothing);

    repo.paymentsFailure = null;
    await tester.tap(find.text('Could not load. Tap to retry.'));
    await tester.pumpAndSettle();
    expect(find.text('S\$8123.50'), findsOneWidget);
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
    final stuck = await OrderRepository(
      client: client,
    ).fetchStuckPendingOrders(createdBefore: cutoff, limit: 20);

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
