import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/banners/presentation/home_banner_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/features/shop/presentation/shop_screen.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/widgets/press_scale.dart';
import 'package:marugen_app/shared/widgets/product_card.dart';
import 'package:marugen_app/shared/widgets/product_grid.dart';

const _plain = Product(
  id: 'plain',
  name: 'Net',
  category: ProductCategory.accessories,
  price: 12,
  stockQuantity: 10,
);
const _proven = Product(
  id: 'proven',
  name: 'Marugen Special Mix High Growth Colour Enhancing Koi Food',
  category: ProductCategory.fishFood,
  price: 118.80,
  stockQuantity: 10,
  avgRating: 4.8,
  reviewCount: 152,
  soldCount: 991,
);
const _sale = Product(
  id: 'sale',
  name: 'Pond filter media',
  category: ProductCategory.accessories,
  price: 100,
  salePrice: 80,
  stockQuantity: 2,
  avgRating: 5,
  reviewCount: 1,
  soldCount: 12345,
);
const _variants = Product(
  id: 'variants',
  name: 'Growth pellets',
  category: ProductCategory.fishFood,
  variants: [
    ProductVariant(
      id: 'a',
      productId: 'variants',
      label: '500g',
      price: 8.80,
      stockQuantity: 5,
    ),
    ProductVariant(
      id: 'b',
      productId: 'variants',
      label: '5kg',
      price: 8888.80,
      stockQuantity: 5,
    ),
  ],
);
const _fish = Product(
  id: 'fish',
  name: 'Kohaku',
  category: ProductCategory.koi,
  price: 320,
  stockQuantity: 1,
  avgRating: 4.8,
  reviewCount: 152,
  soldCount: 991,
  fishDetails: FishDetails(variety: 'Kohaku', sizeCm: 45, gender: 'Male'),
);
const _soldFish = Product(
  id: 'sold-fish',
  name: 'Showa with a long descriptive name for the listing',
  category: ProductCategory.koi,
  price: 123456.78,
  stockQuantity: 0,
  isSold: true,
  fishDetails: FishDetails(variety: 'Showa', sizeCm: 62.5),
);
const _outOfStock = Product(
  id: 'out',
  name: 'Air pump',
  category: ProductCategory.accessories,
  price: 45,
  stockQuantity: 0,
);
const _contact = Product(
  id: 'contact',
  name: 'Grand champion Sanke',
  category: ProductCategory.koi,
  showPrice: false,
  stockQuantity: 1,
);

const _all = [
  _plain,
  _proven,
  _sale,
  _variants,
  _fish,
  _soldFish,
  _outOfStock,
  _contact,
];

void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(
  Widget home, {
  double scale = 1,
  bool dark = false,
  TargetPlatform? platform,
  bool reduceMotion = false,
}) {
  final base = dark ? AppTheme.dark : AppTheme.light;
  // The app leaves the family to the platform; a test has to name the one
  // loaded in setUpAll to be measured with it.
  final theme = base.copyWith(
    platform: platform,
    textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
  );
  return MaterialApp(
    theme: theme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduceMotion,
      ),
      child: child!,
    ),
    home: home,
  );
}

Widget _grid(List<Product> products) => Scaffold(
  body: ProductGrid(
    itemCount: products.length,
    itemBuilder: (_, i) => ProductCard(product: products[i], onTap: () {}),
  ),
);

Finder _cardOf(Product product) => find.byWidgetPredicate(
  (w) => w is ProductCard && w.product.id == product.id,
);

/// The padded text block under the photo.
Finder _bodyOf(Finder card) => find.descendant(
  of: card,
  matching: find.byWidgetPredicate(
    (w) =>
        w is Padding && w.padding == const EdgeInsets.fromLTRB(10, 8, 10, 10),
  ),
);

Finder _photoOf(Finder card) =>
    find.descendant(of: card, matching: find.byType(AspectRatio)).first;

