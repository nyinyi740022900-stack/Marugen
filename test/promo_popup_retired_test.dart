import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/banners/presentation/home_banner_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/shop/presentation/customer_shell.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/features/shop/presentation/shop_screen.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_providers.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyCart extends CartNotifier {
  @override
  List<CartItem> build() => const [];
}

class _EmptyWishlist extends WishlistIdsNotifier {
  @override
  AsyncValue<Set<String>> build() => const AsyncData({});
}

void main() {
  testWidgets('opening the customer app shows no promo popup, even for a '
      'shop that still has the old popup switched on', (tester) async {
    // A device that has never seen today's popup: the old code would show it.
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shopSettingsProvider.overrideWith((ref) async {
            return {
              'promo_banner_active': true,
              'promo_banner_image_url': 'https://img.invalid/promo.jpg',
              'promo_banner_link_url': 'https://shop.invalid/sale',
            };
          }),
          authStateProvider.overrideWith((ref) => const Stream.empty()),
          productListProvider.overrideWith((ref) async => const []),
          liveHomeBannersProvider.overrideWith((ref) async => const []),
          myOrdersProvider.overrideWith((ref) async => const []),
          currentUserIdProvider.overrideWith((ref) => null),
          isLoggedInProvider.overrideWith((ref) => false),
          currentAppUserProvider.overrideWith((ref) async => null),
          cartProvider.overrideWith(_EmptyCart.new),
          wishlistProductIdsProvider.overrideWith(_EmptyWishlist.new),
          unreadNotificationCountProvider.overrideWith((ref) => 0),
        ],
        child: const MaterialApp(home: CustomerShell()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(ShopScreen), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byTooltip('Close'), findsNothing);
    // The shell is the only route: nothing was pushed over it.
    expect(
      Navigator.of(tester.element(find.byType(ShopScreen))).canPop(),
      isFalse,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('promo_banner_last_shown_date_v1'), isNull);
  });
}
