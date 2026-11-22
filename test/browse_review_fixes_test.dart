// Page review 22 Nov 2026, browsing: the cart total note, the product page's
// way to the cart and way out, the empty Koi/Arowana chips, and the review
// row and growth-stage card layouts at 360 dp.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/cart/presentation/cart_screen.dart';
import 'package:marugen_app/features/knowledge/presentation/knowledge_providers.dart';
import 'package:marugen_app/features/knowledge/presentation/knowledge_screen.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/features/reviews/presentation/review_providers.dart';
import 'package:marugen_app/features/reviews/presentation/reviews_section.dart';
import 'package:marugen_app/features/shop/presentation/product_detail_screen.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/features/shop/presentation/shop_screen.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_providers.dart';
import 'package:marugen_app/shared/models/knowledge.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/models/review.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:marugen_app/shared/widgets/cart_badge_button.dart';

const food = Product(
  id: 'food',
  name: 'Koi Food',
  category: ProductCategory.fishFood,
  price: 12,
  stockQuantity: 10,
);
const koi = Product(
  id: 'koi',
  name: 'Kohaku',
  category: ProductCategory.koi,
  price: 300,
  stockQuantity: 1,
);

class _Cart extends CartNotifier {
  _Cart(this.items);
  final List<CartItem> items;

  @override
  List<CartItem> build() => items;

  @override
  Future<CartRefreshResult> refreshFromServer() async =>
      CartRefreshResult(removed: 0, adjusted: 0, isEmpty: items.isEmpty);
}

class _EmptyWishlist extends WishlistIdsNotifier {
  @override
  AsyncValue<Set<String>> build() => const AsyncData({});
}

