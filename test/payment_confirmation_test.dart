import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/orders/utils/payment_confirmation.dart';
import 'package:marugen_app/shared/models/order.dart';

Order paidOrder({String? userId = 'customer', String id = 'order-12345'}) =>
    Order(
      id: id,
      userId: userId,
      status: OrderStatus.paid,
      total: 20,
      createdAt: DateTime(2026, 10, 10),
    );

void main() {
  test(
    'transient confirmation failures recover without another payment',
    () async {
      var attempts = 0;
      final waits = <Duration>[];
      final paid = await confirmOrderPayment(
        orderId: 'order-12345',
        ownerId: 'customer',
        ownsCheckout: () => true,
        fetchOrder: (id) async {
          if (++attempts < 3) throw Exception('offline');
          return paidOrder();
        },
        delay: (duration) async => waits.add(duration),
      );
      expect(paid, isTrue);
      expect(attempts, 3);
      expect(waits, const [
        Duration(milliseconds: 600),
        Duration(milliseconds: 600),
      ]);
    },
  );
  test(
    'all failed confirmation reads return unconfirmed after ten attempts',
    () async {
      var attempts = 0;
      var waits = 0;
      final paid = await confirmOrderPayment(
        orderId: 'order-12345',
        ownerId: 'customer',
        ownsCheckout: () => true,
        fetchOrder: (id) async {
          attempts++;
          throw Exception('offline');
        },
        delay: (_) async {
          waits++;
        },
      );
      expect(paid, isFalse);
      expect(attempts, 10);
      expect(waits, 9);
    },
  );
  test(
    'owner change while awaiting a paid record prevents confirmation',
    () async {
      var ownerMatches = true;
      var attempts = 0;
      final fetched = Completer<Order?>();
      final pending = confirmOrderPayment(
        orderId: 'order-12345',
        ownerId: 'customer',
        ownsCheckout: () => ownerMatches,
        fetchOrder: (_) {
          attempts++;
          return fetched.future;
        },
        delay: (_) async {},
      );
      ownerMatches = false;
      fetched.complete(paidOrder());
      expect(await pending, isFalse);
      expect(attempts, 1);
    },
  );
  test('owner change during retry delay stops later order queries', () async {
    var ownerMatches = true;
    var attempts = 0;
    final paid = await confirmOrderPayment(
      orderId: 'order-12345',
      ownerId: 'customer',
      ownsCheckout: () => ownerMatches,
      fetchOrder: (_) async {
        attempts++;
        return null;
      },
      delay: (_) async {
        ownerMatches = false;
      },
    );
    expect(paid, isFalse);
    expect(attempts, 1);
  });
  for (final wrongOrder in [
    paidOrder(userId: 'other'),
    paidOrder(id: 'other-order'),
  ]) {
    test(
      'another account or order cannot confirm this checkout ${wrongOrder.id}/${wrongOrder.userId}',
      () async {
        expect(
          await confirmOrderPayment(
            orderId: 'order-12345',
            ownerId: 'customer',
            ownsCheckout: () => true,
            fetchOrder: (_) async => wrongOrder,
            delay: (_) async {},
          ),
          isFalse,
        );
      },
    );
  }
  test('signed-out checkout cannot query or confirm an order', () async {
    expect(
      await confirmOrderPayment(
        orderId: 'order-12345',
        ownerId: null,
        ownsCheckout: () => true,
        fetchOrder: (_) async => throw StateError('must not query'),
        delay: (_) async {},
      ),
      isFalse,
    );
  });
  test('completed attempt never starts another native payment flow', () async {
    var nativeFlows = 0;
    await presentPendingPayment(
      intent: {
        'orderId': 'order-12345',
        'paymentStatus': 'paid',
        'status': 'shipped',
        'clientSecret': null,
      },
      ownsCheckout: () => true,
      presentPayment: (_) async {
        nativeFlows++;
      },
    );
    expect(nativeFlows, 0);
  });
  test('pending payment presents its original secret once', () async {
    final presented = <String>[];
    await presentPendingPayment(
      intent: {'orderId': 'order-12345', 'clientSecret': 'original-secret'},
      ownsCheckout: () => true,
      presentPayment: (secret) async => presented.add(secret),
    );
    expect(presented, ['original-secret']);
  });
  test('owner change prevents native payment initialization', () async {
    await presentPendingPayment(
      intent: {'orderId': 'order-12345', 'clientSecret': 'original-secret'},
      ownsCheckout: () => false,
      presentPayment: (_) async => throw StateError('must not present'),
    );
  });
}