void main() {
  // Real Roboto and icon metrics from the SDK, so "fits" means what it will
  // mean on a phone rather than in the square test font.
  var realFont = false;
  setUpAll(() async {
    var sdk = File(Platform.resolvedExecutable).parent;
    while (!Directory('${sdk.path}/bin/cache/artifacts/material_fonts')
            .existsSync() &&
        sdk.parent.path != sdk.path) {
      sdk = sdk.parent;
    }
    final fonts = '${sdk.path}/bin/cache/artifacts/material_fonts';
    final roboto = FontLoader('Roboto');
    var found = 0;
    for (final cut in ['Regular', 'Medium', 'Bold']) {
      final file = File('$fonts/Roboto-$cut.ttf');
      if (!file.existsSync()) continue;
      found++;
      roboto.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    if (found == 3) {
      await roboto.load();
      realFont = true;
    }
    final icons = File('$fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(icons.readAsBytes().then(ByteData.sublistView))).load();
    }
  });

  testWidgets('cards in a row are the same height with and without rating, '
      'sold count, sale, fish facts or stock state', (tester) async {
    _viewport(tester, const Size(390, 3000));
    await tester.pumpWidget(_app(_grid(_all)));
    await tester.pump();

    final cards = find.byType(ProductCard);
    expect(cards, findsNWidgets(_all.length));
    final first = tester.getRect(cards.first);
    final firstBody = tester.getRect(_bodyOf(cards.first));
    for (var i = 0; i < _all.length; i++) {
      final card = tester.getRect(cards.at(i));
      expect(card.width, closeTo(first.width, 0.01), reason: _all[i].id);
      expect(card.height, closeTo(first.height, 0.01), reason: _all[i].id);
      // Same row, same top: a fixed two-column grid, not a masonry.
      expect(card.top, tester.getRect(cards.at(i - i % 2)).top);
      // Square photo edge to edge, then the body, then nothing: no band.
      final photo = tester.getRect(_photoOf(cards.at(i)));
      final body = tester.getRect(_bodyOf(cards.at(i)));
      expect(photo.topLeft, card.topLeft);
      expect(photo.width, card.width);
      expect(photo.height, closeTo(photo.width, 0.01));
      expect(body.top, closeTo(photo.bottom, 0.01));
      expect(body.bottom, closeTo(card.bottom, 0.01), reason: _all[i].id);
      expect(body.height, closeTo(firstBody.height, 0.01));
    }
    // Prices line up across the row whatever the name length.
    expect(
      tester.getRect(find.text(r'S$12.00')).top,
      closeTo(tester.getRect(find.text(r'S$118.80')).top, 0.01),
    );
    // 12 px gutter between the two columns and between rows.
    expect(
      tester.getRect(cards.at(1)).left - tester.getRect(cards.at(0)).right,
      closeTo(12, 0.01),
    );
    expect(
      tester.getRect(cards.at(2)).top - tester.getRect(cards.at(0)).bottom,
      closeTo(12, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  group('nothing clips or overflows', () {
    // Width → columns at text scale 1.0 / 1.3 / 2.0.
    final layouts = <double, List<int>>{
      // One column, as before the redesign: two would be under 156 wide.
      320: [1, 1, 1],
      360: [2, 2, 1],
      390: [2, 2, 1],
      600: [3, 3, 2],
      820: [4, 4, 3],
    };
    const scales = [1.0, 1.3, 2.0];
    for (final MapEntry(key: width, value: columns) in layouts.entries) {
      for (var s = 0; s < scales.length; s++) {
        for (final dark in [false, true]) {
          final scale = scales[s];
          testWidgets('at $width wide, text $scale, dark=$dark', (
            tester,
          ) async {
            _viewport(tester, Size(width, 6000));
            await tester.pumpWidget(
              _app(_grid(_all), scale: scale, dark: dark),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);

            final cards = find.byType(ProductCard);
            expect(cards, findsNWidgets(_all.length));
            final firstRowTop = tester.getRect(cards.first).top;
            final inFirstRow = [
              for (var i = 0; i < _all.length; i++)
                if (tester.getRect(cards.at(i)).top == firstRowTop) i,
            ];
            expect(inFirstRow.length, columns[s]);

            final size = tester.getRect(cards.first).size;
            for (var i = 0; i < _all.length; i++) {
              final card = cards.at(i);
              final rect = tester.getRect(card);
              expect(rect.width, closeTo(size.width, 0.01));
              expect(rect.height, closeTo(size.height, 0.01));
              expect(
                tester.getRect(_bodyOf(card)).bottom,
                closeTo(rect.bottom, 0.01),
              );
              // Every line of text stays inside its card, and the name is
              // the only one allowed to end in an ellipsis.
              for (final element
                  in find
                      .descendant(of: card, matching: find.byType(Text))
                      .evaluate()) {
                final box = element.findRenderObject()! as RenderParagraph;
                final text = Rect.fromPoints(
                  box.localToGlobal(Offset.zero),
                  box.localToGlobal(box.size.bottomRight(Offset.zero)),
                );
                expect(text.left, greaterThanOrEqualTo(rect.left - 0.01));
                expect(text.right, lessThanOrEqualTo(rect.right + 0.01));
                expect(text.top, greaterThanOrEqualTo(rect.top - 0.01));
                expect(text.bottom, lessThanOrEqualTo(rect.bottom + 0.01));
              }
            }
            // The price is never cut short.
            for (final label in [
              r'S$12.00',
              r'S$118.80',
              r'S$80.00',
              r'From S$8.80',
              r'S$320.00',
              r'S$123456.78',
              'Contact for price',
            ]) {
              expect(find.text(label), findsOneWidget, reason: label);
              final paragraph = tester.renderObject<RenderParagraph>(
                find.text(label),
              );
              expect(paragraph.didExceedMaxLines, isFalse, reason: label);
              // Nor shrunk: at real font metrics it is drawn at full size.
              if (realFont) {
                expect(
                  tester.getRect(find.text(label)).height,
                  closeTo(paragraph.size.height, 0.01),
                  reason: '$label is scaled down',
                );
              }
            }
          });
        }
      }
    }
  });

  testWidgets('light cards are flat with a hairline; dark cards have neither '
      'shadow nor border', (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(_app(_grid(const [_plain]), dark: dark));
      // The theme change eases in.
      await tester.pumpAndSettle();
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ProductCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final box = container.decoration! as BoxDecoration;
      final palette = dark ? AppPalette.dark : AppPalette.light;
      expect(box.color, palette.surface);
      expect(box.boxShadow, isNull);
      expect(box.borderRadius, BorderRadius.circular(AppRadius.md));
      final edge = container.foregroundDecoration as BoxDecoration?;
      if (dark) {
        expect(edge, isNull);
      } else {
        expect(edge!.border, Border.all(color: palette.border));
      }
    }
  });

  testWidgets('the card is the only thing on it that can be tapped', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: ProductCard(product: _fish, onTap: () => taps++),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final card = find.byType(ProductCard);
    Finder inside(Finder matching) =>
        find.descendant(of: card, matching: matching);

    expect(inside(find.byType(IconButton)), findsNothing);
    expect(inside(find.byType(Tooltip)), findsNothing);
    expect(
      inside(find.byWidgetPredicate((w) => w is ButtonStyleButton)),
      findsNothing,
    );
    // One ink surface, and the one gesture detector inside it.
    expect(
      inside(find.byWidgetPredicate((w) => w is InkResponse)),
      findsOneWidget,
    );
    expect(inside(find.byType(GestureDetector)), findsOneWidget);
    expect(inside(find.byIcon(Icons.add_shopping_cart)), findsNothing);
    expect(inside(find.byIcon(Icons.bolt)), findsNothing);
    expect(inside(find.byIcon(Icons.chat_bubble_outline)), findsNothing);
    expect(inside(find.byIcon(Icons.local_shipping_outlined)), findsNothing);
    expect(find.textContaining('Delivery'), findsNothing);

    // Every corner of the card is the same target, including where the
    // heart and the cart button used to sit.
    final rect = tester.getRect(card);
    for (final point in [
      rect.topRight + const Offset(-20, 20),
      rect.bottomRight + const Offset(-20, -20),
      rect.bottomLeft + const Offset(20, -20),
      rect.center,
    ]) {
      await tester.tapAt(point);
      await tester.pumpAndSettle();
    }
    expect(taps, 4);

    // One semantics node: a button with the tap, and nothing under it.
    final node = tester.getSemantics(card);
    expect(
      node,
      matchesSemantics(
        label: productCardSemanticsLabel(_fish),
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    expect(node.childrenCount, 0);
    handle.dispose();
  });

  test('one merged label names the product, price, proof and state', () {
    expect(
      productCardSemanticsLabel(_fish),
      r'Kohaku, 45 cm, Male, S$320.00, rating 4.8 of 5 from 152 reviews, '
      '991 sold',
    );
    expect(
      productCardSemanticsLabel(_sale),
      r'Pond filter media, on sale S$80.00, was S$100.00, 20% off, '
      'rating 5.0 of 5 from 1 review, 12345 sold, only 2 left',
    );
    expect(
      productCardSemanticsLabel(_soldFish),
      r'Showa with a long descriptive name for the listing, 62.5 cm, '
      r'S$123456.78, sold',
    );
    expect(
      productCardSemanticsLabel(_outOfStock),
      r'Air pump, S$45.00, out of stock',
    );
    expect(
      productCardSemanticsLabel(_variants),
      r'Growth pellets, From S$8.80',
    );
    expect(
      productCardSemanticsLabel(_contact),
      'Grand champion Sanke, Contact for price',
    );
    expect(productCardSemanticsLabel(_plain), r'Net, S$12.00');
  });

  testWidgets('the proof line, tags and sold states read as designed', (
    tester,
  ) async {
    _viewport(tester, const Size(820, 3000));
    await tester.pumpWidget(_app(_grid(_all)));
    await tester.pump();
    final accent = AppPalette.light.accent;
    final muted = AppPalette.light.textMuted;
    Color? colorOf(String text) =>
        tester.widget<Text>(find.text(text)).style!.color;
    String proofOf(Product product) => find
        .descendant(of: _cardOf(product), matching: find.byType(Text))
        .evaluate()
        .map((e) => e.widget as Text)
        .where((t) => t.textSpan != null)
        .single
        .textSpan!
        .toPlainText();

    // One muted line: the fish's facts, then rating and units sold.
    expect(proofOf(_proven), '￼4.8 (152) · 991 sold');
    expect(proofOf(_fish), '45 cm · Male · ￼4.8 (152) · 991 sold');
    expect(proofOf(_soldFish), '62.5 cm');
    expect(
      find.descendant(
        of: _cardOf(_proven),
        matching: find.byIcon(Icons.star_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _cardOf(_plain),
        matching: find.byIcon(Icons.star_rounded),
      ),
      findsNothing,
    );

    // Price: accent when it can be bought, muted when it cannot.
    expect(colorOf(r'S$12.00'), accent);
    expect(colorOf(r'From S$8.80'), accent);
    expect(colorOf('Contact for price'), muted);
    expect(colorOf(r'S$45.00'), muted);
    expect(colorOf(r'S$123456.78'), muted);

    // Sale: the new price, the struck original and the tag on the photo.
    expect(colorOf(r'S$80.00'), accent);
    expect(find.text('-20%'), findsOneWidget);
    expect(find.text('Only 2 left'), findsOneWidget);

    // Variety tags top-left of the photo.
    final fishPhoto = tester.getRect(_photoOf(_cardOf(_fish)));
    final variety = tester.getRect(
      find.descendant(of: _cardOf(_fish), matching: find.text('Kohaku')).first,
    );
    expect(variety.top - fishPhoto.top, lessThan(16));
    expect(variety.left - fishPhoto.left, lessThan(20));

    // A sold fish keeps its stamp; restockable goods get a small tag at
    // the bottom-left of the photo. Neither is a button.
    expect(find.text('SOLD'), findsOneWidget);
    expect(find.text('OUT OF STOCK'), findsNothing);
    final tag = tester.getRect(find.text('Out of stock'));
    final photo = tester.getRect(_photoOf(_cardOf(_outOfStock)));
    expect(photo.bottom - tag.bottom, lessThan(16));
    expect(tag.left - photo.left, lessThan(20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the struck original price sits beside the sale price when '
      'there is room, and steps aside above 1.3× text or on a narrow card', (
    tester,
  ) async {
    // The test font is far wider than a real one, hence the wide card.
    Widget card(double width, [Product product = _sale]) => Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: ProductCard(product: product, onTap: () {}),
        ),
      ),
    );
    for (final scale in [1.0, 1.3]) {
      await tester.pumpWidget(_app(card(360), scale: scale));
      await tester.pump();
      final price = tester.getRect(find.text(r'S$80.00'));
      final original = tester.getRect(find.text(r'S$100.00'));
      expect(
        tester.widget<Text>(find.text(r'S$100.00')).style!.decoration,
        TextDecoration.lineThrough,
      );
      // Same line, original after the price, both inside the card.
      expect(original.left, greaterThan(price.right));
      expect(original.top, greaterThan(price.top - 1));
      expect(original.bottom, lessThan(price.bottom + 1));
      expect(
        original.right,
        lessThanOrEqualTo(tester.getRect(find.byType(ProductCard)).right),
      );
    }

    await tester.pumpWidget(_app(card(360), scale: 2));
    await tester.pump();
    expect(find.text(r'S$80.00'), findsOneWidget);
    expect(find.text(r'S$100.00'), findsNothing);
    expect(find.text('-20%'), findsOneWidget);

    // No room: the sale price keeps the line to itself, whole.
    const dear = Product(
      id: 'dear',
      name: 'Pond pump',
      category: ProductCategory.accessories,
      price: 12345,
      salePrice: 9999,
      stockQuantity: 10,
    );
    await tester.pumpWidget(_app(card(150, dear)));
    await tester.pump();
    expect(find.text(r'S$12345.00'), findsNothing);
    expect(find.text('-19%'), findsOneWidget);
    final price = find.text(r'S$9999.00');
    expect(
      tester.renderObject<RenderParagraph>(price).didExceedMaxLines,
      isFalse,
    );
    expect(
      tester.getRect(price).right,
      lessThanOrEqualTo(tester.getRect(find.byType(ProductCard)).right),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pressing responds at once and reduced motion keeps it still', (
    tester,
  ) async {
    double scaleOf() => tester
        .widget<AnimatedScale>(
          find.descendant(
            of: find.byType(PressScale),
            matching: find.byType(AnimatedScale),
          ),
        )
        .scale;
    for (final reduceMotion in [false, true]) {
      await tester.pumpWidget(
        _app(_grid(const [_plain]), reduceMotion: reduceMotion),
      );
      await tester.pump();
      expect(scaleOf(), 1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ProductCard)),
      );
      // On touch-down, before any tap is recognised.
      await tester.pump();
      expect(scaleOf(), reduceMotion ? 1 : 0.97);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scaleOf(), 1);
    }
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('tapping anywhere on a shop card opens its product page on '
        '$platform', (tester) async {
      _viewport(tester, const Size(390, 900));
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const ShopScreen()),
          GoRoute(
            path: '/product/:id',
            builder: (_, state) =>
                Scaffold(body: Text('Product ${state.pathParameters['id']}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productListProvider.overrideWith(
              (ref) async => const [_proven, _fish],
            ),
            liveHomeBannersProvider.overrideWith((ref) async => []),
            cartProvider.overrideWith(_EmptyCart.new),
            unreadNotificationCountProvider.overrideWith((ref) => 0),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light.copyWith(platform: platform),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProductCard), findsNWidgets(2));

      // Bottom-right of the body: where the cart / Buy button used to be.
      final food = tester.getRect(_cardOf(_proven));
      await tester.tapAt(food.bottomRight + const Offset(-16, -16));
      await tester.pumpAndSettle();
      expect(find.text('Product proven'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();

      // Top-right of the photo: where the heart used to be.
      final fish = tester.getRect(_cardOf(_fish));
      await tester.tapAt(fish.topRight + const Offset(-20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Product fish'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

class _EmptyCart extends CartNotifier {
  @override
  List<CartItem> build() => const [];
}
