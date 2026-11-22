import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/dashboard/admin_dashboard_screen.dart';
import 'package:marugen_app/features/admin/dashboard/admin_top_products_screen.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final now = DateTime.utc(2026, 11, 1);

Order order(
  String id, {
  OrderStatus status = OrderStatus.paid,
  double total = 20,
  List<OrderItem> items = const [],
}) => Order(
  id: '$id-12345678',
  userId: 'buyer',
  status: status,
  total: total,
  createdAt: now,
  stripePaymentIntentId: 'pi_$id',
  items: items,
);

OrderItem line(
  String name,
  int quantity, {
  double price = 10,
  String id = '',
}) => OrderItem(
  productId: id,
  productName: name,
  quantity: quantity,
  unitPrice: price,
);

/// What the database answers before migration 0078 is applied.
const missingFunction = {
  'code': 'PGRST202',
  'message': 'Could not find the function public.admin_payments_summary',
  'details': null,
  'hint': null,
};

/// The order repository with only the two aggregates answered.
class Aggregates implements OrderRepository {
  AdminPaymentsSummary? payments;
  List<TopProductSales>? topProducts;
  Object? failure;
  int? requestedLimit;

  @override
  Future<AdminPaymentsSummary?> fetchAdminPaymentsSummary() async {
    if (failure != null) throw failure!;
    return payments;
  }

