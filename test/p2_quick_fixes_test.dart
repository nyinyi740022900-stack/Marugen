import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/reviews/presentation/review_providers.dart';
import 'package:marugen_app/features/shop/presentation/product_detail_screen.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_providers.dart';
import 'package:marugen_app/main.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:marugen_app/shared/utils/contact_launcher.dart';
import 'package:marugen_app/shared/utils/error_message.dart';
import 'package:marugen_app/shared/widgets/product_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const koi = Product(
  id: 'koi',
  name: 'Kohaku',
  category: ProductCategory.koi,
  price: 300,
  stockQuantity: 1,
  imageUrls: [
    'https://example.com/1.jpg',
    'https://example.com/2.jpg',
    'https://example.com/3.jpg',
  ],
);

class _EmptyCart extends CartNotifier {
  @override
  List<CartItem> build() => const [];
}

class _EmptyWishlist extends WishlistIdsNotifier {
  @override
  AsyncValue<Set<String>> build() => const AsyncData({});
}

List<Override> guestOverrides() => [
  currentUserIdProvider.overrideWith((ref) => null),
  isLoggedInProvider.overrideWith((ref) => false),
  cartProvider.overrideWith(_EmptyCart.new),
  wishlistProductIdsProvider.overrideWith(_EmptyWishlist.new),
  shopSettingsProvider.overrideWith((ref) async => {}),
];

void main() {
  testWidgets('the product photos show which one of how many is on screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...guestOverrides(),
          productDetailProvider('koi').overrideWith((ref) async => koi),
          relatedProductsProvider((id: 'koi', category: ProductCategory.koi))
              .overrideWith((ref) async => []),
          productReviewsProvider('koi').overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ProductDetailScreen(productId: 'koi'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Photo 1 of 3'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('a guest saving a fish logs in and comes back to that fish, and '
      'the buy button no longer looks like add-to-cart', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: SizedBox(
              width: 250,
              height: 500,
              child: ProductCard(product: koi),
            ),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (_, state) => Text('Login ${state.uri}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: guestOverrides(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byTooltip('Buy Kohaku now'),
        matching: find.byIcon(Icons.bolt),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Save Kohaku to wishlist'));
    await tester.pumpAndSettle();
    expect(find.text('Login /login?redirect=%2Fproduct%2Fkoi'), findsOneWidget);
  });

  testWidgets('contacting the shop offers WhatsApp or a phone call', (
    tester,
  ) async {
    expect(internationalDigits('9123 4567'), '6591234567');
    expect(internationalDigits('+65 6222-3333'), '6562223333');
    expect(internationalDigits('+60 12 345 6789'), '60123456789');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => contactShop(context, '6222 3333'),
              child: const Text('Contact shop'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Contact shop'));
    await tester.pumpAndSettle();
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('+6562223333'), findsOneWidget);
  });

  test('auth errors explain themselves; only a rejected token is an expired '
      'session', () {
    expect(
      friendlyErrorMessage(
        const AuthException(
          'Password should be at least 8 characters.',
          statusCode: '422',
          code: 'weak_password',
        ),
      ),
      'Password should be at least 8 characters.',
    );
    expect(
      friendlyErrorMessage(
        const AuthException('JWT expired', statusCode: '401'),
      ),
      'Your session expired. Please log in again.',
    );
  });

  testWidgets('phones are held in portrait, tablets still rotate', (
    tester,
  ) async {
    final requested = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          requested.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    OrientationPolicy.apply(Size.zero);
    OrientationPolicy.apply(const Size(390, 844));
    OrientationPolicy.apply(const Size(844, 390));
    OrientationPolicy.apply(const Size(820, 1180));
    expect(requested, [
      ['DeviceOrientation.portraitUp'],
      <String>[],
    ]);
  });
}
