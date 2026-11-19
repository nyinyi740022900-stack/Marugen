import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/core/router/app_router.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/banners/admin_banners_screen.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/banners/data/home_banner_repository.dart';
import 'package:marugen_app/features/banners/domain/banner_link.dart';
import 'package:marugen_app/features/banners/presentation/home_banner_providers.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/home_banner.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _products = [
  Product(
    id: 'p1',
    name: 'Kohaku 45cm',
    category: ProductCategory.koi,
    price: 300,
    stockQuantity: 1,
  ),
  Product(
    id: 'p2',
    name: 'Growth Pellets',
    category: ProductCategory.fishFood,
    price: 20,
    stockQuantity: 5,
  ),
];

class _Banners implements HomeBannerRepository {
  final saved = <Map<String, dynamic>>[];
  @override
  Future<String> upsertBanner(
    Map<String, dynamic> payload, {
    String? id,
  }) async {
    saved.add(payload);
    return id ?? 'new';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// An empty image URL keeps the preview on its local placeholder.
HomeBanner _banner({String? link, String? cta}) =>
    HomeBanner(id: 'b1', imageUrl: '', linkUrl: link, ctaLabel: cta);

Future<_Banners> _pumpForm(WidgetTester tester, HomeBanner existing) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = _Banners();
  await tester.pumpWidget(
    ProviderScope(
      // A fresh form each time, even when one test opens several banners.
      key: UniqueKey(),
      overrides: [
        homeBannerRepositoryProvider.overrideWithValue(repo),
        adminHomeBannersProvider.overrideWith((ref) async => [existing]),
        liveHomeBannersProvider.overrideWith((ref) async => [existing]),
        adminAllProductsProvider.overrideWith((ref) async => _products),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: BannerFormScreen(existing: existing),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

bool _selected(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

void main() {
  group('banner link rules', () {
    test('a saved value opens on the choice it belongs to', () {
      expect(bannerLinkKindOf(null), BannerLinkKind.none);
      expect(bannerLinkKindOf('  '), BannerLinkKind.none);
      expect(bannerLinkKindOf('/faq'), BannerLinkKind.faq);
      expect(bannerLinkKindOf('/product/abc-123'), BannerLinkKind.product);
      expect(bannerLinkKindOf('https://marugen.sg/x'), BannerLinkKind.web);
      expect(bannerLinkKindOf('http://marugen.sg'), BannerLinkKind.web);
      expect(bannerLinkKindOf('/cart'), BannerLinkKind.appPage);
      expect(bannerLinkKindOf('/product/'), BannerLinkKind.appPage);
      expect(bannerLinkKindOf('marugen.sg'), BannerLinkKind.appPage);
    });

    test('the product id round-trips through the stored path', () {
      expect(productBannerLink('abc-123'), '/product/abc-123');
      expect(productIdFromBannerLink('/product/abc-123'), 'abc-123');
      expect(productIdFromBannerLink('/product/abc/extra'), isNull);
      expect(productIdFromBannerLink('/products/abc'), isNull);
      expect(productIdFromBannerLink('https://x.y/product/abc'), isNull);
    });

    test('free-form paths must be a customer page the router has', () {
      for (final ok in [
        '/cart',
        '/faq',
        '/wishlist',
        '/product/abc',
        '/product/abc?ref=banner',
      ]) {
        expect(bannerAppPageError(ok), isNull, reason: ok);
      }
      for (final bad in [
        '/nope',
        '/product',
        '/product/',
        '/admin',
        '/checkout',
        '/login',
        '//evil.example',
        'cart',
        'marugen.sg',
        '',
      ]) {
        expect(bannerAppPageError(bad), isNotNull, reason: bad);
      }
    });

    test('a web address must be https', () {
      expect(bannerWebAddressError('https://marugen.sg/sale'), isNull);
      expect(bannerWebAddressError('http://marugen.sg'), isNotNull);
      expect(bannerWebAddressError('marugen.sg'), isNotNull);
      expect(bannerWebAddressError('https://'), isNotNull);
      expect(bannerWebAddressError(' '), isNotNull);
    });

    test('every allowed page is a route in the production router', () {
      final container = ProviderContainer(
        overrides: [
          isLoggedInProvider.overrideWithValue(false),
          authStateProvider.overrideWith(
            (ref) => Stream.value(AuthState(AuthChangeEvent.signedOut, null)),
          ),
          currentAppUserProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);
      final paths = container
          .read(routerProvider)
          .configuration
          .routes
          .whereType<GoRoute>()
          .map((r) => r.path)
          .toSet();
      expect(paths, containsAll(bannerLinkRoutePatterns));
    });
  });

  group('admin banner form', () {
    testWidgets('a button label without a link blocks the save', (
      tester,
    ) async {
      final repo = await _pumpForm(tester, _banner(cta: 'Shop Koi'));
      expect(_selected(tester, 'Nothing'), isTrue);
      await _save(tester);
      expect(
        find.text('Add a link, or remove the button label.'),
        findsOneWidget,
      );
      expect(repo.saved, isEmpty);

      // Either way out works: remove the label…
      await tester.enterText(_field('Button label'), '');
      await _save(tester);
      expect(repo.saved.single['cta_label'], isNull);
      expect(repo.saved.single['link_url'], isNull);
    });

    testWidgets('…or add a link', (tester) async {
      final repo = await _pumpForm(tester, _banner(cta: 'Read FAQ'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'FAQ'));
      await tester.pumpAndSettle();
      await _save(tester);
      expect(repo.saved.single['cta_label'], 'Read FAQ');
      expect(repo.saved.single['link_url'], '/faq');
    });

    testWidgets('saved links load into the right choice', (tester) async {
      await _pumpForm(tester, _banner());
      expect(_selected(tester, 'Nothing'), isTrue);
      // The hand-typed choice is only offered to a banner that has one.
      expect(find.widgetWithText(ChoiceChip, 'App page'), findsNothing);

      await _pumpForm(tester, _banner(link: '/product/p1'));
      expect(_selected(tester, 'A product'), isTrue);
      expect(find.text('Kohaku 45cm'), findsOneWidget);

      await _pumpForm(tester, _banner(link: '/faq'));
      expect(_selected(tester, 'FAQ'), isTrue);

      await _pumpForm(tester, _banner(link: 'https://marugen.sg/sale'));
      expect(_selected(tester, 'Web address'), isTrue);
      expect(
        tester.widget<TextField>(_field('Web address')).controller!.text,
        'https://marugen.sg/sale',
      );

      await _pumpForm(tester, _banner(link: '/cart'));
      expect(_selected(tester, 'App page'), isTrue);
      expect(
        tester.widget<TextField>(_field('App page')).controller!.text,
        '/cart',
      );
    });

    testWidgets('a product is chosen by searching, and its app path is saved', (
      tester,
    ) async {
      final repo = await _pumpForm(tester, _banner());
      await tester.tap(find.widgetWithText(ChoiceChip, 'A product'));
      await tester.pumpAndSettle();
      // Chosen, but no product yet.
      await _save(tester);
      expect(find.text('Choose a product.'), findsOneWidget);
      expect(repo.saved, isEmpty);

      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a product'), findsOneWidget);
      expect(find.text('Kohaku 45cm'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'pellet');
      await tester.pumpAndSettle();
      expect(find.text('Kohaku 45cm'), findsNothing);
      await tester.tap(find.text('Growth Pellets'));
      await tester.pumpAndSettle();

      expect(find.text('Growth Pellets'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      await _save(tester);
      expect(repo.saved.single['link_url'], '/product/p2');
    });

    testWidgets('a link to a deleted product is caught', (tester) async {
      final repo = await _pumpForm(tester, _banner(link: '/product/gone'));
      expect(find.text('Product no longer exists'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Nothing'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'A product'));
      await tester.pumpAndSettle();
      // Make the form dirty-independent: Save is always available.
      await _save(tester);
      expect(
        find.text('That product no longer exists. Choose another one.'),
        findsOneWidget,
      );
      expect(repo.saved, isEmpty);
    });

    testWidgets('a web address must start with https://', (tester) async {
      final repo = await _pumpForm(tester, _banner());
      await tester.tap(find.widgetWithText(ChoiceChip, 'Web address'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Web address'), 'http://marugen.sg');
      await _save(tester);
      expect(
        find.text('The web address must start with https://'),
        findsOneWidget,
      );
      expect(repo.saved, isEmpty);

      await tester.enterText(_field('Web address'), 'https://marugen.sg');
      await _save(tester);
      expect(repo.saved.single['link_url'], 'https://marugen.sg');
    });

    testWidgets('a hand-typed path must be a page that exists', (tester) async {
      final repo = await _pumpForm(tester, _banner(link: '/cart'));
      await tester.enterText(_field('App page'), '/sale-2026');
      await _save(tester);
      expect(
        find.textContaining('That page does not exist in the app.'),
        findsOneWidget,
      );
      expect(repo.saved, isEmpty);

      await tester.enterText(_field('App page'), '/wishlist');
      await _save(tester);
      expect(repo.saved.single['link_url'], '/wishlist');
    });

    // 320 pt at normal text and a wider screen at double text: the photo
    // row above the link section does not fit 2x text on a phone yet (it
    // predates this change), so that combination cannot be asserted here.
    for (final (size, scale) in [
      (const Size(320, 2400), 1.0),
      (const Size(600, 2400), 2.0),
    ]) {
      testWidgets(
        'link choices fit ${size.width.round()} pt at ${scale}x text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          for (final link in ['/product/p1', 'https://marugen.sg', '/cart']) {
            await tester.pumpWidget(
              ProviderScope(
                key: UniqueKey(),
                overrides: [
                  adminAllProductsProvider.overrideWith(
                    (ref) async => _products,
                  ),
                ],
                child: MaterialApp(
                  theme: AppTheme.dark,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: BannerFormScreen(existing: _banner(link: link)),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: link);
          }
        },
      );
    }
  });
}
