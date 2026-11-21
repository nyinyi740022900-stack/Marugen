import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/orders/presentation/order_detail_screen.dart';
import 'package:marugen_app/features/shop/data/product_repository.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:shared_preferences/shared_preferences.dart';

final net = Product.fromMap({
  'id': 'net',
  'name': 'Net',
  'category': 'accessories',
  'price': 12,
  'stock_quantity': 9,
});

Product pellets({List<String> weights = const ['1kg', '5kg']}) =>
    Product.fromMap({
      'id': 'pellets',
      'name': 'Pellets',
      'category': 'fish_food',
      'price': 10,
      'stock_quantity': 0,
      'variants': [
        for (final weight in weights)
          {
            'id': 'pellets-$weight',
            'product_id': 'pellets',
            'label': weight,
            'price': weight == '5kg' ? 45 : 10,
            'stock_quantity': 6,
          },
      ],
    });

class Catalogue implements ProductRepository {
  Catalogue(this.products);
  final List<Product> products;
  String? offlineFor;

  @override
  Future<Product?> fetchProductById(String id) async {
    if (id == offlineFor) throw const SocketException('offline');
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Order orderOf(List<OrderItem> items) => Order(
  id: 'order-12345678',
  userId: 'buyer',
  status: OrderStatus.delivered,
  total: 100,
  createdAt: DateTime.utc(2026, 11, 1),
  items: items,
);

const netLine = OrderItem(
  productId: 'net',
  productName: 'Net',
  quantity: 2,
  unitPrice: 12,
);
const fiveKiloLine = OrderItem(
  productId: 'pellets',
  productName: 'Pellets',
  quantity: 1,
  unitPrice: 45,
  variantLabel: '5kg',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> showReorder(
    WidgetTester tester,
    Catalogue catalogue,
    Order order,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: ReorderButton(order: order)),
        ),
        GoRoute(
          path: '/cart',
          builder: (_, _) => const Scaffold(body: Text('Cart screen')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('buyer'),
          productRepositoryProvider.overrideWithValue(catalogue),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(ReorderButton)),
    );
  }

  test('the result says how many were added and how many were not', () {
    expect(reorderResultMessage(added: 2, skipped: 0), '2 items added.');
    expect(
      reorderResultMessage(added: 2, skipped: 1),
      '2 items added. 1 is no longer available.',
    );
    expect(
      reorderResultMessage(added: 1, skipped: 2),
      '1 item added. 2 are no longer available.',
    );
    expect(
      reorderResultMessage(added: 0, skipped: 1),
      'This item is no longer available.',
    );
    expect(
      reorderResultMessage(added: 0, skipped: 3),
      'These items are no longer available.',
    );
  });

  testWidgets('a dropped connection ends the spinner, says so, and leaves '
      'the cart alone', (tester) async {
    final catalogue = Catalogue([net, pellets()])..offlineFor = 'pellets';
    final container = await showReorder(
      tester,
      catalogue,
      orderOf(const [netLine, fiveKiloLine]),
    );
    await tester.tap(find.text('Reorder'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('Network problem — check your connection and try again.'),
      findsOneWidget,
    );
    // Not even the line that had already been looked up.
    expect(container.read(cartProvider), isEmpty);
    expect(find.text('Cart screen'), findsNothing);

    // The button works again once the connection is back.
    catalogue.offlineFor = null;
    await tester.tap(find.text('Reorder'));
    await tester.pumpAndSettle();
    expect(container.read(cartProvider), hasLength(2));
  });

  testWidgets('an option that no longer exists is skipped, not swapped for '
      'the base product', (tester) async {
    final container = await showReorder(
      tester,
      Catalogue([
        net,
        pellets(weights: const ['1kg']),
      ]),
      orderOf(const [netLine, fiveKiloLine]),
    );
    await tester.tap(find.text('Reorder'));
    await tester.pumpAndSettle();
    expect(
      find.text('1 item added. 1 is no longer available.'),
      findsOneWidget,
    );
    final cart = container.read(cartProvider);
    expect(cart.single.product.id, 'net');
    expect(cart.single.quantity, 2);
    expect(find.text('Cart screen'), findsOneWidget);
  });

  testWidgets('the same option is put back at its own price', (tester) async {
    final container = await showReorder(
      tester,
      Catalogue([net, pellets()]),
      orderOf(const [netLine, fiveKiloLine]),
    );
    await tester.tap(find.text('Reorder'));
    await tester.pumpAndSettle();
    expect(find.text('2 items added.'), findsOneWidget);
    final line = container
        .read(cartProvider)
        .firstWhere((i) => i.product.id == 'pellets');
    expect(line.selectedVariant?.label, '5kg');
    expect(line.unitPrice, 45);
  });

  testWidgets('nothing available stays on the order and says so', (
    tester,
  ) async {
    final container = await showReorder(
      tester,
      Catalogue([]),
      orderOf(const [netLine]),
    );
    await tester.tap(find.text('Reorder'));
    await tester.pumpAndSettle();
    expect(find.text('This item is no longer available.'), findsOneWidget);
    expect(container.read(cartProvider), isEmpty);
    expect(find.text('Cart screen'), findsNothing);
  });
}
