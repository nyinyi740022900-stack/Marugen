import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/reviews/presentation/review_providers.dart';
import 'package:marugen_app/features/shop/presentation/product_detail_screen.dart';
import 'package:marugen_app/features/shop/presentation/product_share.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_providers.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:share_plus/share_plus.dart';

const _product = Product(
  id: 'food',
  name: 'Koi Food',
  category: ProductCategory.fishFood,
  price: 12,
  variants: [
    ProductVariant(
      id: 'large',
      productId: 'food',
      label: '5 kg',
      price: 98.8,
      stockQuantity: 10,
    ),
    ProductVariant(
      id: 'small',
      productId: 'food',
      label: '500 g',
      price: 12,
      stockQuantity: 10,
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  ProductShareService service, {
  Future<Map<String, dynamic>>? settings,
}) async {
  tester.view.physicalSize = const Size(360, 1200);
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
        shopSettingsProvider.overrideWith(
          (_) => settings ?? Future.value({'shop_phone': '+65 9123 4567'}),
        ),
        productDetailProvider('food').overrideWith((_) async => _product),
        relatedProductsProvider((
          id: 'food',
          category: ProductCategory.fishFood,
        )).overrideWith((_) async => []),
        productReviewsProvider('food').overrideWith((_) async => []),
        productShareServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const ProductDetailScreen(productId: 'food'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'share snapshots selection, anchors the sheet and blocks repeated taps',
    (tester) async {
      final settings = Completer<Map<String, dynamic>>();
      final sharing = Completer<ShareResult>();
      final payloads = <ShareParams>[];
      await _pump(
        tester,
        ProductShareService(
          loadImage: (_) async => null,
          nativeShare: (params) {
            payloads.add(params);
            return sharing.future;
          },
        ),
        settings: settings.future,
      );
      await tester.tap(find.text('5 kg').first);
      await tester.pump();
      final share = find.byTooltip('Share product');
      expect(tester.getSize(share).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(share).height, greaterThanOrEqualTo(48));
      await tester.tap(share);
      await tester.pump();
      await tester.tap(share);
      await tester.pump();
      await tester.tap(find.text('500 g').first);
      await tester.pump();
      settings.complete({'shop_phone': '+65 9123 4567'});
      await tester.pump();
      await tester.pump();
      expect(payloads, hasLength(1));
      expect(payloads.single.text, contains('S\$98.80'));
      expect(payloads.single.text, contains('wa.me/6591234567'));
      expect(payloads.single.sharePositionOrigin!.isEmpty, isFalse);
      sharing.complete(const ShareResult('', ShareResultStatus.dismissed));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not share this product. Please try again.'),
        findsNothing,
      );
    },
  );

  testWidgets('share errors offer retry and do not leave the action disabled', (
    tester,
  ) async {
    var attempts = 0;
    await _pump(
      tester,
      ProductShareService(
        loadImage: (_) async => null,
        nativeShare: (_) async {
          attempts++;
          if (attempts == 1) throw StateError('platform unavailable');
          return const ShareResult('', ShareResultStatus.dismissed);
        },
      ),
    );
    await tester.tap(find.byTooltip('Share product'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not share this product. Please try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets(
    'pushing another route while settings load cancels the pending sheet',
    (tester) async {
      final settings = Completer<Map<String, dynamic>>();
      var shares = 0;
      await _pump(
        tester,
        ProductShareService(
          nativeShare: (_) async {
            shares++;
            return const ShareResult('', ShareResultStatus.dismissed);
          },
        ),
        settings: settings.future,
      );
      await tester.tap(find.byTooltip('Share product'));
      unawaited(
        Navigator.of(tester.element(find.byType(ProductDetailScreen))).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Another screen')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(ProductDetailScreen, skipOffstage: false),
        findsOneWidget,
      );
      settings.complete({});
      await tester.pumpAndSettle();
      expect(shares, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'leaving while settings load never opens a sheet on another screen',
    (tester) async {
      final settings = Completer<Map<String, dynamic>>();
      var shares = 0;
      await _pump(
        tester,
        ProductShareService(
          loadImage: (_) async => null,
          nativeShare: (_) async {
            shares++;
            return const ShareResult('', ShareResultStatus.dismissed);
          },
        ),
        settings: settings.future,
      );
      await tester.tap(find.byTooltip('Share product'));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      settings.complete({});
      await tester.pumpAndSettle();
      expect(shares, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

class _EmptyWishlist extends WishlistIdsNotifier {
  @override
  AsyncValue<Set<String>> build() => const AsyncData({});
}

class _EmptyCart extends CartNotifier {
  @override
  List<CartItem> build() => [];
}
