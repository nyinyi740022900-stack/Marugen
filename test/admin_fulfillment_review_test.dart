// Page review 22 Nov 2026, Orders > Fulfillment: a courier order can be
// marked delivered by hand, and a status move confirms itself and
// refreshes Home.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/admin/delivery/admin_delivery_screen.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/shared/models/order.dart';

import 'delivery_workflow_test.dart'
    show DeliveryOrders, deliveryOrder, showDelivery;

class _Orders extends DeliveryOrders {
  _Orders(super.orders);
  final moves = <OrderStatus>[];
  int summaryFetches = 0;
  int recentFetches = 0;

  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    moves.add(status);
  }

  @override
  Future<AdminOrderSummary> fetchAdminOrderSummary() async {
    summaryFetches++;
    return const AdminOrderSummary(
      openOrders: 1,
      totalRevenue: 20,
      weekRevenue: 20,
    );
  }

  @override
  Future<List<Order>> fetchAllOrdersPage({
    OrderStatus? status,
    required int offset,
    required int limit,
  }) {
    if (limit == kRecentOrdersLimit) recentFetches++;
    return super.fetchAllOrdersPage(
      status: status,
      offset: offset,
      limit: limit,
    );
  }
}

void main() {
  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('a courier order in transit can be marked delivered from the '
      'overflow, with a warning to check the carrier first', (tester) async {
    bigScreen(tester);
    final order = deliveryOrder(
      status: 'shipped',
      provider: 'seventeentrack',
      tracking: 'SG123',
      registered: true,
    );
    final repo = _Orders([order]);
    await showDelivery(tester, order, repository: repo);
    // Not a primary button: the carrier normally reports delivery.
    expect(find.text('Mark as delivered'), findsNothing);

    await tester.tap(find.byTooltip('More delivery actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as delivered…'));
    await tester.pumpAndSettle();
    expect(find.text('Mark as delivered?'), findsOneWidget);
    expect(
      find.textContaining('Use only if the carrier shows it delivered.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.moves, isEmpty);

    await tester.tap(find.byTooltip('More delivery actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as delivered…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark Delivered'));
    await tester.pumpAndSettle();
    expect(repo.moves, [OrderStatus.delivered]);
    expect(find.text('Order #DEL-001 marked as delivered.'), findsOneWidget);
  });

  testWidgets('shop delivery keeps its own button and has no overflow, and '
      'its confirmation has no carrier line', (tester) async {
    bigScreen(tester);
    final order = deliveryOrder(
      status: 'shipped',
      method: 'shop_delivery',
      category: 'koi',
    );
    await showDelivery(tester, order, repository: _Orders([order]));
    expect(find.byTooltip('More delivery actions'), findsNothing);
    await tester.tap(find.text('Mark as delivered'));
    await tester.pumpAndSettle();
    expect(find.textContaining('carrier shows it delivered'), findsNothing);
  });

  testWidgets('a status move says what happened and reloads the Home '
      'summary and recent orders', (tester) async {
    bigScreen(tester);
    final order = deliveryOrder(status: 'paid');
    final repo = _Orders([order]);
    await showDelivery(tester, order, repository: repo);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdminDeliveryPane)),
    );
    // Home is alive in the shell's IndexedStack while Fulfillment is used.
    final summary = container.listen(adminOrderSummaryProvider, (_, _) {});
    final recent = container.listen(adminRecentOrdersProvider, (_, _) {});
    addTearDown(summary.close);
    addTearDown(recent.close);
    await tester.pumpAndSettle();
    expect((repo.summaryFetches, repo.recentFetches), (1, 1));

    await tester.tap(find.text('Start packing'));
    await tester.pumpAndSettle();
    expect(repo.moves, [OrderStatus.packing]);
    expect(find.text('Order #DEL-001 is now packing.'), findsOneWidget);
    expect((repo.summaryFetches, repo.recentFetches), (2, 2));
  });
}
