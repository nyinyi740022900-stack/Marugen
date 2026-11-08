import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/features/shop/data/product_repository.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/features/shop/presentation/shop_screen.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_providers.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:marugen_app/shared/widgets/back_to_first_tab.dart';
import 'package:marugen_app/shared/widgets/sized_network_image.dart';

const koi = Product(
  id: 'koi',
  name: 'Kohaku',
  category: ProductCategory.koi,
  price: 300,
  stockQuantity: 1,
);

class CountingProducts implements ProductRepository {
  int fetches = 0;
  @override
  Future<Product?> fetchProductById(String id) async {
    fetches++;
    return koi;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _EmptyCart extends CartNotifier {
  @override
  List<CartItem> build() => const [];
}

class _EmptyWishlist extends WishlistIdsNotifier {
  @override
  AsyncValue<Set<String>> build() => const AsyncData({});
}

void main() {
  testWidgets('thumbnails decode at the size they are shown, not the '
      'uploaded size', (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 60,
            height: 60,
            child: SizedNetworkImage(imageUrl: 'https://example.com/koi.jpg'),
          ),
        ),
      ),
    );
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.memCacheWidth, 180);
  });

  test('reopening a product fetches its current stock again', () async {
    final products = CountingProducts();
    final container = ProviderContainer(
      overrides: [productRepositoryProvider.overrideWithValue(products)],
    );
    addTearDown(container.dispose);
    final open = container.listen(productDetailProvider('koi'), (_, _) {});
    await container.read(productDetailProvider('koi').future);
    open.close();
    await Future<void>.delayed(Duration.zero);
    final reopen = container.listen(productDetailProvider('koi'), (_, _) {});
    addTearDown(reopen.close);
    await container.read(productDetailProvider('koi').future);
    expect(products.fetches, 2);
  });

  testWidgets('pulling the shop down reloads the catalogue', (tester) async {
    var loads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productListProvider.overrideWith((ref) async {
            loads++;
            return [koi];
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
    expect(loads, 1);
    await tester.fling(find.byType(GridView), const Offset(0, 400), 1200);
    await tester.pumpAndSettle();
    expect(loads, 2);
  });

  testWidgets('Android back on another tab returns to the first tab; on the '
      'first tab it leaves the app as usual', (tester) async {
    var appClosed = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') appClosed++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    var tab = 2;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => BackToFirstTab(
            index: tab,
            onBackToFirst: () => setState(() => tab = 0),
            child: Text('Tab $tab'),
          ),
        ),
      ),
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Tab 0'), findsOneWidget);
    expect(appClosed, 0);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(appClosed, 1);
  });
}
