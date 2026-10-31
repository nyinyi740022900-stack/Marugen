import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/data/payment_repository.dart';
import 'package:marugen_app/features/orders/presentation/order_detail_screen.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/orders/presentation/orders_screen.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/shared/models/order.dart';

Order order(
  OrderStatus status, {
  String id = 'order-12345',
  String? number,
  double refund = 0,
}) => Order(
  id: id,
  userId: 'customer',
  orderNumber: number,
  status: status,
  total: 20,
  createdAt: DateTime(2026, 10, 10),
  refundAmount: refund,
);

class ResumingPayments implements PaymentRepository {
  ResumingPayments(this.result);
  final Future<Map<String, dynamic>> Function() result;
  final resumed = <String>[];
  @override
  Future<Map<String, dynamic>> resumePayment(String orderId) {
    resumed.add(orderId);
    return result();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class PaidOrders implements OrderRepository {
  @override
  Future<Order?> fetchOrderById(String id) async => order(OrderStatus.paid);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> showPendingOrder(
  WidgetTester tester,
  PaymentRepository payments,
) async {
  var status = OrderStatus.pending;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => const Stream.empty()),
        currentUserIdProvider.overrideWithValue('customer'),
        currentAppUserProvider.overrideWith(
          (ref) async => const AppUser(id: 'customer'),
        ),
        orderByIdProvider('order-12345').overrideWith((ref) async {
          final current = order(status);
          status = OrderStatus.paid;
          return current;
        }),
        paymentRepositoryProvider.overrideWithValue(payments),
        orderRepositoryProvider.overrideWithValue(PaidOrders()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: OrderDetailScreen(
          orderId: 'order-12345',
          order: order(OrderStatus.pending),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a pending order can complete its payment from the order page', (
    tester,
  ) async {
    final payments = ResumingPayments(
      () async => {
        'orderId': 'order-12345',
        'paymentStatus': 'paid',
        'clientSecret': null,
      },
    );
    await showPendingOrder(tester, payments);
    final complete = find.widgetWithText(ElevatedButton, 'Complete payment');
    await tester.scrollUntilVisible(complete, 200);
    await tester.tap(complete);
    await tester.pumpAndSettle();
    expect(payments.resumed, ['order-12345']);
    expect(find.text('Payment received. Thank you!'), findsOneWidget);
  });

  testWidgets('a payment that can no longer be completed says why', (
    tester,
  ) async {
    final payments = ResumingPayments(
      () async => throw Exception(
        'This order can no longer be paid. Check out again from your cart.',
      ),
    );
    await showPendingOrder(tester, payments);
    final complete = find.widgetWithText(ElevatedButton, 'Complete payment');
    await tester.scrollUntilVisible(complete, 200);
    await tester.tap(complete);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This order can no longer be paid. Check out again from your cart.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('checkouts cancelled before payment stay out of My Orders '
      'until asked for', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isLoggedInProvider.overrideWithValue(true),
          myOrdersProvider.overrideWith(
            (ref) async => [
              order(OrderStatus.paid, id: 'paid', number: 'MG-1'),
              order(OrderStatus.cancelled, id: 'unpaid', number: 'MG-2'),
              order(
                OrderStatus.refunded,
                id: 'refunded',
                number: 'MG-3',
                refund: 20,
              ),
            ],
          ),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const OrdersScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Order #MG-1'), findsOneWidget);
    expect(find.text('Order #MG-3'), findsOneWidget);
    expect(find.text('Order #MG-2'), findsNothing);
    await tester.tap(find.text('Show 1 cancelled checkout'));
    await tester.pumpAndSettle();
    expect(find.text('Order #MG-2'), findsOneWidget);
    expect(find.text('Hide cancelled checkouts'), findsOneWidget);
  });

  testWidgets('My Orders tabs group orders by what happens next', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isLoggedInProvider.overrideWithValue(true),
          myOrdersProvider.overrideWith(
            (ref) async => [
              order(OrderStatus.pending, id: 'a', number: 'MG-PAY'),
              order(OrderStatus.packing, id: 'b', number: 'MG-SHIP'),
              order(OrderStatus.shipped, id: 'c', number: 'MG-RECEIVE'),
              order(OrderStatus.delivered, id: 'd', number: 'MG-DONE'),
            ],
          ),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const OrdersScreen()),
      ),
    );
    await tester.pumpAndSettle();
    Iterable<String> shown() => find
        .textContaining('Order #MG-')
        .evaluate()
        .map((e) => (e.widget as Text).data!);
    expect(shown(), hasLength(4));
    for (final (tab, number) in [
      ('To pay', 'MG-PAY'),
      ('To ship', 'MG-SHIP'),
      ('To receive', 'MG-RECEIVE'),
      ('Completed', 'MG-DONE'),
    ]) {
      await tester.tap(find.widgetWithText(ChoiceChip, tab));
      await tester.pumpAndSettle();
      expect(shown(), ['Order #$number'], reason: tab);
    }
  });
}
