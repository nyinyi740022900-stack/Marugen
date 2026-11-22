// Page review 22 Nov 2026, checkout: back is held while a payment is being
// taken, the pay button says what is happening, and a payment still being
// confirmed when the app is closed is settled on the next launch.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/auth/data/auth_repository.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/data/payment_repository.dart';
import 'package:marugen_app/features/orders/presentation/checkout_screen.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/orders/presentation/shipping_quote_providers.dart';
import 'package:marugen_app/features/profile/presentation/address_providers.dart';
import 'package:marugen_app/features/shop/data/product_repository.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/address.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shipping_test_fixtures.dart';

const cartKey = 'cart_items_v1::customer';
final awaitingKey = PaymentAwaitingStore.prefsKey('customer');

Product product(String id) => Product(
  id: id,
  name: id,
  category: ProductCategory.accessories,
  price: 10,
  stockQuantity: 5,
);

class Catalogue implements ProductRepository {
  @override
  Future<Product?> fetchProductById(String id) async => product(id);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Server implements OrderRepository {
  Server(this.status);
  OrderStatus? status;
  bool offline = false;
  int fetches = 0;

  @override
  Future<Order?> fetchOrderById(String id) async {
    fetches++;
    if (offline) throw Exception('offline');
    final current = status;
    return current == null
        ? null
        : Order(
            id: id,
            userId: 'customer',
            status: current,
            total: 20,
            createdAt: DateTime(2026, 11, 1),
          );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

String cartJson(List<String> ids) => jsonEncode([
  for (final id in ids)
    {'product_id': id, 'variant_id': null, 'size_label': null, 'quantity': 1},
]);

String awaitingJson({String owner = 'customer'}) => jsonEncode({
  'order_id': 'order-1',
  'owner_id': owner,
  'lines': [
    {'product_id': 'bought', 'variant_id': null, 'size_label': null},
  ],
});

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<List<String>> savedCart() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(cartKey);
  return [
    if (raw != null)
      for (final line in jsonDecode(raw) as List)
        (line as Map)['product_id'] as String,
  ];
}

/// "The next launch": a fresh container over whatever the device stored.
ProviderContainer launch(Server server, {String? userId = 'customer'}) {
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue(userId),
      productRepositoryProvider.overrideWithValue(Catalogue()),
      orderRepositoryProvider.overrideWithValue(server),
    ],
  );
  addTearDown(container.dispose);
  // What the Orders tab and the order page do on launch.
  container.listen(paymentAwaitingConfirmationProvider, (_, _) {});
  return container;
}

List<String> cartIds(ProviderContainer container) => [
  for (final line in container.read(cartProvider)) line.product.id,
];

/// The cart once whatever was saved on the device has been restored.
Future<List<String>> restoredCart(ProviderContainer container) async {
  container.read(cartProvider);
  await settle();
  return cartIds(container);
}

class _HeldPayments implements PaymentRepository {
  final intent = Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> createPaymentIntent({
    required List<Map<String, dynamic>> items,
    Map<String, dynamic>? shippingAddress,
    String currency = 'sgd',
    String? promoCode,
    String? shippingQuoteId,
    String? idempotencyKey,
    String? customerRemarks,
    int customerRemarksRevision = 0,
  }) => intent.future;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _VerifiedAuth implements AuthRepository {
  @override
  bool get isEmailVerified => true;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('next launch after the app was closed mid-confirmation', () {
    test('order now paid: the bought lines leave the cart and the record '
        'is cleared', () async {
      SharedPreferences.setMockInitialValues({
        cartKey: cartJson(['bought', 'later']),
        awaitingKey: awaitingJson(),
      });
      final server = Server(OrderStatus.paid);
      final container = launch(server);
      await settle();

      expect(server.fetches, 1);
      expect(container.read(paymentAwaitingConfirmationProvider), isNull);
      expect(cartIds(container), ['later']);
      expect(await savedCart(), ['later']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(awaitingKey), isNull);
    });

    test('the cart restored before the record is settled ends the same', () async {
      SharedPreferences.setMockInitialValues({
        cartKey: cartJson(['bought', 'later']),
        awaitingKey: awaitingJson(),
      });
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('customer'),
          productRepositoryProvider.overrideWithValue(Catalogue()),
          orderRepositoryProvider.overrideWithValue(Server(OrderStatus.paid)),
        ],
      );
      addTearDown(container.dispose);
      container.read(cartProvider);
      await settle();
      expect(cartIds(container), ['bought', 'later']);

      container.listen(paymentAwaitingConfirmationProvider, (_, _) {});
      await settle();
      expect(cartIds(container), ['later']);
      expect(await savedCart(), ['later']);
    });

    test('order still pending: the record stays as "still confirming" and '
        'the cart is untouched', () async {
      SharedPreferences.setMockInitialValues({
        cartKey: cartJson(['bought', 'later']),
        awaitingKey: awaitingJson(),
      });
      final container = launch(Server(OrderStatus.pending));
      await settle();

      final record = container.read(paymentAwaitingConfirmationProvider);
      expect(record?.orderId, 'order-1');
      expect(record?.windowElapsed, isTrue);
      expect(await restoredCart(container), ['bought', 'later']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(awaitingKey), isNotNull);
    });

    for (final status in [OrderStatus.cancelled, OrderStatus.refunded, null]) {
      test('order ${status?.name ?? 'gone'}: the record is cleared and the '
          'cart is untouched', () async {
        SharedPreferences.setMockInitialValues({
          cartKey: cartJson(['bought', 'later']),
          awaitingKey: awaitingJson(),
        });
        final container = launch(Server(status));
        await settle();

        expect(container.read(paymentAwaitingConfirmationProvider), isNull);
        expect(await restoredCart(container), ['bought', 'later']);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(awaitingKey), isNull);
      });
    }

