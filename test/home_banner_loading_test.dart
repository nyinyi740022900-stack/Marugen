import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/banners/presentation/hero_banner_carousel.dart';
import 'package:marugen_app/features/banners/presentation/home_banner_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/features/shop/presentation/shop_screen.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_providers.dart';
import 'package:marugen_app/shared/models/home_banner.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:marugen_app/shared/widgets/skeleton.dart';

// Empty image URLs render the local placeholder, so no network is touched.
const _slides = [
  HomeBanner(
    id: 'a',
    imageUrl: '',
    title: 'First',
    ctaLabel: 'Shop Koi',
    linkUrl: '/product/1',
  ),
  HomeBanner(id: 'b', imageUrl: '', title: 'Second', ctaLabel: 'No link'),
  HomeBanner(id: 'c', imageUrl: '', title: 'Third'),
];

const _marker = Key('below-banner');

Widget _hero({required List<Override> overrides, bool reduceMotion = false}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: const Scaffold(
          body: Column(
            children: [
              HeroBannerCarousel(),
              SizedBox(key: _marker, height: 10),
            ],
          ),
        ),
      ),
    );

double _catalogueTop(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(_marker)).dy;

class _EmptyCart extends CartNotifier {
  @override
  List<CartItem> build() => const [];
}

class _EmptyWishlist extends WishlistIdsNotifier {
  @override
  AsyncValue<Set<String>> build() => const AsyncData({});
}

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(390, 844);
    view.devicePixelRatio = 1;
    addTearDown(view.reset);
  });

  group('banner space on the Shop tab', () {
    testWidgets('nothing is reserved while loading or when there are no '
        'slides, so the catalogue never jumps on a day without banners', (
      tester,
    ) async {
      final fetch = Completer<List<HomeBanner>>();
      await tester.pumpWidget(
        _hero(
          overrides: [
            liveHomeBannersProvider.overrideWith((ref) => fetch.future),
          ],
        ),
      );
      expect(find.byType(Skeleton), findsNothing);
      expect(_catalogueTop(tester), 0);

      fetch.complete(const []);
      await tester.pumpAndSettle();
      expect(_catalogueTop(tester), 0);
    });

    testWidgets('a failed fetch takes no space either', (tester) async {
      await tester.pumpWidget(
        _hero(
          overrides: [
            liveHomeBannersProvider.overrideWith(
              (ref) async => throw StateError('offline'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(_catalogueTop(tester), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('slides ease in when they arrive', (tester) async {
      final fetch = Completer<List<HomeBanner>>();
      await tester.pumpWidget(
        _hero(
          overrides: [
            liveHomeBannersProvider.overrideWith((ref) => fetch.future),
          ],
        ),
      );
      fetch.complete(_slides);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final midway = _catalogueTop(tester);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      final open = _catalogueTop(tester);
      expect(open, greaterThan(180));
      expect(midway, greaterThan(0));
      expect(midway, lessThan(open));
      expect(find.text('First'), findsOneWidget);
    });

    testWidgets('Reduce Motion shows the slides at once', (tester) async {
      final fetch = Completer<List<HomeBanner>>();
      await tester.pumpWidget(
        _hero(
          reduceMotion: true,
          overrides: [
            liveHomeBannersProvider.overrideWith((ref) => fetch.future),
          ],
        ),
      );
      fetch.complete(_slides);
      await tester.pump();
      await tester.pump();
      final first = _catalogueTop(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(first, greaterThan(180));
      expect(_catalogueTop(tester), first);
    });

    testWidgets('slides already loaded appear without replaying the '
        'entrance', (tester) async {
      await tester.pumpWidget(
        _hero(
          overrides: [
            liveHomeBannersProvider.overrideWith((ref) async => _slides),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final open = _catalogueTop(tester);
      // The grid swaps its skeleton for products: a new carousel element.
      await tester.pumpWidget(
        _hero(
          overrides: [
            liveHomeBannersProvider.overrideWith((ref) async => _slides),
          ],
        ),
      );
      await tester.pump();
      expect(_catalogueTop(tester), open);
    });
  });

  group('banner freshness', () {
    testWidgets('returning from the background fetches the slides again and '
        'keeps the current ones up meanwhile', (tester) async {
      var fetches = 0;
      var slides = [_slides[0]];
      await tester.pumpWidget(
        _hero(
          overrides: [
            liveHomeBannersProvider.overrideWith((ref) async {
              fetches++;
              return slides;
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(fetches, 1);
      final open = _catalogueTop(tester);

      slides = [_slides[2]];
      // The platform always walks through every state in order.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(fetches, 1);
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      // No collapse while the refetch is in flight.
      expect(_catalogueTop(tester), open);
      await tester.pumpAndSettle();
      expect(fetches, 2);
      expect(find.text('Third'), findsOneWidget);
      expect(find.text('First'), findsNothing);
    });

    testWidgets('pulling the shop down refreshes the banners with the '
        'catalogue, and a banner outage does not fail the refresh', (
      tester,
    ) async {
      var productLoads = 0;
      var bannerLoads = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productListProvider.overrideWith((ref) async {
              productLoads++;
              return const [
                Product(
                  id: 'koi',
                  name: 'Kohaku',
                  category: ProductCategory.koi,
                  price: 300,
                  stockQuantity: 1,
                ),
              ];
            }),
            liveHomeBannersProvider.overrideWith((ref) async {
              if (bannerLoads++ == 1) throw StateError('offline');
              return [_slides[0]];
            }),
            currentUserIdProvider.overrideWith((ref) => null),
            isLoggedInProvider.overrideWith((ref) => false),
            cartProvider.overrideWith(_EmptyCart.new),
            wishlistProductIdsProvider.overrideWith(_EmptyWishlist.new),
            shopSettingsProvider.overrideWith((ref) async => {}),
            unreadNotificationCountProvider.overrideWith((ref) => 0),
          ],
          child: const MaterialApp(home: ShopScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect((productLoads, bannerLoads), (1, 1));

      Future<void> pull() async {
        await tester.fling(
          find.byType(CustomScrollView),
          const Offset(0, 400),
          1200,
        );
        await tester.pumpAndSettle();
      }

      // Second banner fetch fails: the catalogue still refreshes and the
      // slide that was showing stays.
      await pull();
      expect((productLoads, bannerLoads), (2, 2));
      expect(find.text('First'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await pull();
      expect((productLoads, bannerLoads), (3, 3));
    });
  });

  group('banner slides', () {
    Widget carousel() => MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          child: BannerCarousel(
            banners: _slides,
            interval: Duration(minutes: 1),
          ),
        ),
      ),
    );

    testWidgets('the button pill is drawn only for a slide with a link', (
      tester,
    ) async {
      await tester.pumpWidget(carousel());
      expect(find.text('Shop Koi'), findsOneWidget);
      await tester.fling(find.text('First'), const Offset(-300, 0), 1200);
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      expect(find.text('No link'), findsNothing);
    });

    test('the slide is announced with its button label when it has a link', () {
      expect(
        bannerSemanticsLabel(_slides[0], 0, 3),
        'Banner 1 of 3: First. Shop Koi',
      );
      expect(bannerSemanticsLabel(_slides[1], 1, 3), 'Banner 2 of 3: Second');
      expect(
        bannerSemanticsLabel(const HomeBanner(id: 'x', imageUrl: ''), 0, 1),
        'Banner 1 of 1',
      );
    });

    testWidgets('slide and dots carry their labels for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(carousel());
      // The node also merges the visible headline text after the label.
      expect(
        find.bySemanticsLabel(RegExp(r'^Banner 1 of 3: First\. Shop Koi')),
        findsOneWidget,
      );
      for (var n = 1; n <= 3; n++) {
        final dot = find.bySemanticsLabel('Go to banner $n');
        expect(dot, findsOneWidget);
        final node = tester.getSemantics(dot);
        expect(node.flagsCollection.isButton, isTrue);
        expect(
          node.flagsCollection.isSelected,
          n == 1 ? Tristate.isTrue : Tristate.isFalse,
        );
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      }
      handle.dispose();
    });

    testWidgets('each dot is a 44pt target and jumps to its slide', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(carousel());
      for (var n = 1; n <= 3; n++) {
        final size = tester.getSize(find.bySemanticsLabel('Go to banner $n'));
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      // Tap the corner of the target, well away from the 6pt dot itself.
      final target = tester.getRect(find.bySemanticsLabel('Go to banner 3'));
      await tester.tapAt(target.topRight + const Offset(-3, 3));
      await tester.pumpAndSettle();
      expect(find.text('Third'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('many slides still fit a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: BannerCarousel(
              banners: [
                for (var i = 0; i < 10; i++)
                  HomeBanner(id: '$i', imageUrl: '', title: 'Slide $i'),
              ],
              interval: const Duration(minutes: 1),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Go to banner 10'), findsOneWidget);
    });
  });
}
