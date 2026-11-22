// Page review 22 Nov 2026, order page: the exit after a slow confirmation
// (P0), the "still confirming" state, the GST line, the push question on
// the confirming path, 48 dp review controls and the staff action bar.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/core/notifications/push_permission_prompt.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/admin_shell.dart'
    show adminTabIndexProvider, kAdminOrdersTab;
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/presentation/order_detail_screen.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/orders/presentation/orders_screen.dart';
import 'package:marugen_app/features/orders/presentation/staff_order_actions.dart';
import 'package:marugen_app/features/orders/utils/payment_confirmation.dart';
import 'package:marugen_app/features/reviews/data/review_repository.dart';
import 'package:marugen_app/features/reviews/presentation/review_providers.dart';
import 'package:marugen_app/features/shop/presentation/shell_tab_provider.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/models/order_cancellation_request.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/models/review.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const orderId = 'order-12345';
const confirmingCopy =
    "Payment received. We're confirming it with the bank — this can take a "
    'minute.';

Order order(
  OrderStatus status, {
  String? userId = 'customer',
  String? fulfillmentMethod,
  double? gstPercent,
  bool? gstIncluded,
  int? gstCents,
  List<OrderItem> items = const [],
  OrderCancellationRequest? cancellation,
  String? refundStatus,
  String? trackingProvider,
  bool trackingRegistered = false,
}) => Order(
  id: orderId,
  userId: userId,
  orderNumber: '1234',
  status: status,
  total: 21.8,
  createdAt: DateTime(2026, 11, 1),
  items: items,
  fulfillmentMethod: fulfillmentMethod,
  gstPercent: gstPercent,
  gstIncludedInPrice: gstIncluded,
  gstAmountCents: gstCents,
  cancellationRequest: cancellation,
  refundStatus: refundStatus,
  trackingProvider: trackingProvider,
  trackingRegistered: trackingRegistered,
);

class _Reviews implements ReviewRepository {
  _Reviews(this.mine);
  final ProductReview? mine;

  @override
  Future<ProductReview?> fetchMyReview(String productId) async => mine;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The server. Only the test changes what it holds.
class Server implements OrderRepository {
  Server(this.current);
  Order current;
  int fetches = 0;
  final statusWrites = <OrderStatus>[];
  final refunds = <String>[];

  @override
  Future<Order?> fetchOrderById(String id) async {
    fetches++;
    return current;
  }

  @override
  Future<List<Order>> fetchMyOrders() async => [current];

  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    statusWrites.add(status);
  }

