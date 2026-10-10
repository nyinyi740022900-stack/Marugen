import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/cart/presentation/cart_screen.dart';
import 'package:marugen_app/features/reviews/presentation/review_providers.dart';
import 'package:marugen_app/features/shop/presentation/product_detail_screen.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/features/wishlist/data/wishlist_repository.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_providers.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_screen.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/models/wishlist_item.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const food = Product(
  id: 'food',
  name: 'Koi food',
  category: ProductCategory.fishFood,
  price: 10,
  stockQuantity: 5,
  description: 'Food selection details.',
);
const fish = Product(
  id: 'fish',
  name: 'Selected koi',
  category: ProductCategory.koi,
  price: 200,
  stockQuantity: 1,
);

class FixedWishlist extends WishlistIdsNotifier {
  @override
  AsyncValue<Set<String>> build() => const AsyncData({});
}

class ReviewCart extends CartNotifier {
  int restores = 0;
  @override
  List<CartItem> build() => [
    const CartItem(product: food),
    const CartItem(product: fish),
  ];
  @override
  Future<CartRefreshResult> refreshFromServer() async =>
      const CartRefreshResult(removed: 0, adjusted: 0, isEmpty: false);
  @override
  bool restoreRemoved(CartItem item, {required String? ownerId}) {
    restores++;
    state = [...state, item];
    return true;
  }
}

class RetryingWishlist implements WishlistRepository {
  int loads = 0;
  int removals = 0;
  @override
  Future<Set<String>> fetchMyWishlistProductIds() async {
    if (++loads == 1) throw StateError('Temporary failure');
    return {'food'};
  }

  @override
  Future<void> remove(String productId) async {
    removals++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Cart Undo expires when leaving cart for checkout', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue('customer'),
        cartProvider.overrideWith(ReviewCart.new),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/cart',
      routes: [
        GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
        GoRoute(
          path: '/checkout',
          builder: (_, _) => const Scaffold(body: Text('Checkout preview')),
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
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove from cart'));
    await tester.pumpAndSettle();
    final undo = tester
        .widget<SnackBar>(find.byType(SnackBar))
        .action!
        .onPressed;
    await tester.tap(find.text('Proceed to Checkout'));
    await tester.pumpAndSettle();
    expect(find.text('Checkout preview'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    undo();
    expect((container.read(cartProvider.notifier) as ReviewCart).restores, 0);
    expect(container.read(cartProvider).length, 1);
  });

  testWidgets(
    'Reduced-motion product tabs jump without a zero-duration animation',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isLoggedInProvider.overrideWithValue(false),
            wishlistProductIdsProvider.overrideWith(FixedWishlist.new),
            productDetailProvider.overrideWith((ref, id) async => food),
            productReviewsProvider.overrideWith((ref, id) async => []),
            relatedProductsProvider.overrideWith((ref, key) async => []),
            shopSettingsProvider.overrideWith((ref) async => {}),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const ProductDetailScreen(productId: 'food'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reviews'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Wishlist removal recovers after its IDs request fails', (
    tester,
  ) async {
    final repository = RetryingWishlist();
    final item = WishlistItem(
      id: 'saved',
      userId: 'customer',
      productId: food.id,
      createdAt: DateTime(2026),
      product: food,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => const Stream.empty()),
          currentUserIdProvider.overrideWithValue('customer'),
          myWishlistProvider.overrideWith((ref) async => [item]),
          wishlistRepositoryProvider.overrideWithValue(repository),
          shopSettingsProvider.overrideWith((ref) async => {}),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const WishlistScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Koi food from wishlist'));
    await tester.pumpAndSettle();
    expect(repository.loads, 2);
    expect(repository.removals, 0);
    await tester.tap(find.byTooltip('Remove Koi food from wishlist'));
    await tester.pumpAndSettle();
    expect(repository.removals, 1);
    expect(find.text('Your wishlist is empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