  @override
  Future<List<TopProductSales>?> fetchAdminTopProducts({
    required int limit,
  }) async {
    requestedLimit = limit;
    if (failure != null) throw failure!;
    return topProducts;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<http.Request> requests;

  SupabaseClient clientAnswering(Object body, {int status = 200}) {
    requests = [];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    return client;
  }

  group('repository', () {
    test('payments total and top products are read from the server', () async {
      final summary = await OrderRepository(
        client: clientAnswering([
          {'transaction_count': 1204, 'collected': 98765.4},
        ]),
      ).fetchAdminPaymentsSummary();
      expect(requests.single.url.path, '/rest/v1/rpc/admin_payments_summary');
      expect(summary!.transactionCount, 1204);
      expect(summary.collected, 98765.4);

      final ranked = await OrderRepository(
        client: clientAnswering([
          {
            'product_name': 'Kohaku',
            'product_id': 'k',
            'units': 12,
            'revenue': 2400,
          },
          {
            'product_name': 'Deleted pellets',
            'product_id': null,
            'units': 3,
            'revenue': 45.5,
          },
        ]),
      ).fetchAdminTopProducts(limit: 50);
      expect(requests.single.url.path, '/rest/v1/rpc/admin_top_products');
      expect(jsonDecode(requests.single.body), {'p_limit': 50});
      expect(
        ranked!.map((p) => '${p.name}|${p.productId}|${p.units}|${p.revenue}'),
        ['Kohaku|k|12|2400.0', 'Deleted pellets|null|3|45.5'],
      );
    });

    test('a database without the functions yet answers null, not an '
        'error', () async {
      expect(
        await OrderRepository(
          client: clientAnswering(missingFunction, status: 404),
        ).fetchAdminPaymentsSummary(),
        isNull,
      );
      expect(
        await OrderRepository(
          client: clientAnswering(missingFunction, status: 404),
        ).fetchAdminTopProducts(limit: 10),
        isNull,
      );
    });

    test('any other failure is still an error', () async {
      const denied = {'code': '42501', 'message': 'Admins only'};
      await expectLater(
        OrderRepository(client: clientAnswering(denied, status: 403))
            .fetchAdminPaymentsSummary(),
        throwsA(isA<PostgrestException>()),
      );
      await expectLater(
        OrderRepository(client: clientAnswering(denied, status: 403))
            .fetchAdminTopProducts(limit: 10),
        throwsA(isA<PostgrestException>()),
      );
      expect(isMissingRpc(Exception('offline')), isFalse);
    });
  });

  test('the fallback ranking follows the server rules: no cancelled orders, '
      'most units first, ties by name', () {
    final ranked = rankTopProductSales([
      order(
        'new',
        items: [
          line('Pellets', 2, price: 15, id: 'pellets-new'),
          line('Net', 3, price: 8, id: 'net'),
        ],
      ),
      order(
        'cancelled',
        status: OrderStatus.cancelled,
        items: [line('Net', 50)],
      ),
      order(
        'old',
        status: OrderStatus.refunded,
        items: [
          line('Pellets', 1, price: 20, id: 'pellets-old'),
          line('Bowl', 3, price: 5),
        ],
      ),
    ]);
    expect(
      ranked.map((p) => '${p.name}|${p.productId}|${p.units}|${p.revenue}'),
      ['Bowl|null|3|15.0', 'Net|net|3|24.0', 'Pellets|pellets-new|3|50.0'],
    );
  });

  group('top products provider', () {
    ProviderContainer containerWith(Aggregates repo, List<Order> orders) {
      final container = ProviderContainer(
        overrides: [
          orderRepositoryProvider.overrideWithValue(repo),
          adminAllOrdersProvider.overrideWith((ref) async => orders),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('uses the server ranking as it is', () async {
      final repo = Aggregates()
        ..topProducts = const [TopProductSales(name: 'Server first', units: 1)];
      final container = containerWith(repo, [
        order('a', items: [line('Client first', 99)]),
      ]);
      final ranked = await container.read(adminTopProductsProvider.future);
      expect(ranked.single.name, 'Server first');
      expect(repo.requestedLimit, kTopProductsLimit);
    });

    test('ranks the loaded orders until the function exists', () async {
      final container = containerWith(Aggregates(), [
        order('a', items: [line('Kohaku', 2), line('Pellets', 5)]),
      ]);
      final ranked = await container.read(adminTopProductsProvider.future);
      expect(ranked.map((p) => '${p.name}=${p.units}'), [
        'Pellets=5',
        'Kohaku=2',
      ]);
    });

    test('a real failure is not papered over with the fallback', () async {
      final container = containerWith(
        Aggregates()..failure = const PostgrestException(message: 'boom'),
        [
          order('a', items: [line('Kohaku', 2)]),
        ],
      );
      await expectLater(
        container.read(adminTopProductsProvider.future),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  group('payments summary provider', () {
    ProviderContainer containerWith(Aggregates repo) {
      final container = ProviderContainer(
        overrides: [
          orderRepositoryProvider.overrideWithValue(repo),
          // Only what a 1000-row fetch would have returned.
          adminAllOrdersProvider.overrideWith(
            (ref) async => [
              order('a', total: 20),
              order('b', total: 30),
              order('unpaid', total: 99, status: OrderStatus.pending),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('is the server total, not the sum of the orders the app '
        'holds', () async {
      final container = containerWith(
        Aggregates()
          ..payments = const AdminPaymentsSummary(
            transactionCount: 1500,
            collected: 98765.4,
          ),
      );
      final summary = await container.read(adminPaymentsSummaryProvider.future);
      expect(summary.collected, 98765.4);
      expect(summary.transactionCount, 1500);
      expect(container.exists(adminAllOrdersProvider), isFalse);
    });

    test('before migration 0078 it adds up every order as before', () async {
      final container = containerWith(Aggregates());
      final summary = await container.read(adminPaymentsSummaryProvider.future);
      // The unpaid checkout reached Stripe but collected nothing, so it is
      // not one of the paid orders the figure comes from.
      expect(summary.collected, 50);
      expect(summary.transactionCount, 2);
    });

    test('a real failure is not papered over with the fallback', () async {
      final container = containerWith(
        Aggregates()
          ..failure = const PostgrestException(message: 'boom', code: '42501'),
      );
      await expectLater(
        container.read(adminPaymentsSummaryProvider.future),
        throwsA(isA<PostgrestException>()),
      );
      expect(container.exists(adminAllOrdersProvider), isFalse);
    });
  });

  testWidgets('the dashboard card and the full screen show the same server '
      'ranking', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = Aggregates()
      ..topProducts = [
        for (var i = 1; i <= 7; i++)
          TopProductSales(name: 'Product $i', units: 100 - i),
      ];
    final overrides = [
      orderRepositoryProvider.overrideWithValue(repo),
      productListProvider.overrideWith((ref) async => []),
      adminAllProductsProvider.overrideWith((ref) async => []),
      // The orders the app holds would rank something else entirely.
      adminAllOrdersProvider.overrideWith(
        (ref) async => [
          order('a', items: [line('Client only', 999)]),
        ],
      ),
      fulfillmentOrdersProvider.overrideWith((ref) async => <Order>[]),
      adminRecentOrdersProvider.overrideWith((ref) async => <Order>[]),
      adminStuckPendingOrdersProvider.overrideWith(
        (ref) async => const StuckPendingOrders(orders: [], total: 0),
      ),
      unreadNotificationCountProvider.overrideWith((ref) => 0),
      adminOrderSummaryProvider.overrideWith(
        (ref) async => const AdminOrderSummary(
          openOrders: 0,
          totalRevenue: 0,
          weekRevenue: 0,
        ),
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AdminDashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Product 1'), findsOneWidget);
    expect(find.text('99 sold'), findsOneWidget);
    expect(find.text('Product 5'), findsOneWidget);
    expect(find.text('Product 6'), findsNothing);
    expect(find.text('+2 more'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    expect(find.text('Client only'), findsNothing);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AdminTopProductsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 1; i <= 7; i++) {
      expect(find.text('Product $i'), findsOneWidget);
    }
    expect(find.text('Client only'), findsNothing);
  });
}