  @override
  Future<void> refundOrder(
    String orderId, {
    String? reason,
    bool refreshOnly = false,
  }) async => refunds.add(orderId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer containerFor(
  Server server, {
  UserRole role = UserRole.customer,
  String userId = 'customer',
  List<Override> extra = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      authStateProvider.overrideWith((ref) => const Stream.empty()),
      currentUserIdProvider.overrideWithValue(userId),
      isLoggedInProvider.overrideWithValue(true),
      currentAppUserProvider.overrideWith(
        (ref) async => AppUser(id: userId, role: role),
      ),
      orderRepositoryProvider.overrideWithValue(server),
      shopSettingsProvider.overrideWith((ref) async => <String, dynamic>{}),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Opens the order the way checkout does (`go`, nothing underneath) or the
/// way the Orders list does (`push` on top of the shell).
Future<GoRouter> openOrder(
  WidgetTester tester,
  ProviderContainer container, {
  required bool reachedWithGo,
  bool justPlaced = false,
}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final location = '/orders/$orderId${justPlaced ? '?justPlaced=true' : ''}';
  final router = GoRouter(
    initialLocation: reachedWithGo ? location : '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('SHOP SHELL')),
      ),
      GoRoute(
        path: '/admin',
        builder: (_, _) => const Scaffold(body: Text('ADMIN SHELL')),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (_, state) => OrderDetailScreen(
          orderId: state.pathParameters['id']!,
          justPlaced: state.uri.queryParameters['justPlaced'] == 'true',
        ),
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
  await tester.pump();
  if (!reachedWithGo) {
    router.push(location);
    await tester.pumpAndSettle();
  }
  await tester.pump();
  await tester.pump();
  return router;
}

void awaitPayment(ProviderContainer container, {bool windowElapsed = false}) {
  var record = const PaymentAwaitingConfirmation(
    orderId: orderId,
    ownerId: 'customer',
  );
  if (windowElapsed) record = record.withWindowElapsed();
  container.read(paymentAwaitingConfirmationProvider.notifier).state = record;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('exit from an order page with nothing underneath', () {
    testWidgets('reached with go: a close button returns to the Shop tab', (
      tester,
    ) async {
      final container = containerFor(Server(order(OrderStatus.paid)));
      container.read(customerTabIndexProvider.notifier).state = 2;
      await openOrder(tester, container, reachedWithGo: true);

      expect(find.byType(BackButton), findsNothing);
      expect(find.byTooltip('Back to shop'), findsOneWidget);
      // And a button in the page itself, next to Reorder.
      expect(find.text('Continue Shopping'), findsOneWidget);
      expect(find.text('Reorder'), findsOneWidget);

      await tester.tap(find.byTooltip('Back to shop'));
      await tester.pumpAndSettle();
      expect(find.text('SHOP SHELL'), findsOneWidget);
      expect(container.read(customerTabIndexProvider), 0);
    });

    testWidgets('pushed from a list: the ordinary back arrow, no close and '
        'no Continue Shopping', (tester) async {
      final container = containerFor(Server(order(OrderStatus.paid)));
      await openOrder(tester, container, reachedWithGo: false);

      expect(find.byTooltip('Back to shop'), findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.text('Continue Shopping'), findsNothing);
      expect(find.text('Reorder'), findsOneWidget);
    });

    testWidgets('a payment still being confirmed after checkout is not a '
        'dead end: Continue Shopping, no Reorder, no pay-again', (
      tester,
    ) async {
      final container = containerFor(Server(order(OrderStatus.pending)));
      awaitPayment(container);
      await openOrder(tester, container, reachedWithGo: true);

      expect(find.text(confirmingCopy), findsOneWidget);
      expect(find.byTooltip('Back to shop'), findsOneWidget);
      expect(find.text('Continue Shopping'), findsOneWidget);
      expect(find.text('Reorder'), findsNothing);
      expect(find.text('Complete payment'), findsNothing);
      expect(find.text('Cancel Order'), findsNothing);

      await tester.tap(find.text('Continue Shopping'));
      await tester.pumpAndSettle();
      expect(find.text('SHOP SHELL'), findsOneWidget);
    });

    testWidgets('confirming on a pushed order page still offers Continue '
        'Shopping and hides Reorder', (tester) async {
      final container = containerFor(Server(order(OrderStatus.pending)));
      awaitPayment(container);
      await openOrder(tester, container, reachedWithGo: false);
      expect(find.text('Continue Shopping'), findsOneWidget);
      expect(find.text('Reorder'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a just-placed order keeps its single Continue Shopping', (
      tester,
    ) async {
      final container = containerFor(Server(order(OrderStatus.paid)));
      await openOrder(
        tester,
        container,
        reachedWithGo: true,
        justPlaced: true,
      );
      expect(find.text('Continue Shopping'), findsOneWidget);
      expect(find.text('Reorder'), findsNothing);
      expect(find.byTooltip('Back to shop'), findsOneWidget);
    });
  });

  group('still confirming after the minute', () {
    testWidgets('the window running out never brings back Complete payment '
        'or Cancel Order', (tester) async {
      final server = Server(order(OrderStatus.pending));
      final container = containerFor(server);
      awaitPayment(container);
      await openOrder(tester, container, reachedWithGo: true);
      expect(find.text(confirmingCopy), findsOneWidget);

      for (final wait in paymentConfirmationBackoff) {
        await tester.pump(wait);
        await tester.pump();
      }
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text(confirmingCopy), findsNothing);
      expect(find.text(stillConfirmingPaymentCopy), findsOneWidget);
      expect(
        stillConfirmingPaymentCopy,
        "We're still confirming your payment. You have not been charged "
        "twice — please don't pay again. Pull down to refresh, or contact "
        "us if this hasn't updated in 10 minutes.",
      );
      expect(find.text('Contact support'), findsOneWidget);
      expect(find.text('Complete payment'), findsNothing);
      expect(find.text('Cancel Order'), findsNothing);
      expect(find.text('Reorder'), findsNothing);
      expect(find.text('Continue Shopping'), findsOneWidget);
      // Kept (and kept on the device) until the order settles.
      final record = container.read(paymentAwaitingConfirmationProvider);
      expect(record?.windowElapsed, isTrue);

      // The automatic re-checking is over.
      final fetched = server.fetches;
      await tester.pump(const Duration(minutes: 5));
      expect(server.fetches, fetched);
    });

    testWidgets('Contact support opens the picker with the order number', (
      tester,
    ) async {
      final container = containerFor(Server(order(OrderStatus.pending)));
      awaitPayment(container, windowElapsed: true);
      await openOrder(tester, container, reachedWithGo: true);

      await tester.tap(find.text('Contact support'));
      await tester.pumpAndSettle();
      expect(find.text('Contact Support'), findsOneWidget);
    });

    testWidgets('pull to refresh after the webhook landed ends the state and '
        'clears the saved record', (tester) async {
      final server = Server(order(OrderStatus.pending));
      final container = containerFor(server);
      awaitPayment(container, windowElapsed: true);
      await openOrder(tester, container, reachedWithGo: true);
      expect(find.text(stillConfirmingPaymentCopy), findsOneWidget);

      server.current = order(OrderStatus.paid);
      container.invalidate(orderByIdProvider(orderId));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text(stillConfirmingPaymentCopy), findsNothing);
      expect(container.read(paymentAwaitingConfirmationProvider), isNull);
      expect(find.text('Reorder'), findsOneWidget);
    });

    testWidgets('a cancelled order ends the state too', (tester) async {
      final server = Server(order(OrderStatus.pending));
      final container = containerFor(server);
      awaitPayment(container, windowElapsed: true);
      await openOrder(tester, container, reachedWithGo: true);

      server.current = order(OrderStatus.cancelled);
      container.invalidate(orderByIdProvider(orderId));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text(stillConfirmingPaymentCopy), findsNothing);
      expect(container.read(paymentAwaitingConfirmationProvider), isNull);
    });

    testWidgets('the Orders list offers no Complete payment for that order', (
      tester,
    ) async {
      final server = Server(order(OrderStatus.pending));
      final container = containerFor(server);
      Future<void> showList() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light,
              home: const OrdersScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
      }

      await showList();
      expect(find.text('Complete payment'), findsOneWidget);

      awaitPayment(container, windowElapsed: true);
      await tester.pump();
      expect(find.text('Complete payment'), findsNothing);
      expect(find.text('Order #1234'), findsOneWidget);

      // Record cleared (order cancelled by the stale-order cleanup, say):
      // an ordinary pending order again.
      container.read(paymentAwaitingConfirmationProvider.notifier).state = null;
      await tester.pump();
      expect(find.text('Complete payment'), findsOneWidget);
    });

    testWidgets('the Orders list settles the record when it shows the order '
        'paid', (tester) async {
      final server = Server(order(OrderStatus.pending));
      final container = containerFor(server);
      final cart = container.read(cartProvider.notifier);
      cart.add(
        Product.fromMap({
          'id': 'bought',
          'name': 'Koi food',
          'category': 'fish_food',
          'price': 20,
          'stock_quantity': 5,
        }),
      );
      final bought = container.read(cartProvider).toList();
      container
          .read(paymentAwaitingConfirmationProvider.notifier)
          .state = PaymentAwaitingConfirmation(
        orderId: orderId,
        ownerId: 'customer',
        cartLines: bought,
      ).withWindowElapsed();
      server.current = order(OrderStatus.paid);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.light, home: const OrdersScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(container.read(paymentAwaitingConfirmationProvider), isNull);
      expect(container.read(cartProvider), isEmpty);
    });
  });

  group('GST line on the order', () {
    testWidgets('inclusive GST is a muted note under the total', (
      tester,
    ) async {
      final container = containerFor(
        Server(
          order(
            OrderStatus.paid,
            gstPercent: 9,
            gstIncluded: true,
            gstCents: 180,
          ),
        ),
      );
      await openOrder(tester, container, reachedWithGo: false);
      final note = find.text('Includes GST (9%) of S\$1.80');
      expect(note, findsOneWidget);
      expect(find.text('GST (9%)'), findsNothing);
      expect(
        tester.getTopLeft(note).dy,
        greaterThan(tester.getTopLeft(find.text('Total')).dy),
      );
    });

    testWidgets('GST added on top is a row above the total', (tester) async {
      final container = containerFor(
        Server(
          order(
            OrderStatus.paid,
            gstPercent: 9,
            gstIncluded: false,
            gstCents: 180,
          ),
        ),
      );
      await openOrder(tester, container, reachedWithGo: false);
      expect(find.text('GST (9%)'), findsOneWidget);
      expect(find.textContaining('Includes GST'), findsNothing);
      expect(
        tester.getTopLeft(find.text('GST (9%)')).dy,
        lessThan(tester.getTopLeft(find.text('Total')).dy),
      );
    });

    testWidgets('an order without a GST snapshot shows no GST line', (
      tester,
    ) async {
      final container = containerFor(Server(order(OrderStatus.paid)));
      await openOrder(tester, container, reachedWithGo: false);
      expect(find.textContaining('GST'), findsNothing);
    });
  });

  group('push reason on the confirming path', () {
    late Future<bool> Function() canAsk;
    late Future<void> Function() request;
    setUp(() {
      canAsk = PushPermissionPrompt.canAsk;
      request = PushPermissionPrompt.requestPermission;
    });
    tearDown(() {
      PushPermissionPrompt.canAsk = canAsk;
      PushPermissionPrompt.requestPermission = request;
    });

    testWidgets('a payment being confirmed asks the one-time question', (
      tester,
    ) async {
      PushPermissionPrompt.canAsk = () async => true;
      var requested = 0;
      PushPermissionPrompt.requestPermission = () async => requested++;
      final container = containerFor(Server(order(OrderStatus.pending)));
      awaitPayment(container);
      await openOrder(tester, container, reachedWithGo: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(PushPermissionPrompt.reason), findsOneWidget);
      await tester.tap(find.text('Turn on notifications'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(requested, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an ordinary pending order does not ask', (tester) async {
      PushPermissionPrompt.canAsk = () async => true;
      final container = containerFor(Server(order(OrderStatus.pending)));
      await openOrder(tester, container, reachedWithGo: true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(PushPermissionPrompt.reason), findsNothing);
    });
  });

  group('review controls on a delivered order', () {
    const item = OrderItem(
      id: 'line',
      productId: 'product',
      productName: 'Koi food',
      quantity: 1,
      unitPrice: 20,
    );
    Future<void> show(WidgetTester tester, ProductReview? mine) async {
      final container = containerFor(
        Server(order(OrderStatus.delivered, items: const [item])),
        extra: [
          reviewRepositoryProvider.overrideWithValue(_Reviews(mine)),
        ],
      );
      await openOrder(tester, container, reachedWithGo: false);
      await tester.pump();
    }

    testWidgets('"Write a review" is at least 48 dp tall', (tester) async {
      await show(tester, null);
      final button = find.widgetWithText(OutlinedButton, 'Write a review');
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
    });

    testWidgets('"Edit your review" is at least 48 dp tall', (tester) async {
      await show(
        tester,
        ProductReview(
          id: 'review',
          productId: 'product',
          userId: 'customer',
          rating: 4,
          createdAt: DateTime(2026, 11, 2),
        ),
      );
      final target = find.ancestor(
        of: find.text('Edit your review'),
        matching: find.byType(InkWell),
      );
      expect(target, findsOneWidget);
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    });
  });

  group('staff action bar', () {
    test('the primary action follows the order state', () {
      expect(
        staffPrimaryActionFor(order(OrderStatus.paid, fulfillmentMethod: 'courier')),
        StaffOrderAction.startPacking,
      );
      expect(
        staffPrimaryActionFor(
          order(OrderStatus.packing, fulfillmentMethod: 'courier'),
        ),
        StaffOrderAction.manageDelivery,
      );
      // Booked with the courier, waiting for pickup.
      expect(
        staffPrimaryActionFor(
          order(
            OrderStatus.shipped,
            fulfillmentMethod: 'courier',
            trackingProvider: 'easyparcel',
            trackingRegistered: true,
          ),
        ),
        StaffOrderAction.manageDelivery,
      );
      expect(
        staffPrimaryActionFor(
          order(OrderStatus.shipped, fulfillmentMethod: 'shop_delivery'),
        ),
        StaffOrderAction.markDelivered,
      );
      // Paid, but the delivery method needs a decision first.
      expect(
        staffPrimaryActionFor(order(OrderStatus.paid)),
        StaffOrderAction.manageDelivery,
      );
      for (final status in [
        OrderStatus.pending,
        OrderStatus.delivered,
        OrderStatus.cancelled,
        OrderStatus.refunded,
      ]) {
        expect(staffPrimaryActionFor(order(status)), isNull);
      }
      // A cancellation hold is handled by the cancellation panel.
      final held = order(
        OrderStatus.paid,
        fulfillmentMethod: 'courier',
        cancellation: const OrderCancellationRequest(status: 'requested'),
      );
      expect(staffPrimaryActionFor(held), isNull);
      expect(staffCanRefund(held), isFalse);
    });

    test('refund and cancel follow the admin Orders rules', () {
      expect(staffCanCancel(order(OrderStatus.pending)), isTrue);
      expect(staffCanRefund(order(OrderStatus.pending)), isFalse);
      for (final status in [
        OrderStatus.paid,
        OrderStatus.packing,
        OrderStatus.shipped,
        OrderStatus.delivered,
      ]) {
        expect(staffCanRefund(order(status)), isTrue, reason: status.name);
        expect(staffCanCancel(order(status)), isFalse, reason: status.name);
      }
      expect(
        staffCanRefund(order(OrderStatus.paid, refundStatus: 'pending')),
        isFalse,
      );
      expect(staffCanRefund(order(OrderStatus.refunded)), isFalse);
      expect(staffCanCancel(order(OrderStatus.cancelled)), isFalse);
    });

    testWidgets('Start packing writes the status once, with no shopper '
        'buttons on the page', (tester) async {
      final server = Server(
        order(OrderStatus.paid, fulfillmentMethod: 'courier', userId: 'buyer'),
      );
      final container = containerFor(server, role: UserRole.staff, userId: 's');
      await openOrder(tester, container, reachedWithGo: false);

      expect(find.text('Reorder'), findsNothing);
      expect(find.text('Complete payment'), findsNothing);
      await tester.tap(find.text('Start packing'));
      await tester.pumpAndSettle();
      expect(server.statusWrites, [OrderStatus.packing]);
    });

    testWidgets('Manage delivery focuses the order on the Fulfillment tab', (
      tester,
    ) async {
      final server = Server(
        order(
          OrderStatus.packing,
          fulfillmentMethod: 'courier',
          userId: 'buyer',
        ),
      );
      final container = containerFor(server, role: UserRole.staff, userId: 's');
      await openOrder(tester, container, reachedWithGo: false);

      await tester.tap(find.text('Manage delivery'));
      await tester.pumpAndSettle();
      expect(container.read(focusFulfillmentOrderProvider), orderId);
      expect(container.read(requestedOrdersTabProvider), 1);
      expect(container.read(adminTabIndexProvider), kAdminOrdersTab);
      expect(find.text('ADMIN SHELL'), findsOneWidget);
      expect(server.statusWrites, isEmpty);
    });

    testWidgets('Mark as delivered asks first; Cancel in the dialog writes '
        'nothing', (tester) async {
      final server = Server(
        order(
          OrderStatus.shipped,
          fulfillmentMethod: 'shop_delivery',
          userId: 'buyer',
        ),
      );
      final container = containerFor(server, role: UserRole.staff, userId: 's');
      await openOrder(tester, container, reachedWithGo: false);

      await tester.tap(find.text('Mark as delivered'));
      await tester.pumpAndSettle();
      expect(find.text('Mark as delivered?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.statusWrites, isEmpty);

      await tester.tap(find.text('Mark as delivered'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark Delivered'));
      await tester.pumpAndSettle();
      expect(server.statusWrites, [OrderStatus.delivered]);
    });

    testWidgets('the overflow refunds through the refund endpoint after a '
        'confirmation', (tester) async {
      final server = Server(
        order(OrderStatus.paid, fulfillmentMethod: 'courier', userId: 'buyer'),
      );
      final container = containerFor(server, role: UserRole.owner, userId: 's');
      await openOrder(tester, container, reachedWithGo: false);

      await tester.tap(find.byTooltip('More order actions'));
      await tester.pumpAndSettle();
      expect(find.text('Refund order…'), findsOneWidget);
      // A paid order is refunded, never cancelled outright.
      expect(find.text('Cancel order…'), findsNothing);
      await tester.tap(find.text('Refund order…'));
      await tester.pumpAndSettle();
      expect(find.text('Refund this order?'), findsOneWidget);
      // The same dialog as Orders > All: the amount on the message and on
      // the button.
      expect(
        find.text("Refund S\$21.80 to the customer's original payment method?"),
        findsOneWidget,
      );
      await tester.tap(find.text('Refund S\$21.80'));
      await tester.pumpAndSettle();
      expect(server.refunds, [orderId]);
      expect(server.statusWrites, isEmpty);
    });

    testWidgets('an unpaid order can only be cancelled, after a '
        'confirmation', (tester) async {
      final server = Server(order(OrderStatus.pending, userId: 'buyer'));
      final container = containerFor(server, role: UserRole.staff, userId: 's');
      await openOrder(tester, container, reachedWithGo: false);

      expect(find.text('Start packing'), findsNothing);
      await tester.tap(find.byTooltip('More order actions'));
      await tester.pumpAndSettle();
      expect(find.text('Refund order…'), findsNothing);
      await tester.tap(find.text('Cancel order…'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this order?'), findsOneWidget);
      expect(find.text('Keep order'), findsOneWidget);
      await tester.tap(find.text('Cancel order'));
      await tester.pumpAndSettle();
      expect(server.statusWrites, [OrderStatus.cancelled]);
    });

    testWidgets('a customer never sees the staff bar', (tester) async {
      final container = containerFor(
        Server(order(OrderStatus.paid, fulfillmentMethod: 'courier')),
      );
      await openOrder(tester, container, reachedWithGo: false);
      expect(find.text('Start packing'), findsNothing);
      expect(find.byTooltip('More order actions'), findsNothing);
    });
  });

  test('the saved record round-trips by line id', () async {
    // Guards the storage format the next launch depends on.
    SharedPreferences.setMockInitialValues({});
    await PaymentAwaitingStore.save(
      const PaymentAwaitingConfirmation(
        orderId: orderId,
        ownerId: 'customer',
        restoredLines: [
          PurchasedLine(productId: 'p', variantId: 'v', size: 'L'),
        ],
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    final raw =
        jsonDecode(prefs.getString(PaymentAwaitingStore.prefsKey('customer'))!)
            as Map;
    expect(raw['order_id'], orderId);
    final restored = await PaymentAwaitingStore.read('customer');
    expect(restored!.windowElapsed, isTrue);
    expect(restored.purchasedLines.single.productId, 'p');
    expect(restored.purchasedLines.single.variantId, 'v');
    expect(restored.purchasedLines.single.size, 'L');
    expect(await PaymentAwaitingStore.read('someone-else'), isNull);
  });
}
