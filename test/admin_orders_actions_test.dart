// Page review 22 Nov 2026, Orders > All: buttons say what they do, the
// refund confirmation names the amount, the card names the customer, and
// a search narrowed by the status chip says so.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/admin_shell.dart';
import 'package:marugen_app/features/admin/delivery/easyparcel_providers.dart';
import 'package:marugen_app/features/admin/orders/admin_orders_screen.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/shared/models/order.dart';

import 'delivery_workflow_test.dart' show DeliveryOrders;

Order _order({String status = 'paid'}) => Order.fromMap({
  'id': 'order-845',
  'order_number': 'DEL-845',
  'user_id': 'customer',
  'status': status,
  'total': 84.5,
  'created_at': '2026-11-19T01:00:00Z',
  'fulfillment_method': 'courier',
  'stripe_payment_intent_id': 'pi_845',
  'shipping_address': {'recipient_name': 'Daw May', 'phone': '81234567'},
  'items': [
    {
      'product_id': 'food-1',
      'product_name': 'Koi food',
      'quantity': 1,
      'unit_price': 84.5,
      'product_category': 'fish_food',
    },
  ],
});

class _Orders extends DeliveryOrders {
  _Orders(super.orders);
  final refunds = <String>[];
  final moves = <(String, OrderStatus)>[];

  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    moves.add((orderId, status));
  }

  @override
  Future<void> refundOrder(
    String orderId, {
    String? reason,
    bool refreshOnly = false,
  }) async {
    refunds.add(orderId);
  }
}

void main() {
  Future<ProviderContainer> show(
    WidgetTester tester,
    _Orders repo, {
    double width = 500,
  }) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderRepositoryProvider.overrideWithValue(repo),
          easyParcelConnectedProvider.overrideWith((ref) async => false),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AdminOrdersScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(AdminOrdersScreen)),
    );
  }

  testWidgets('a paid order offers actions, not status nouns, and names '
      'the customer', (tester) async {
    final repo = _Orders([_order()]);
    await show(tester, repo);
    expect(find.text('Daw May · 81234567'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Start packing'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Refund order…'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Packing'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Refunded'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Start packing'));
    await tester.pumpAndSettle();
    expect(repo.moves, [('order-845', OrderStatus.packing)]);
  });

  testWidgets('the refund confirmation states the amount, on the message '
      'and on the button', (tester) async {
    final repo = _Orders([_order()]);
    await show(tester, repo);
    await tester.tap(find.widgetWithText(TextButton, 'Refund order…'));
    await tester.pumpAndSettle();
    expect(
      find.text("Refund S\$84.50 to the customer's original payment method?"),
      findsOneWidget,
    );
    expect(find.text('Refund S\$84.50'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(repo.refunds, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Refund order…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refund S\$84.50'));
    await tester.pumpAndSettle();
    expect(repo.refunds, ['order-845']);
  });

  testWidgets('an unpaid order is cancelled with "Keep order" / "Cancel '
      'order"', (tester) async {
    final repo = _Orders([_order(status: 'pending')]);
    await show(tester, repo);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel order…'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this order?'), findsOneWidget);
    await tester.tap(find.text('Keep order'));
    await tester.pumpAndSettle();
    expect(repo.moves, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel order…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel order'));
    await tester.pumpAndSettle();
    expect(repo.moves, [('order-845', OrderStatus.cancelled)]);
  });

  testWidgets('a search narrowed by the status chip says so and can be '
      'widened to all orders', (tester) async {
    final repo = _Orders([_order()]);
    final container = await show(tester, repo);
    container.read(adminOrderStatusFilterProvider.notifier).state =
        OrderStatus.pending;
    await tester.enterText(find.byType(TextField), 'DEL-845');
    await tester.pumpAndSettle();
    expect(find.text('No matches in Pending.'), findsOneWidget);
    expect(find.text('Order #DEL-845'), findsNothing);

    await tester.tap(find.text('Search all orders'));
    await tester.pumpAndSettle();
    expect(container.read(adminOrderStatusFilterProvider), isNull);
    expect(find.text('Order #DEL-845'), findsOneWidget);

    // With no chip there is nothing to widen.
    await tester.enterText(find.byType(TextField), 'nothing like this');
    await tester.pumpAndSettle();
    expect(find.text('No matches.'), findsOneWidget);
    expect(find.text('Search all orders'), findsNothing);
  });

  test('the tab constants select the screens they are named after', () {
    expect(AdminShell.tabs[kAdminOrdersTab], isA<AdminOrdersScreen>());
    expect(
      AdminShell.tabs[kAdminHomeTab].runtimeType.toString(),
      'AdminDashboardScreen',
    );
    expect(
      AdminShell.tabs[kAdminProductsTab].runtimeType.toString(),
      'AdminProductsScreen',
    );
    expect(
      AdminShell.tabs[kAdminSettingsTab].runtimeType.toString(),
      'AdminSettingsScreen',
    );
    expect(
      AdminShell.tabs[kAdminHomeBannersTab].runtimeType.toString(),
      'AdminBannersScreen',
    );
    expect(AdminShell.tabs, hasLength(9));
  });

  testWidgets('one wording for the cancel confirmation everywhere', (
    tester,
  ) async {
    final repo = _Orders([_order(status: 'pending')]);
    await show(tester, repo);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel order…'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Order #DEL-845 will be cancelled and any reserved stock released. '
        'This cannot be undone.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the list keeps a readable width on an iPad', (tester) async {
    await show(tester, _Orders([_order()]), width: 1200);
    final card = find.ancestor(
      of: find.text('Order #DEL-845'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(card.first).width, lessThanOrEqualTo(800));
  });
}
