import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/reviews/presentation/review_providers.dart';
import 'package:marugen_app/features/shop/presentation/gallery_video_slide.dart';
import 'package:marugen_app/features/shop/presentation/product_detail_screen.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_providers.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:marugen_app/shared/widgets/product_video_player.dart';

const video = 'https://example.com/kohaku.mp4';
const photos = [
  'https://example.com/1.jpg',
  'https://example.com/2.jpg',
  'https://example.com/3.jpg',
];

const koi = Product(
  id: 'p',
  name: 'Kohaku',
  category: ProductCategory.koi,
  price: 300,
  stockQuantity: 1,
  imageUrls: photos,
  videoUrl: video,
);

const food = Product(
  id: 'p',
  name: 'Pellets',
  category: ProductCategory.fishFood,
  price: 30,
  stockQuantity: 5,
  imageUrls: photos,
  videoUrl: video,
);

class _EmptyCart extends CartNotifier {
  @override
  List<CartItem> build() => const [];
}

class _EmptyWishlist extends WishlistIdsNotifier {
  @override
  AsyncValue<Set<String>> build() => const AsyncData({});
}

void main() {
  Future<void> show(
    WidgetTester tester,
    Product product, {
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWith((ref) => null),
          isLoggedInProvider.overrideWith((ref) => false),
          cartProvider.overrideWith(_EmptyCart.new),
          wishlistProductIdsProvider.overrideWith(_EmptyWishlist.new),
          shopSettingsProvider.overrideWith((ref) async => {}),
          productDetailProvider('p').overrideWith((ref) async => product),
          relatedProductsProvider((
            id: 'p',
            category: product.category,
          )).overrideWith((ref) async => []),
          productReviewsProvider('p').overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
          home: const ProductDetailScreen(productId: 'p'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> swipe(WidgetTester tester, {bool back = false}) async {
    await tester.fling(
      find.byType(PageView),
      Offset(back ? 150 : -150, 0),
      1500,
    );
    await tester.pumpAndSettle();
  }

  ProductVideoPlayer player(WidgetTester tester) =>
      tester.widget<ProductVideoPlayer>(find.byType(ProductVideoPlayer));

  testWidgets('a live fish video is the second gallery slide, counted by the '
      'page badge, and no longer sits below the delivery card', (tester) async {
    await show(tester, koi);

    // Three photos and the video.
    expect(find.text('1 / 4'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Photo, slide 1 of 4. Slide 2 is a video'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
    expect(find.text('VIDEO', skipOffstage: false), findsNothing);

    await swipe(tester);
    expect(find.text('2 / 4'), findsOneWidget);
    expect(find.bySemanticsLabel('Video, slide 2 of 4'), findsOneWidget);
    expect(find.byIcon(Icons.videocam), findsOneWidget);
    expect(find.text('Play video'), findsOneWidget);
    expect(find.bySemanticsLabel('Play video of Kohaku'), findsOneWidget);

    await swipe(tester);
    expect(find.text('3 / 4'), findsOneWidget);
    expect(find.text('Play video'), findsNothing);
  });

  testWidgets('nothing plays until the shopper taps the poster', (
    tester,
  ) async {
    await show(tester, koi);
    expect(find.byType(ProductVideoPlayer, skipOffstage: false), findsNothing);
    await swipe(tester);
    // On the video slide, still only a poster: no player, so no playback.
    expect(find.byType(ProductVideoPlayer, skipOffstage: false), findsNothing);

    await tester.tap(find.text('Play video'));
    await tester.pumpAndSettle();
    expect(find.text('Play video'), findsNothing);
    expect(player(tester).videoUrl, video);
    expect(player(tester).autoPlay, isTrue);
    expect(player(tester).active, isTrue);
  });

  testWidgets('swiping away pauses it, and coming back does not start it '
      'again by itself', (tester) async {
    await show(tester, koi);
    await swipe(tester);
    await tester.tap(find.text('Play video'));
    await tester.pumpAndSettle();
    expect(player(tester).active, isTrue);

    // Mid-swipe, as soon as the next photo is the current page.
    final drag = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    await drag.moveBy(const Offset(-30, 0));
    await drag.moveBy(const Offset(-230, 0));
    await tester.pump();
    expect(find.text('3 / 4'), findsOneWidget);
    expect(player(tester).active, isFalse);
    await drag.up();
    await tester.pumpAndSettle();
    for (final shown in tester.widgetList<ProductVideoPlayer>(
      find.byType(ProductVideoPlayer, skipOffstage: false),
    )) {
      expect(shown.active, isFalse);
    }

    await swipe(tester, back: true);
    expect(find.text('2 / 4'), findsOneWidget);
    // Back on the slide the page had to throw away: the poster again,
    // waiting for a tap.
    expect(find.text('Play video'), findsOneWidget);
    expect(find.byType(ProductVideoPlayer), findsNothing);
  });

  testWidgets('a screen opened over the product page pauses it', (
    tester,
  ) async {
    await show(tester, koi);
    await swipe(tester);
    await tester.tap(find.text('Play video'));
    await tester.pumpAndSettle();
    expect(player(tester).active, isTrue);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('covering screen')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester
          .widget<ProductVideoPlayer>(
            find.byType(ProductVideoPlayer, skipOffstage: false),
          )
          .active,
      isFalse,
    );
    await tester.pumpAndSettle();

    navigator.pop();
    await tester.pumpAndSettle();
    // Visible again, but resuming is the shopper's choice: the player was
    // paused and nothing here presses play for them.
    expect(find.byType(GalleryVideoSlide), findsOneWidget);
  });

  testWidgets('reduced motion: the player replaces the poster without a '
      'cross-fade', (tester) async {
    await show(tester, koi, reduceMotion: true);
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play video'));
    await tester.pump();
    // One frame later there is no poster left fading out.
    expect(find.text('Play video'), findsNothing);
    expect(find.byType(ProductVideoPlayer), findsOneWidget);
  });

  testWidgets('a fish with a video and no photos still shows it', (
    tester,
  ) async {
    await show(
      tester,
      const Product(
        id: 'p',
        name: 'Showa',
        category: ProductCategory.koi,
        price: 300,
        stockQuantity: 1,
        videoUrl: video,
      ),
    );
    expect(find.text('Play video'), findsOneWidget);
    // One slide: nothing to count.
    expect(find.textContaining(' / '), findsNothing);
  });

  testWidgets('a fish without a video keeps a photo-only gallery', (
    tester,
  ) async {
    await show(
      tester,
      const Product(
        id: 'p',
        name: 'Sanke',
        category: ProductCategory.koi,
        price: 300,
        stockQuantity: 1,
        imageUrls: photos,
      ),
    );
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Photo 1 of 3'), findsOneWidget);
    expect(find.byType(GalleryVideoSlide, skipOffstage: false), findsNothing);
  });

  testWidgets('other products keep their video below, outside the gallery', (
    tester,
  ) async {
    await show(tester, food);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.byType(GalleryVideoSlide, skipOffstage: false), findsNothing);
    await tester.scrollUntilVisible(
      find.text('VIDEO'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('VIDEO'), findsOneWidget);
    final below = tester.widget<ProductVideoPlayer>(
      find.byType(ProductVideoPlayer, skipOffstage: false),
    );
    expect(below.autoPlay, isFalse);
  });
}
