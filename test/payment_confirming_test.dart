import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/presentation/order_detail_screen.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/orders/utils/payment_confirmation.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:shared_preferences/shared_preferences.dart';

const confirmingCopy =
    "Payment received. We're confirming it with the bank — this can take a "
    'minute.';

/// The server's order. Only the test (standing in for the Stripe webhook)
/// ever changes [status].
class ServerOrders implements OrderRepository {
  OrderStatus status = OrderStatus.pending;
  int fetches = 0;

  @override
  Future<Order?> fetchOrderById(String id) async {
    fetches++;
    return Order(
      id: id,
      userId: 'customer',
      status: status,
      total: 20,
      createdAt: DateTime(2026, 11, 1),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Product product(String id) => Product.fromMap({
  'id': id,
  'name': 'Koi food $id',
  'category': 'fish_food',
  'price': 20,
  'stock_quantity': 5,
});

Future<ProviderContainer> openOrder(
  WidgetTester tester,
  ServerOrders server, {
  required bool sheetSucceeded,
  bool buyNow = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      authStateProvider.overrideWith((ref) => const Stream.empty()),
      currentUserIdProvider.overrideWithValue('customer'),
      currentAppUserProvider.overrideWith(
        (ref) async => const AppUser(id: 'customer'),
      ),
      orderRepositoryProvider.overrideWithValue(server),
    ],
  );
  addTearDown(container.dispose);
  final cart = container.read(cartProvider.notifier);
  cart.add(product('bought'), quantity: 2);
  final bought = container.read(cartProvider).toList();
  // Something the customer put in the cart that this payment did not buy.
  cart.add(product('later'));
  if (sheetSucceeded) {
    // What checkout does when the sheet succeeded but the webhook is slow.
    container
        .read(paymentAwaitingConfirmationProvider.notifier)
        .state = PaymentAwaitingConfirmation(
      orderId: 'order-12345',
      ownerId: 'customer',
      cartLines: buyNow ? const [] : bought,
    );
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: const OrderDetailScreen(orderId: 'order-12345'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return container;
}

Future<bool> onPage(WidgetTester tester, String text) async {
  final list = find.byType(Scrollable).first;
  final target = find.text(text);
  if (target.evaluate().isNotEmpty) return true;
  try {
    await tester.scrollUntilVisible(target, 300, scrollable: list);
    return true;
  } on StateError {
    return false;
  } finally {
    await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
    await tester.pump();
  }
}

Iterable<String> cartIds(ProviderContainer container) =>
    container.read(cartProvider).map((line) => line.product.id);

void main() {
  test('only a payment sheet that ran and succeeded counts as "just paid"', () async {
    final secretIntent = {'orderId': 'o', 'clientSecret': 'secret'};
    expect(
      await presentPendingPayment(
        intent: secretIntent,
        ownsCheckout: () => true,
        presentPayment: (_) async {},
      ),
      isTrue,
    );
    // Dismissing the sheet throws (Stripe's Canceled) — never "paid".
    var reported = false;
    try {
      reported = await presentPendingPayment(
        intent: secretIntent,
        ownsCheckout: () => true,
        presentPayment: (_) async => throw Exception('Canceled'),
      );
    } catch (_) {}
    expect(reported, isFalse);
    // No sheet shown at all.
    expect(
      await presentPendingPayment(
        intent: {'orderId': 'o', 'paymentStatus': 'pending'},
        ownsCheckout: () => true,
        presentPayment: (_) async {},
      ),
      isFalse,
    );
    // The account changed while the sheet was open.
    var owner = true;
    expect(
      await presentPendingPayment(
        intent: secretIntent,
        ownsCheckout: () => owner,
        presentPayment: (_) async => owner = false,
      ),
      isFalse,
    );
  });

  test('the confirmation window is about a minute and backs off', () {
    final total = paymentConfirmationBackoff.fold(
      Duration.zero,
      (sum, wait) => sum + wait,
    );
    expect(total, const Duration(seconds: 60));
    for (var i = 1; i < paymentConfirmationBackoff.length; i++) {
      expect(
        paymentConfirmationBackoff[i],
        greaterThanOrEqualTo(paymentConfirmationBackoff[i - 1]),
      );
    }
  });

  testWidgets('a paid order with a slow webhook shows confirming, then the '
      'paid order, and only then empties the cart', (tester) async {
    final server = ServerOrders();
    final container = await openOrder(tester, server, sheetSucceeded: true);

    expect(find.text(confirmingCopy), findsOneWidget);
    expect(await onPage(tester, 'Complete payment'), isFalse);
    expect(await onPage(tester, 'Cancel Order'), isFalse);
    expect(cartIds(container), ['bought', 'later']);

    // Still pending on the first re-check: nothing changes.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text(confirmingCopy), findsOneWidget);
    expect(cartIds(container), ['bought', 'later']);

    // The webhook lands.
    server.status = OrderStatus.paid;
    await tester.pump(const Duration(seconds: 3));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(confirmingCopy), findsNothing);
    expect(find.text('Paid'), findsWidgets);
    expect(await onPage(tester, 'Complete payment'), isFalse);
    expect(cartIds(container), ['later']);
    expect(container.read(paymentAwaitingConfirmationProvider), isNull);

    // Confirmed: the re-checking is over.
    final settled = server.fetches;
    await tester.pump(const Duration(minutes: 2));
    expect(server.fetches, settled);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Buy Now leaves the cart alone when its payment is confirmed', (
    tester,
  ) async {
    final server = ServerOrders();
    final container = await openOrder(
      tester,
      server,
      sheetSucceeded: true,
      buyNow: true,
    );
    expect(find.text(confirmingCopy), findsOneWidget);
    server.status = OrderStatus.paid;
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(confirmingCopy), findsNothing);
    expect(cartIds(container), ['bought', 'later']);
  });

  testWidgets('a dismissed payment sheet never shows "payment received"', (
    tester,
  ) async {
    final server = ServerOrders();
    final container = await openOrder(tester, server, sheetSucceeded: false);
    expect(find.text(confirmingCopy), findsNothing);
    expect(await onPage(tester, 'Complete payment'), isTrue);
    final fetched = server.fetches;
    await tester.pump(const Duration(minutes: 2));
    expect(server.fetches, fetched, reason: 'no re-checking without a payment');
    expect(cartIds(container), ['bought', 'later']);
  });

  testWidgets('still pending after the window falls back to the normal '
      'pending order', (tester) async {
    final server = ServerOrders();
    final container = await openOrder(tester, server, sheetSucceeded: true);
    expect(find.text(confirmingCopy), findsOneWidget);

    for (final wait in paymentConfirmationBackoff) {
      expect(find.text(confirmingCopy), findsOneWidget);
      await tester.pump(wait);
      await tester.pump();
    }
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(confirmingCopy), findsNothing);
    expect(await onPage(tester, 'Complete payment'), isTrue);
    // Never paid as far as the server said: the cart is untouched.
    expect(cartIds(container), ['bought', 'later']);

    final fetched = server.fetches;
    await tester.pump(const Duration(minutes: 2));
    expect(server.fetches, fetched, reason: 'the window is bounded');
  });

  testWidgets('leaving the order screen stops the re-checking', (tester) async {
    final server = ServerOrders();
    await openOrder(tester, server, sheetSucceeded: true);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    final fetched = server.fetches;

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
    expect(server.fetches, fetched);
  });
}