    test('offline at launch: nothing is decided, the record is kept', () async {
      SharedPreferences.setMockInitialValues({
        cartKey: cartJson(['bought', 'later']),
        awaitingKey: awaitingJson(),
      });
      final container = launch(Server(OrderStatus.paid)..offline = true);
      await settle();

      expect(
        container.read(paymentAwaitingConfirmationProvider)?.orderId,
        'order-1',
      );
      expect(await restoredCart(container), ['bought', 'later']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(awaitingKey), isNotNull);
    });

    test("another account's record is never read", () async {
      SharedPreferences.setMockInitialValues({awaitingKey: awaitingJson()});
      final server = Server(OrderStatus.paid);
      final container = launch(server, userId: 'someone-else');
      await settle();
      expect(container.read(paymentAwaitingConfirmationProvider), isNull);
      expect(server.fetches, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(awaitingKey), isNotNull);
    });

    test('a record written for a different owner under this key is dropped', () async {
      SharedPreferences.setMockInitialValues({
        awaitingKey: awaitingJson(owner: 'someone-else'),
      });
      final server = Server(OrderStatus.paid);
      final container = launch(server);
      await settle();
      expect(container.read(paymentAwaitingConfirmationProvider), isNull);
      expect(server.fetches, 0);
    });

    test('a guest has nothing to restore', () async {
      SharedPreferences.setMockInitialValues({awaitingKey: awaitingJson()});
      final server = Server(OrderStatus.paid);
      final container = launch(server, userId: null);
      await settle();
      expect(container.read(paymentAwaitingConfirmationProvider), isNull);
      expect(server.fetches, 0);
    });
  });

  test('a sheet that succeeded is saved with the order, owner and lines', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue('customer'),
        productRepositoryProvider.overrideWithValue(Catalogue()),
        orderRepositoryProvider.overrideWithValue(Server(OrderStatus.pending)),
      ],
    );
    addTearDown(container.dispose);
    setPaymentAwaiting(
      container.read,
      PaymentAwaitingConfirmation(
        orderId: 'order-1',
        ownerId: 'customer',
        cartLines: [CartItem(product: product('bought'), quantity: 2)],
      ),
    );
    await settle();

    expect(
      container.read(paymentAwaitingConfirmationProvider)?.windowElapsed,
      isFalse,
    );
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString(awaitingKey)!) as Map;
    expect(saved['order_id'], 'order-1');
    expect(saved['owner_id'], 'customer');
    expect((saved['lines'] as List).single['product_id'], 'bought');
  });

  group('checkout while a payment is processing', () {
    const item = CartItem(
      product: Product(
        id: 'food',
        name: 'Fish food',
        category: ProductCategory.accessories,
        price: 10,
      ),
      quantity: 2,
    );
    const address = Address(
      id: 'address',
      userId: 'customer',
      recipientName: 'Customer',
      phone: '81234567',
      line1: '1 Street',
      postalCode: '123456',
    );

    Future<_HeldPayments> show(
      WidgetTester tester, {
      bool gstIncluded = true,
    }) async {
      tester.view.physicalSize = const Size(390, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final payments = _HeldPayments();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('customer'),
            authRepositoryProvider.overrideWithValue(_VerifiedAuth()),
            paymentRepositoryProvider.overrideWithValue(payments),
            shopSettingsProvider.overrideWith(
              (ref) async => {
                'gst_percent': 9,
                'gst_included_in_price': gstIncluded,
              },
            ),
            myAddressesProvider.overrideWith((ref) async => [address]),
            checkoutShippingQuoteProvider.overrideWith(
              (ref, key) async => fixtureShippingQuote(key),
            ),
          ],
          child: const MaterialApp(home: CheckoutScreen(buyNowItems: [item])),
        ),
      );
      await tester.pumpAndSettle();
      return payments;
    }

    testWidgets('back is held and the button says to keep the screen open; '
        'both end when the payment does', (tester) async {
      final payments = await show(tester);
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
      expect(find.text(checkoutProcessingLabel), findsNothing);

      await tester.tap(find.textContaining('with Stripe'));
      await tester.pump();

      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
      expect(
        checkoutProcessingLabel,
        'Confirming payment… please keep this screen open',
      );
      expect(find.text(checkoutProcessingLabel), findsOneWidget);
      // The app-bar arrow would do nothing while back is held.
      expect(find.byType(BackButton), findsNothing);
      // A second tap cannot start a second payment.
      final button = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text(checkoutProcessingLabel),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);

      payments.intent.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
      expect(find.text(checkoutProcessingLabel), findsNothing);
    });

    testWidgets('inclusive GST is a note under the total, so the rows above '
        'add up', (tester) async {
      await show(tester);
      // 2 x S$10.00 including 9% GST.
      final note = find.text('Includes GST (9%) of S\$1.65');
      expect(note, findsOneWidget);
      expect(find.text('GST (9%)'), findsNothing);
      expect(
        tester.getTopLeft(note).dy,
        greaterThan(tester.getTopLeft(find.text('Total (incl. GST)')).dy),
      );
      // Subtotal 20.00 + delivery 2.02 = the total, with no GST row between.
      expect(find.text('S\$22.02'), findsOneWidget);
    });

    testWidgets('GST added on top stays a row above the total', (tester) async {
      await show(tester, gstIncluded: false);
      expect(find.text('GST (9%)'), findsOneWidget);
      expect(find.textContaining('Includes GST'), findsNothing);
      expect(
        tester.getTopLeft(find.text('GST (9%)')).dy,
        lessThan(tester.getTopLeft(find.text('Total')).dy),
      );
    });
  });
}
