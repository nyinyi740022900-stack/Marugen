// Code review 22 Nov 2026, checkout: a confirmed payment takes only what it
// bought out of the cart (units added while it was being confirmed stay),
// and a "still confirming" record the server never confirms is given up on
// after two hours.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/shop/data/product_repository.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:shared_preferences/shared_preferences.dart';

const cartKey = 'cart_items_v1::customer';
final awaitingKey = PaymentAwaitingStore.prefsKey('customer');

Product product(String id) => Product(
  id: id,
  name: id,
  category: ProductCategory.accessories,
  price: 10,
  stockQuantity: 9,
);

class Catalogue implements ProductRepository {
  bool offline = false;

  @override
  Future<Product?> fetchProductById(String id) async {
    if (offline) throw Exception('offline');
    return product(id);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Server implements OrderRepository {
  Server(this.status);
  OrderStatus status;
  int fetches = 0;

  Order order() => Order(
    id: 'order-1',
    userId: 'customer',
    status: status,
    total: 20,
    createdAt: DateTime(2026, 11, 1),
  );

  @override
  Future<Order?> fetchOrderById(String id) async {
    fetches++;
    return order();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Clock {
  DateTime time = DateTime.utc(2026, 11, 22, 10);
  DateTime call() => time;
}

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderContainer containerFor(
  Server server, {
  Clock? clock,
  Catalogue? catalogue,
}) {
  final container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue('customer'),
      productRepositoryProvider.overrideWithValue(catalogue ?? Catalogue()),
      orderRepositoryProvider.overrideWithValue(server),
      if (clock != null) paymentAwaitingClockProvider.overrideWithValue(clock.call),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Map<String, int> cart(ProviderContainer container) => {
  for (final line in container.read(cartProvider))
    line.product.id: line.quantity,
};

Future<Map<String, int>> savedCart() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(cartKey);
  return {
    if (raw != null)
      for (final line in jsonDecode(raw) as List)
        (line as Map)['product_id'] as String: line['quantity'] as int,
  };
}

Future<Map<String, dynamic>?> savedRecord() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(awaitingKey);
  return raw == null ? null : (jsonDecode(raw) as Map).cast<String, dynamic>();
}

String cartJson(Map<String, int> lines) => jsonEncode([
  for (final entry in lines.entries)
    {
      'product_id': entry.key,
      'variant_id': null,
      'size_label': null,
      'quantity': entry.value,
    },
]);

String awaitingJson({int? quantity, DateTime? createdAt}) => jsonEncode({
  'order_id': 'order-1',
  'owner_id': 'customer',
  'created_at': ?createdAt?.toIso8601String(),
  'lines': [
    {
      'product_id': 'bought',
      'variant_id': null,
      'size_label': null,
      'quantity': ?quantity,
    },
  ],
});

/// Pays for what is in the cart now; the server has not confirmed it yet.
PaymentAwaitingConfirmation pay(ProviderContainer container) {
  setPaymentAwaiting(
    container.read,
    PaymentAwaitingConfirmation(
      orderId: 'order-1',
      ownerId: 'customer',
      cartLines: List.of(container.read(cartProvider)),
    ),
  );
  return container.read(paymentAwaitingConfirmationProvider)!;
}

void main() {
  group('a confirmed payment takes only what it bought', () {
    test('pay for 1, add 2 more while confirming: 2 stay in the cart', () async {
      SharedPreferences.setMockInitialValues({});
      final server = Server(OrderStatus.pending);
      final container = containerFor(server);
      final notifier = container.read(cartProvider.notifier);
      await settle();
      notifier.add(product('bought'));
      notifier.add(product('other'));
      final record = pay(container);
      expect(record.purchasedLines.map((l) => l.quantity), [1, 1]);

      notifier.add(product('bought'), quantity: 2);
      expect(cart(container), {'bought': 3, 'other': 1});

      server.status = OrderStatus.paid;
      expect(settlePaymentAwaiting(container.read, record, server.order()), isTrue);
      await settle();

      expect(cart(container), {'bought': 2});
      expect(await savedCart(), {'bought': 2});
      expect(container.read(paymentAwaitingConfirmationProvider), isNull);
      expect(await savedRecord(), isNull);
    });

    test('an unchanged line is removed', () async {
      SharedPreferences.setMockInitialValues({});
      final server = Server(OrderStatus.pending);
      final container = containerFor(server);
      final notifier = container.read(cartProvider.notifier);
      await settle();
      notifier.add(product('bought'), quantity: 3);
      final record = pay(container);

      server.status = OrderStatus.paid;
      settlePaymentAwaiting(container.read, record, server.order());
      await settle();
      expect(cart(container), isEmpty);
      expect(await savedCart(), isEmpty);
    });

    test('a line reduced below what was bought is removed, never negative', () async {
      SharedPreferences.setMockInitialValues({});
      final container = containerFor(Server(OrderStatus.paid));
      final notifier = container.read(cartProvider.notifier);
      await settle();
      notifier.add(product('bought'), quantity: 1);
      notifier.removePurchased(const [
        PurchasedLine(productId: 'bought', quantity: 3),
      ]);
      expect(cart(container), isEmpty);
    });

    test('a purchase without a quantity takes the whole line', () async {
      SharedPreferences.setMockInitialValues({});
      final container = containerFor(Server(OrderStatus.paid));
      final notifier = container.read(cartProvider.notifier);
      await settle();
      notifier.add(product('bought'), quantity: 3);
      notifier.removePurchased(const [PurchasedLine(productId: 'bought')]);
      expect(cart(container), isEmpty);
    });

    test('the quantity is saved with the record and read back', () async {
      SharedPreferences.setMockInitialValues({});
      final container = containerFor(Server(OrderStatus.pending));
      final notifier = container.read(cartProvider.notifier);
      await settle();
      notifier.add(product('bought'), quantity: 2);
      pay(container);
      await settle();

      final lines = (await savedRecord())!['lines'] as List;
      expect((lines.single as Map)['quantity'], 2);
      final restored = await PaymentAwaitingStore.read('customer');
      expect(restored!.purchasedLines.single.quantity, 2);
    });
  });

  group('settled on the launch after the app was closed', () {
    Future<ProviderContainer> launch({Catalogue? catalogue}) async {
      final container = containerFor(
        Server(OrderStatus.paid),
        catalogue: catalogue,
      );
      container.listen(paymentAwaitingConfirmationProvider, (_, _) {});
      container.read(cartProvider);
      await settle();
      return container;
    }

    test('bought 1 of a saved line of 3: 2 are restored', () async {
      SharedPreferences.setMockInitialValues({
        cartKey: cartJson({'bought': 3, 'later': 1}),
        awaitingKey: awaitingJson(quantity: 1),
      });
      final container = await launch();
      expect(cart(container), {'bought': 2, 'later': 1});
      expect(await savedCart(), {'bought': 2, 'later': 1});
    });

    test('bought all of it: the line is not restored', () async {
      SharedPreferences.setMockInitialValues({
        cartKey: cartJson({'bought': 3, 'later': 1}),
        awaitingKey: awaitingJson(quantity: 3),
      });
      final container = await launch();
      expect(cart(container), {'later': 1});
      expect(await savedCart(), {'later': 1});
    });

    test('a record saved before quantities were kept removes the whole '
        'line', () async {
      SharedPreferences.setMockInitialValues({
        cartKey: cartJson({'bought': 3, 'later': 1}),
        awaitingKey: awaitingJson(),
      });
      final container = await launch();
      expect(cart(container), {'later': 1});
      expect(await savedCart(), {'later': 1});
    });

    test('lines that could not be checked yet lose what was bought too', () async {
      SharedPreferences.setMockInitialValues({
        cartKey: cartJson({'bought': 3, 'whole': 2, 'later': 1}),
      });
      // Offline at launch: every saved line stays unchecked, in storage.
      final container = containerFor(
        Server(OrderStatus.paid),
        catalogue: Catalogue()..offline = true,
      );
      container.read(cartProvider);
      await settle();
      expect(cart(container), isEmpty);

      container.read(cartProvider.notifier).removePurchased(const [
        PurchasedLine(productId: 'bought', quantity: 1),
        PurchasedLine(productId: 'whole'),
      ]);
      await settle();
      expect(await savedCart(), {'bought': 2, 'later': 1});
    });
  });

  group('a record the server never confirms', () {
    late Clock clock;
    late Server server;
    late ProviderContainer container;

    void start() {
      SharedPreferences.setMockInitialValues({});
      clock = Clock();
      server = Server(OrderStatus.pending);
      container = containerFor(server, clock: clock);
    }

    test('is stamped with the time the sheet succeeded, and saved with it', () async {
      start();
      final record = pay(container);
      await settle();
      expect(record.createdAt, clock.time);
      expect(record.withWindowElapsed().createdAt, clock.time);
      expect((await savedRecord())!['created_at'], '2026-11-22T10:00:00.000Z');
      final restored = await PaymentAwaitingStore.read('customer');
      expect(restored!.createdAt, clock.time);
    });

    test('still pending inside two hours: kept, as before', () async {
      start();
      final record = pay(container);
      await settle();
      for (final age in const [
        Duration(seconds: 30),
        Duration(minutes: 10),
        Duration(hours: 2),
      ]) {
        clock.time = record.createdAt!.add(age);
        expect(
          settlePaymentAwaiting(container.read, record, server.order()),
          isFalse,
          reason: '$age',
        );
        expect(container.read(paymentAwaitingConfirmationProvider), same(record));
      }
      await settle();
      expect(await savedRecord(), isNotNull);
      // The order page still shows "confirming" for it.
      expect(
        paymentAwaitingFor(record, server.order(), 'customer'),
        same(record),
      );
    });

    test('still pending after two hours: dropped from memory and the '
        'device, so the order is an ordinary pending one again', () async {
      start();
      final record = pay(container);
      await settle();
      clock.time = record.createdAt!.add(
        const Duration(hours: 2, seconds: 1),
      );
      expect(
        settlePaymentAwaiting(container.read, record, server.order()),
        isTrue,
      );
      await settle();
      final current = container.read(paymentAwaitingConfirmationProvider);
      expect(current, isNull);
      expect(await savedRecord(), isNull);
      expect(paymentAwaitingFor(current, server.order(), 'customer'), isNull);
    });

    test('an old record whose order was paid after all still clears the '
        'cart', () async {
      start();
      final notifier = container.read(cartProvider.notifier);
      await settle();
      notifier.add(product('bought'));
      final record = pay(container);
      clock.time = record.createdAt!.add(const Duration(hours: 5));
      server.status = OrderStatus.paid;
      expect(
        settlePaymentAwaiting(container.read, record, server.order()),
        isTrue,
      );
      expect(cart(container), isEmpty);
    });

    test('read on a later launch when older than two hours and still '
        'pending: dropped', () async {
      clock = Clock();
      SharedPreferences.setMockInitialValues({
        awaitingKey: awaitingJson(
          quantity: 1,
          createdAt: clock.time.subtract(const Duration(hours: 3)),
        ),
      });
      server = Server(OrderStatus.pending);
      container = containerFor(server, clock: clock);
      container.listen(paymentAwaitingConfirmationProvider, (_, _) {});
      await settle();
      expect(server.fetches, 1);
      expect(container.read(paymentAwaitingConfirmationProvider), isNull);
      expect(await savedRecord(), isNull);
    });

    test('read on a later launch when younger: kept as "still '
        'confirming"', () async {
      clock = Clock();
      SharedPreferences.setMockInitialValues({
        awaitingKey: awaitingJson(
          quantity: 1,
          createdAt: clock.time.subtract(const Duration(minutes: 90)),
        ),
      });
      server = Server(OrderStatus.pending);
      container = containerFor(server, clock: clock);
      container.listen(paymentAwaitingConfirmationProvider, (_, _) {});
      await settle();
      final record = container.read(paymentAwaitingConfirmationProvider);
      expect(record?.orderId, 'order-1');
      expect(record?.windowElapsed, isTrue);
      expect(await savedRecord(), isNotNull);
    });

    test('a record saved before times were kept counts from its first '
        'read, and is saved again with that time', () async {
      clock = Clock();
      SharedPreferences.setMockInitialValues({awaitingKey: awaitingJson()});
      server = Server(OrderStatus.pending);
      container = containerFor(server, clock: clock);
      container.listen(paymentAwaitingConfirmationProvider, (_, _) {});
      await settle();

      final record = container.read(paymentAwaitingConfirmationProvider)!;
      expect(record.createdAt, clock.time);
      final saved = (await savedRecord())!;
      expect(saved['created_at'], '2026-11-22T10:00:00.000Z');
      // Still "the whole line": no quantity was invented for it.
      expect(((saved['lines'] as List).single as Map).containsKey('quantity'), isFalse);

      // Two hours from that first read, not from some unknown earlier time.
      clock.time = clock.time.add(const Duration(hours: 1, minutes: 59));
      expect(
        settlePaymentAwaiting(container.read, record, server.order()),
        isFalse,
      );
      clock.time = clock.time.add(const Duration(minutes: 2));
      expect(
        settlePaymentAwaiting(container.read, record, server.order()),
        isTrue,
      );
      await settle();
      expect(await savedRecord(), isNull);
    });
  });
}
