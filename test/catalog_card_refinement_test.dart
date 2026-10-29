import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/shop/presentation/product_detail_screen.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/features/reviews/presentation/review_providers.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_providers.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:marugen_app/shared/widgets/product_card.dart';
import 'package:marugen_app/shared/widgets/product_grid.dart';

const _food = Product(
  id: 'food',
  name: 'Marugen Special Mix High Growth Colour Enhancing Koi Food',
  category: ProductCategory.fishFood,
  price: 8.80,
  stockQuantity: 10,
  avgRating: 5,
  reviewCount: 1,
  variants: [
    ProductVariant(
      id: 'small',
      productId: 'food',
      label: '500g',
      price: 8.80,
      stockQuantity: 10,
    ),
    ProductVariant(
      id: 'large',
      productId: 'food',
      label: '5kg',
      price: 88,
      stockQuantity: 10,
    ),
  ],
);
const _expensive = Product(
  id: 'fish',
  name: 'Japanese Kohaku with a long descriptive name',
  category: ProductCategory.koi,
  price: 123456.78,
  stockQuantity: 1,
);

void main() {
  setUpAll(() async {
    var sdkDirectory = File(Platform.resolvedExecutable).parent;
    while (!Directory('${sdkDirectory.path}/bin/cache/artifacts/material_fonts')
            .existsSync() &&
        sdkDirectory.parent.path != sdkDirectory.path) {
      sdkDirectory = sdkDirectory.parent;
    }
    final fontDirectory =
        '${sdkDirectory.path}/bin/cache/artifacts/material_fonts';
    final systemFont = File('/System/Library/Fonts/SFNS.ttf');
    final textFont = systemFont.existsSync()
        ? systemFont
        : File('$fontDirectory/Roboto-Regular.ttf');
    if (textFont.existsSync()) {
      await (FontLoader(
        '.SF Pro Text',
      )..addFont(textFont.readAsBytes().then(ByteData.sublistView))).load();
    }
    final icons = File('$fontDirectory/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(icons.readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('recommendations remain reachable and complete at $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: ProviderScope(
            overrides: [
              isLoggedInProvider.overrideWithValue(false),
              currentUserIdProvider.overrideWithValue(null),
              cartProvider.overrideWith(_EmptyCart.new),
              wishlistProductIdsProvider.overrideWith(_EmptyWishlist.new),
              shopSettingsProvider.overrideWith((ref) async => {}),
              productDetailProvider('food').overrideWith((ref) async => _food),
              relatedProductsProvider((
                id: 'food',
                category: ProductCategory.fishFood,
              )).overrideWith((ref) async => [_food, _expensive]),
              productReviewsProvider('food').overrideWith((ref) async => []),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const ProductDetailScreen(productId: 'food'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tab = find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Recommended for you'),
      );
      expect(tab, findsOneWidget);
      await tester.ensureVisible(tab);
      await tester.pumpAndSettle();
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(find.byType(ProductCard), findsAtLeastNWidgets(1));
      final price = find.text(r'From S$8.80').last;
      expect(
        tester.renderObject<RenderParagraph>(price).didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      final carousel = find.byType(ListView).last;
      await tester.drag(carousel, const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(find.text(r'S$123456.78'), findsOneWidget);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(r'S$123456.78'))
            .didExceedMaxLines,
        isFalse,
      );
      await tester.drag(carousel, const Offset(350, 0));
      await tester.pumpAndSettle();
      if (Platform.environment['CATALOG_CAPTURE'] == '1') {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          final dir = Directory('output/catalog-refinement')
            ..createSync(recursive: true);
          File('${dir.path}/recommendations-${scale.toInt()}x.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  for (final width in [320.0, 360.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets(
          'complete prices and usable actions at $width/$scale/dark=$dark',
          (tester) async {
            tester.view.physicalSize = Size(width, 1200);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('capture'),
                child: ProviderScope(
                  overrides: [
                    isLoggedInProvider.overrideWithValue(false),
                    wishlistProductIdsProvider.overrideWith(_EmptyWishlist.new),
                    shopSettingsProvider.overrideWith(
                      (ref) async => {'delivery_lead_days_min': 2},
                    ),
                  ],
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: dark ? AppTheme.dark : AppTheme.light,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                    home: Scaffold(
                      body: ProductGrid(
                        itemCount: 2,
                        itemBuilder: (_, i) => ProductCard(
                          product: i == 0 ? _food : _expensive,
                          onTap: () {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final price = find.text(r'From S$8.80');
            final paragraph = tester.renderObject<RenderParagraph>(price);
            expect(
              paragraph.didExceedMaxLines,
              isFalse,
              reason: 'The full variant price must remain visible',
            );
            final priceRect = tester.getRect(price);
            final action = find.byTooltip('Choose options for ${_food.name}');
            final actionRect = tester.getRect(action);
            expect(priceRect.overlaps(actionRect), isFalse);
            expect(actionRect.width, greaterThanOrEqualTo(48));
            expect(actionRect.height, greaterThanOrEqualTo(48));
            expect(
              tester
                  .getSize(find.byTooltip('Save ${_food.name} to wishlist'))
                  .width,
              greaterThanOrEqualTo(48),
            );
            expect(tester.takeException(), isNull);
            if (Platform.environment['CATALOG_CAPTURE'] == '1') {
              await tester.runAsync(() async {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(const ValueKey('capture')),
                );
                final image = await boundary.toImage(pixelRatio: 1);
                final bytes = await image.toByteData(
                  format: ImageByteFormat.png,
                );
                final dir = Directory('output/catalog-refinement')
                  ..createSync(recursive: true);
                File(
                  '${dir.path}/cards-${width.toInt()}-${scale.toInt()}x-${dark ? 'dark' : 'light'}.png',
                ).writeAsBytesSync(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
          },
        );
      }
    }
  }
}

class _EmptyWishlist extends WishlistIdsNotifier {
  @override
  AsyncValue<Set<String>> build() => const AsyncData({});
}

class _EmptyCart extends CartNotifier {
  @override
  List<CartItem> build() => [];
}
