import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/analytics/analytics_repository.dart';
import 'package:marugen_app/features/admin/dashboard/admin_dashboard_screen.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<http.Request> requests;

  SupabaseClient clientReturning(Object body) {
    requests = [];
    return SupabaseClient(
      'https://example.supabase.co',
      'test-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  }

  test('dashboard totals and analytics come from server-side counts', () async {
    var client = clientReturning([
      {'open_orders': 2, 'total_revenue': 1850.5, 'week_revenue': 150},
    ]);
    final summary = await OrderRepository(client: client)
        .fetchAdminOrderSummary();
    expect(requests.single.url.path, '/rest/v1/rpc/admin_order_summary');
    expect(
      [summary.openOrders, summary.totalRevenue, summary.weekRevenue],
      [2, 1850.5, 150.0],
    );
    await client.dispose();

    client = clientReturning([
      {'day': '2026-10-30', 'visits': 1500, 'product_views': 0},
      {'day': '2026-10-31', 'visits': 3, 'product_views': 5},
    ]);
    final days = await AnalyticsRepository(client: client).fetchDailyActivity();
    expect(requests.single.url.path, '/rest/v1/rpc/admin_daily_activity');
    expect(jsonDecode(requests.single.body), {'p_days': 190});
    expect(days.map((d) => [d.day, d.visits, d.productViews]), [
      [DateTime(2026, 10, 30), 1500, 0],
      [DateTime(2026, 10, 31), 3, 5],
    ]);
    await client.dispose();

    client = clientReturning([
      {'product_id': 'k', 'product_name': 'Kohaku', 'views': 5},
      {'product_id': null, 'product_name': null, 'views': 1},
    ]);
    final top = await AnalyticsRepository(client: client)
        .fetchTopViewedProducts(days: 14);
    expect(requests.single.url.path, '/rest/v1/rpc/admin_top_viewed_products');
    expect(jsonDecode(requests.single.body)['p_limit'], 10);
    expect(top.map((t) => '${t.productName}=${t.views}'), [
      'Kohaku=5',
      'null=1',
    ]);
    await client.dispose();
  });

  testWidgets('dashboard shows the server totals whatever the Orders filter', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productListProvider.overrideWith((ref) async => []),
          adminOrdersProvider.overrideWith((ref) async => <Order>[]),
          unreadNotificationCountProvider.overrideWith((ref) => 0),
          adminOrderSummaryProvider.overrideWith(
            (ref) async => const AdminOrderSummary(
              openOrders: 2,
              totalRevenue: 1850,
              weekRevenue: 150,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AdminDashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('S\$1850'), findsOneWidget);
    expect(find.text('S\$150'), findsOneWidget);
  });
}
