import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/orders/domain/shipping_quote.dart';
import 'package:marugen_app/features/reviews/presentation/review_providers.dart';
import 'package:marugen_app/features/shop/presentation/product_detail_screen.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_providers.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';

const _exactFish = 'You are buying this exact fish — photographed at our farm.';
const _freeTitle = 'Free hand delivery in Singapore';
const _freeBody =
    "Our team brings your fish to your door. We'll message you after "
    'payment to agree a time.';

const _koi = Product(
  id: 'p',
  name: 'Kohaku 45cm',
  category: ProductCategory.koi,
  price: 300,
  stockQuantity: 1,
);

const _batch = Product(
  id: 'p',
  name: 'Japan Imported Koi Selection',
  category: ProductCategory.koi,
  variants: [
    ProductVariant(
      id: 'a',
      productId: 'p',
      label: 'Fish A',
      price: 300,
      stockQuantity: 1,
    ),
    ProductVariant(
      id: 'b',
      productId: 'p',
      label: 'Fish B',
      price: 320,
      stockQuantity: 1,
    ),
  ],
);

const _food = Product(
  id: 'p',
  name: 'Growth Pellets',
  category: ProductCategory.fishFood,
  price: 20,
  stockQuantity: 5,
);

class _EmptyCart extends CartNotifier {
  @override
  List<CartItem> build() => const [];
}

class _EmptyWishlist extends WishlistIdsNotifier {
  @override
  AsyncValue<Set<String>> build() => const AsyncData({});
}

Future<void> _pump(
  WidgetTester tester,
  Product product, {
  Size size = const Size(390, 3000),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isLoggedInProvider.overrideWithValue(false),
        currentUserIdProvider.overrideWithValue(null),
        cartProvider.overrideWith(_EmptyCart.new),
        wishlistProductIdsProvider.overrideWith(_EmptyWishlist.new),
        shopSettingsProvider.overrideWith((_) async => {}),
        productDetailProvider('p').overrideWith((_) async => product),
        relatedProductsProvider((id: 'p', category: product.category))
            .overrideWith((_) async => []),
        productReviewsProvider('p').overrideWith((_) async => []),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const ProductDetailScreen(productId: 'p'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a single live fish promises free hand delivery and that it '
      'is the fish in the photos', (tester) async {
    await _pump(tester, _koi);
    expect(find.text(_freeTitle), findsOneWidget);
    expect(find.text(_freeBody), findsOneWidget);
    expect(find.textContaining('no courier tracking'), findsNothing);
    expect(find.text(_exactFish), findsOneWidget);
    // Directly under the product title.
    final title = tester.getRect(find.text('Kohaku 45cm').first);
    final line = tester.getRect(find.text(_exactFish));
    expect(line.top, greaterThanOrEqualTo(title.bottom));
    expect(line.top - title.bottom, lessThan(12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a batch listing keeps the delivery promise but does not '
      'claim one exact fish', (tester) async {
    await _pump(tester, _batch);
    expect(find.text(_freeTitle), findsOneWidget);
    expect(find.text(_exactFish), findsNothing);
  });

  testWidgets('courier goods keep their own delivery copy', (tester) async {
    await _pump(tester, _food);
    expect(find.text('Island-wide delivery in Singapore'), findsOneWidget);
    expect(find.textContaining('Shipped by courier'), findsOneWidget);
    expect(find.text(_freeTitle), findsNothing);
    expect(find.text(_exactFish), findsNothing);
  });

  testWidgets('courier goods show the estimated delivery window that used '
      'to sit on the shop card', (tester) async {
    await _pump(tester, _food);
    // Lead time defaults (2 to 5 days) apply when the shop has set none.
    final estimate = find.textContaining('Estimated delivery');
    expect(estimate, findsOneWidget);
    expect(
      tester.getRect(estimate).top,
      greaterThan(
        tester.getRect(find.text('Island-wide delivery in Singapore')).top,
      ),
    );
    expect(find.textContaining('not a guaranteed date'), findsOneWidget);
  });

  testWidgets('hand-delivered fish and sold-out goods show no delivery '
      'estimate', (tester) async {
    await _pump(tester, _koi);
    expect(find.textContaining('Estimated delivery'), findsNothing);
    await tester.pumpWidget(const SizedBox());

    await _pump(
      tester,
      const Product(
        id: 'p',
        name: 'Growth Pellets',
        category: ProductCategory.fishFood,
        price: 20,
        stockQuantity: 0,
      ),
    );
    expect(find.text('Island-wide delivery in Singapore'), findsOneWidget);
    expect(find.textContaining('Estimated delivery'), findsNothing);
  });

  testWidgets('the live-fish copy fits a small phone at double text size', (
    tester,
  ) async {
    await _pump(tester, _koi, size: const Size(320, 6000), textScale: 2);
    expect(find.text(_exactFish), findsOneWidget);
    expect(find.text(_freeTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // "Free" on the product page is only honest while the server charges the
  // buyer nothing for shop delivery; the app refuses any other quote.
  test('a shop-delivery quote that charges the buyer is rejected', () {
    Map<String, dynamic> quote(int buyer) => {
      'quote_id': 'q',
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 10))
          .toIso8601String(),
      'currency': 'SGD',
      'fulfillment_method': 'shop_delivery',
      'shipping_cost_policy': 'seller_100',
      'total_shipping_cents': buyer,
      'buyer_shipping_cents': buyer,
      'seller_shipping_cents': 0,
    };
    expect(ShippingQuote.fromMap(quote(0)).isShopDelivery, isTrue);
    expect(() => ShippingQuote.fromMap(quote(500)), throwsA(anything));
  });
}
