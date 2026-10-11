import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/orders/presentation/purchase_intent.dart';
import 'package:marugen_app/features/shop/presentation/shop_screen.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/shared/widgets/product_grid.dart';
import 'package:marugen_app/shared/widgets/skeleton.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/widgets/product_card.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_providers.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [360.0, 390.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
          'two products share a row on $platform at $width / $scale',
          (tester) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final product = Product.fromMap({
              'id': 'p',
              'name': 'Marugen Special Mix High Growth Food',
              'category': 'fish_food',
              'price': 118.80,
              'stock_quantity': 10,
              'avg_rating': 4.8,
              'review_count': 999,
              'sold_count': 12345,
            });
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  isLoggedInProvider.overrideWithValue(false),
                  wishlistProductIdsProvider.overrideWith(_EmptyWishlist.new),
                  shopSettingsProvider.overrideWith((ref) async => {}),
                ],
                child: MaterialApp(
                  theme: ThemeData(platform: platform),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: ProductGrid(
                      itemCount: 4,
                      itemBuilder: (_, i) => ProductCard(product: product),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            final cards = find.byType(ProductCard);
            expect(
              tester.getTopLeft(cards.at(0)).dy,
              tester.getTopLeft(cards.at(1)).dy,
            );
            expect(
              tester.getTopLeft(cards.at(2)).dy,
              greaterThan(tester.getTopLeft(cards.at(0)).dy),
            );
            expect(
              tester
                  .getSize(find.byTooltip('Add ${product.name} to cart').first)
                  .width,
              greaterThanOrEqualTo(48),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('grid prices align for one and two line product names', (
    tester,
  ) async {
    final products = [
      Product.fromMap({
        'id': 'short',
        'name': 'Koi food',
        'category': 'fish_food',
        'price': 20,
        'stock_quantity': 10,
      }),
      Product.fromMap({
        'id': 'long',
        'name': 'Premium koi supplies and colour enhancing food',
        'category': 'fish_food',
        'price': 30,
        'stock_quantity': 10,
      }),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isLoggedInProvider.overrideWithValue(false),
          wishlistProductIdsProvider.overrideWith(_EmptyWishlist.new),
          shopSettingsProvider.overrideWith((ref) async => {}),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final product in products)
                  SizedBox(
                    width: 220,
                    height: 450,
                    child: ProductCard(product: product, onTap: () {}),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.getTopLeft(find.text(r'S$20.00')).dy,
      tester.getTopLeft(find.text(r'S$30.00')).dy,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('card offers named 48 pixel actions and two name lines', (
    tester,
  ) async {
    final product = Product.fromMap({
      'id': 'p',
      'name': 'A long meaningful product name for a fish keeper',
      'category': 'fish_food',
      'price': 20,
      'stock_quantity': 10,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isLoggedInProvider.overrideWith((ref) => false),
          wishlistProductIdsProvider.overrideWith(_EmptyWishlist.new),
          shopSettingsProvider.overrideWith((ref) async => {}),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 220,
              height: 450,
              child: ProductCard(product: product, onTap: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.widget<Text>(find.text(product.name)).maxLines, 2);
    expect(find.byTooltip('Add ${product.name} to cart'), findsOneWidget);
    expect(
      tester.getSize(find.byTooltip('Add ${product.name} to cart')).height,
      greaterThanOrEqualTo(48),
    );
    expect(find.byTooltip('Save ${product.name} to wishlist'), findsOneWidget);
  });
  for (final width in [320.0, 360.0, 390.0, 1024.0]) {
    testWidgets('long card names at double text scale fit width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final product = Product.fromMap({
        'id': 'p',
        'name': 'A very long meaningful name for premium fish supplies and food with several options',
        'category': 'fish_food',
        'price': 20,
        'stock_quantity': 10,
        'avg_rating': 4.8,
        'review_count': 999,
        'sold_count': 12345,
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isLoggedInProvider.overrideWith((ref) => false),
            wishlistProductIdsProvider.overrideWith(_EmptyWishlist.new),
            shopSettingsProvider.overrideWith(
              (ref) async => {'delivery_lead_days_min': 2},
            ),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: ProductGrid(
                itemCount: 4,
                itemBuilder: (_, i) =>
                    ProductCard(product: product, onTap: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(ProductCard).first).width,
        lessThanOrEqualTo(480),
      );
    });
  }
  testWidgets('reduced motion skeleton schedules no animation frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Skeleton(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('live fish buy now leaves existing cart isolated', (
    tester,
  ) async {
    final fish = Product.fromMap({
      'id': 'fish',
      'name': 'Chosen fish',
      'category': 'koi',
      'price': 100,
      'stock_quantity': 1,
    });
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith((ref) => 'account'),
        isLoggedInProvider.overrideWith((ref) => true),
        cartProvider.overrideWith(_ExistingCart.new),
        wishlistProductIdsProvider.overrideWith(_EmptyWishlist.new),
        shopSettingsProvider.overrideWith((ref) async => {}),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: SizedBox(
              width: 250,
              height: 500,
              child: ProductCard(product: fish),
            ),
          ),
        ),
        GoRoute(
          path: '/checkout',
          builder: (_, _) => const Scaffold(body: Text('Checkout')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    final before = List.of(container.read(cartProvider));
    await tester.tap(find.byTooltip('Buy Chosen fish now'));
    await tester.pumpAndSettle();
    expect(container.read(cartProvider), before);
    expect(
      container.read(purchaseIntentProvider)!.items.single.product.id,
      'fish',
    );
    expect(find.text('Checkout'), findsOneWidget);
  });
  testWidgets('no matches offers clear filters and restores search', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        productListProvider.overrideWith((ref) async => []),
        cartProvider.overrideWith(_ExistingCart.new),
        unreadNotificationCountProvider.overrideWith((ref) => 0),
      ],
    );
    addTearDown(container.dispose);
    container.read(searchQueryProvider.notifier).state = 'missing';
    container.read(selectedCategoryProvider.notifier).state =
        ProductCategory.koi;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ShopScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching products'), findsOneWidget);
    expect(find.byTooltip('Clear search'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(container.read(searchQueryProvider), '');
    expect(container.read(selectedCategoryProvider), isNull);
    expect(find.text('No products yet'), findsOneWidget);
  });
}

class _EmptyWishlist extends WishlistIdsNotifier {
  @override
  AsyncValue<Set<String>> build() => const AsyncData({});
}

class _ExistingCart extends CartNotifier {
  @override
  List<CartItem> build() => [
    const CartItem(
      product: Product(
        id: 'existing',
        name: 'Existing item',
        category: ProductCategory.accessories,
        price: 10,
        stockQuantity: 5,
      ),
    ),
  ];
}