void phone(WidgetTester tester, {double width = 360, double height = 800}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget scaled(double textScale, Widget child) => MediaQuery(
  data: MediaQueryData(
    size: const Size(360, 800),
    textScaler: TextScaler.linear(textScale),
  ),
  child: child,
);

void main() {
  group('cart total note', () {
    const inclusive = {'gst_percent': 9, 'gst_included_in_price': true};
    const exclusive = {'gst_percent': 9, 'gst_included_in_price': false};

    test('inclusive GST with a fish in the cart', () {
      expect(
        cartTotalNote(settings: inclusive, hasLiveFish: true),
        'Prices include GST. Free delivery by Marugen.',
      );
    });

    test('inclusive GST without a fish', () {
      expect(
        cartTotalNote(settings: inclusive, hasLiveFish: false),
        'Prices include GST. Delivery is calculated at checkout.',
      );
    });

    test('exclusive GST', () {
      expect(
        cartTotalNote(settings: exclusive, hasLiveFish: false),
        'GST and delivery are added at checkout.',
      );
      // A fish is still delivered free: never "delivery is added".
      expect(
        cartTotalNote(settings: exclusive, hasLiveFish: true),
        'GST is added at checkout. Free delivery by Marugen.',
      );
    });

    test('says nothing about GST it does not know or that is zero', () {
      for (final settings in [
        null,
        <String, dynamic>{},
        {'gst_percent': 0, 'gst_included_in_price': false},
      ]) {
        expect(
          cartTotalNote(settings: settings, hasLiveFish: false),
          'Delivery is calculated at checkout.',
        );
        expect(
          cartTotalNote(settings: settings, hasLiveFish: true),
          'Free delivery by Marugen.',
        );
      }
    });

    testWidgets('the cart shows the note for its settings and contents', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue(null),
            cartProvider.overrideWith(
              () => _Cart(const [CartItem(product: koi, quantity: 1)]),
            ),
            shopSettingsProvider.overrideWith((ref) async => inclusive),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const CartScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Prices include GST. Free delivery by Marugen.'),
        findsOneWidget,
      );
      expect(find.text('Delivery and GST are added at checkout.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('product page', () {
    Future<GoRouter> show(
      WidgetTester tester,
      Future<Product?> Function() load, {
      List<CartItem> cart = const [],
      bool pushed = true,
    }) async {
      phone(tester, height: 1200);
      final router = GoRouter(
        initialLocation: pushed ? '/' : '/product/food',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('SHOP')),
          ),
          GoRoute(
            path: '/cart',
            builder: (_, _) => const Scaffold(body: Text('CART PAGE')),
          ),
          GoRoute(
            path: '/product/:id',
            builder: (_, state) =>
                ProductDetailScreen(productId: state.pathParameters['id']!),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isLoggedInProvider.overrideWithValue(false),
            currentUserIdProvider.overrideWithValue(null),
            cartProvider.overrideWith(() => _Cart(cart)),
            wishlistProductIdsProvider.overrideWith(_EmptyWishlist.new),
            shopSettingsProvider.overrideWith((ref) async => {}),
            productDetailProvider('food').overrideWith((ref) => load()),
            relatedProductsProvider((
              id: 'food',
              category: ProductCategory.fishFood,
            )).overrideWith((ref) async => []),
            productReviewsProvider('food').overrideWith((ref) async => []),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      if (pushed) {
        router.push('/product/food');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
      return router;
    }

    testWidgets('the app bar has the cart button with its count, and it '
        'opens the cart', (tester) async {
      await show(
        tester,
        () async => food,
        cart: const [CartItem(product: food, quantity: 3)],
      );
      await tester.pumpAndSettle();

      final button = find.descendant(
        of: find.byType(SliverAppBar),
        matching: find.byType(CartBadgeButton),
      );
      expect(button, findsOneWidget);
      expect(
        find.descendant(of: button, matching: find.byTooltip('Open cart')),
        findsOneWidget,
      );
      expect(find.descendant(of: button, matching: find.text('3')), findsOneWidget);

      await tester.tap(find.byTooltip('Open cart'));
      await tester.pumpAndSettle();
      expect(find.text('CART PAGE'), findsOneWidget);
    });

    testWidgets('the add-to-cart confirmation stays for 4 seconds', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showCartSnackBar(context, CartAddResult.added),
                child: const Text('add'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('add'));
      await tester.pump();
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 4),
      );
      await tester.pump(const Duration(milliseconds: 3500));
      expect(find.text('Added to cart'), findsOneWidget);
      expect(find.text('View Cart'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Added to cart'), findsNothing);
    });

    testWidgets('loading has an app bar with a working back', (tester) async {
      // Never completes: the page stays in its loading state.
      await show(tester, () => Future<Product?>.delayed(const Duration(days: 1)));
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('SHOP'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(days: 2));
    });

    testWidgets('an error has an app bar, Retry and Back to Shop', (
      tester,
    ) async {
      await show(tester, () async => throw Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Back to Shop'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Back to Shop')).dy,
        greaterThan(tester.getTopLeft(find.text('Retry')).dy),
      );
      await tester.tap(find.text('Back to Shop'));
      await tester.pumpAndSettle();
      expect(find.text('SHOP'), findsOneWidget);
    });

    testWidgets('an error reached from a shared link still leads to the Shop', (
      tester,
    ) async {
      await show(tester, () async => throw Exception('offline'), pushed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('SHOP'), findsOneWidget);
    });

    testWidgets('not found has an app bar with back', (tester) async {
      await show(tester, () async => null);
      await tester.pumpAndSettle();
      expect(find.text('Product not found'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
    });
  });

  group('shop with an empty category', () {
    Future<ProviderContainer> show(
      WidgetTester tester,
      List<Product> Function() catalogue, {
      void Function()? onLoad,
    }) async {
      phone(tester);
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const ShopScreen())],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productListProvider.overrideWith((ref) async {
              ref.watch(selectedCategoryProvider);
              onLoad?.call();
              final category = ref.read(selectedCategoryProvider);
              return [
                for (final p in catalogue())
                  if (category == null || p.category == category) p,
              ];
            }),
            currentUserIdProvider.overrideWith((ref) => null),
            isLoggedInProvider.overrideWith((ref) => false),
            cartProvider.overrideWith(() => _Cart(const [])),
            wishlistProductIdsProvider.overrideWith(_EmptyWishlist.new),
            shopSettingsProvider.overrideWith(
              (ref) async => {'shop_phone': '+65 9123 4567'},
            ),
            unreadNotificationCountProvider.overrideWith((ref) => 0),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(ShopScreen)));
    }

    testWidgets('Koi with no fish says so and offers the farm', (tester) async {
      final container = await show(tester, () => const [food]);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Koi'));
      await tester.pumpAndSettle();

      expect(find.text('No koi available right now'), findsOneWidget);
      expect(
        find.text(
          'New fish are listed as soon as they are ready. Message us to ask '
          'what is in the ponds.',
        ),
        findsOneWidget,
      );
      expect(find.text('No matching products'), findsNothing);
      expect(find.text('Ask the farm'), findsOneWidget);
      expect(find.text('See all products'), findsOneWidget);
      expect(emptyCategoryEnquiry(ProductCategory.koi), 'Hi, do you have any koi available?');

      await tester.tap(find.text('See all products'));
      await tester.pumpAndSettle();
      expect(container.read(selectedCategoryProvider), isNull);
      expect(find.text('Koi Food'), findsOneWidget);
    });

    testWidgets('Arowana names the fish, and Ask the farm opens the contact '
        'picker', (tester) async {
      await show(tester, () => const [food]);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Arowana'));
      await tester.pumpAndSettle();
      expect(find.text('No arowana available right now'), findsOneWidget);

      await tester.tap(find.text('Ask the farm'));
      await tester.pumpAndSettle();
      expect(find.text('Contact Support'), findsOneWidget);
      expect(find.text('WhatsApp'), findsWidgets);
    });

    test('other categories get a sensible generic', () {
      expect(
        emptyCategoryTitle(ProductCategory.fishFood),
        'No fish food available right now',
      );
      expect(
        emptyCategoryTitle(ProductCategory.accessories),
        'No accessories available right now',
      );
      expect(
        emptyCategorySubtitle(ProductCategory.accessories),
        isNot(contains('ponds')),
      );
    });

    testWidgets('a text search with no hits keeps its own copy, also inside '
        'a category', (tester) async {
      await show(tester, () => const [food, koi]);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No matching products'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Koi'));
      await tester.pumpAndSettle();
      expect(find.text('No matching products'), findsOneWidget);
      expect(find.text('No koi available right now'), findsNothing);
    });

    testWidgets('the empty state can be pulled down to refresh, and shows '
        'what was listed meanwhile', (tester) async {
      var loads = 0;
      var listed = <Product>[food];
      await show(tester, () => listed, onLoad: () => loads++);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Koi'));
      await tester.pumpAndSettle();
      expect(find.text('No koi available right now'), findsOneWidget);
      final before = loads;

      listed = [food, koi];
      await tester.fling(
        find.text('No koi available right now'),
        const Offset(0, 400),
        1200,
      );
      await tester.pumpAndSettle();
      expect(loads, before + 1);
      expect(find.text('No koi available right now'), findsNothing);
      expect(find.text('Kohaku'), findsOneWidget);
    });
  });

  group('layouts at 360 dp', () {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('review row does not overflow at ${scale}x', (tester) async {
        phone(tester, height: 1600);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              isLoggedInProvider.overrideWithValue(false),
              currentUserIdProvider.overrideWithValue(null),
              productReviewsProvider('food').overrideWith(
                (ref) async => [
                  ProductReview(
                    id: 'r1',
                    productId: 'food',
                    userId: 'u1',
                    rating: 5,
                    comment: 'Healthy fish, well packed.',
                    createdAt: DateTime(2026, 11, 14),
                    authorName: 'Alexander Christopher Tan',
                  ),
                ],
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const Scaffold(
                body: SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: ReviewsSection(productId: 'food'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Verified Purchase'), findsOneWidget);
        // The date has its own line under the stars.
        final date = find.text('Nov 14, 2026');
        expect(date, findsOneWidget);
        expect(
          tester.getTopLeft(date).dy,
          greaterThan(tester.getTopLeft(find.text('Verified Purchase')).dy),
        );
      });

      testWidgets('growth-stage cards do not clip at ${scale}x', (
        tester,
      ) async {
        phone(tester, height: 1400);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              varietiesProvider(null).overrideWith(
                (ref) async => const [
                  Variety(
                    id: '1',
                    name: 'Kohaku',
                    category: 'koi',
                    description: 'White with red markings.',
                    stages: [
                      VarietyStage(
                        label: 'Tosai',
                        description: 'Under one year old, colour developing',
                      ),
                      VarietyStage(
                        label: 'Nisai',
                        description: 'Two years, pattern settles and deepens',
                      ),
                    ],
                  ),
                ],
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const KnowledgeScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kohaku'));
        await tester.pumpAndSettle();
        expect(find.text('GROWTH STAGES'), findsOneWidget);
        expect(find.text('Tosai'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
