import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:marugen_app/features/admin/settings/admin_settings_screen.dart';
import 'package:marugen_app/features/shop/presentation/shop_screen.dart';
import 'package:marugen_app/features/shop/presentation/product_detail_screen.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_providers.dart';
import 'package:marugen_app/features/reviews/presentation/review_providers.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/features/profile/presentation/address_providers.dart';
import 'package:marugen_app/features/orders/presentation/checkout_screen.dart';
import 'package:marugen_app/features/orders/presentation/shipping_quote_providers.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';

import 'shipping_test_fixtures.dart';

import 'package:flutter/material.dart';
import 'package:marugen_app/features/admin/knowledge/admin_knowledge_screen.dart';
import 'package:marugen_app/features/knowledge/presentation/knowledge_providers.dart';
import 'package:marugen_app/features/services/presentation/service_providers.dart';
import 'package:marugen_app/shared/models/knowledge.dart';
import 'package:marugen_app/features/admin/dashboard/admin_low_stock_screen.dart';
import 'package:marugen_app/features/admin/dashboard/admin_top_products_screen.dart';
import 'package:marugen_app/features/admin/promo/admin_promo_screen.dart';
import 'package:marugen_app/features/admin/reviews/admin_reviews_screen.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/features/promo/presentation/promo_providers.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/models/promo_code.dart';
import 'package:marugen_app/shared/models/review.dart';
import 'package:marugen_app/shared/providers/paged_notifier.dart';
import 'package:marugen_app/features/admin/admin_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/customers/admin_customer_profile_screen.dart';
import 'package:marugen_app/features/admin/customers/admin_customer_providers.dart';
import 'package:marugen_app/features/legal/terms_screen.dart';
import 'package:marugen_app/features/legal/privacy_screen.dart';
import 'package:marugen_app/features/support/faq_screen.dart';
import 'package:marugen_app/shared/models/address.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/shared/models/order.dart';

void main() {
  if (Platform.environment['UI_PAGE_CAPTURE'] == '1') {
    _registerVisualCaptures();
  }
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      'owner More menu scrolls on short screens in ${theme.brightness}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var selected = -1;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: AdminMoreMenu(
                selectedIndex: 3,
                onSelected: (value) => selected = value,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('Settings'), 100);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        expect(selected, 6);
        expect(tester.takeException(), isNull);
      },
    );
    for (final page in [
      const AdminKnowledgeScreen(),
      const AdminLowStockScreen(),
      const AdminTopProductsScreen(),
      const AdminPromoScreen(),
      const AdminReviewsScreen(),
    ]) {
      testWidgets(
        '${page.runtimeType} fits compact large text ${theme.brightness}',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                varietiesProvider(null).overrideWith(
                  (ref) async => const [
                    Variety(
                      id: 'koi',
                      name: 'Premium Japanese Kohaku',
                      category: 'koi',
                    ),
                  ],
                ),
                articlesProvider.overrideWith((ref) async => []),
                servicesProvider.overrideWith((ref) async => []),
                lowStockProductsProvider.overrideWithValue(
                  const AsyncData([
                    Product(
                      id: 'food',
                      name: 'Premium koi food with a long description',
                      category: ProductCategory.fishFood,
                      price: 123.45,
                      stockQuantity: 2,
                    ),
                  ]),
                ),
                adminOrdersProvider.overrideWith(
                  (ref) async => [
                    Order(
                      id: 'order',
                      userId: 'customer',
                      status: OrderStatus.paid,
                      total: 100,
                      createdAt: DateTime(2026),
                      items: const [
                        OrderItem(
                          productId: 'food',
                          productName:
                              'Premium koi food with a long description',
                          quantity: 1234,
                          unitPrice: 10,
                        ),
                      ],
                    ),
                  ],
                ),
                adminPromoCodesProvider.overrideWith(
                  (ref) async => const [
                    PromoCode(
                      id: 'promo',
                      code: 'LOYALCUSTOMER2026',
                      discountType: DiscountType.percent,
                      discountValue: 10,
                      active: true,
                    ),
                  ],
                ),
                adminReviewsPagedProvider.overrideWith(_LoadedReviews.new),
              ],
              child: MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
                home: page,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (page is AdminKnowledgeScreen) {
            await tester.tap(find.text('Guides'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('Services'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          if (page is AdminReviewsScreen) {
            await tester.tap(find.text('Reply'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.scrollUntilVisible(
              find.text('Post Reply'),
              150,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(find.text('Post Reply').hitTestable(), findsOneWidget);
          }
        },
      );
    }
    for (final size in [const Size(320, 640), const Size(820, 1100)]) {
      testWidgets(
        'customer profile fits long details at $size ${theme.brightness}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                customerProfileProvider('customer').overrideWith(
                  (ref) async => const AppUser(
                    id: 'customer',
                    fullName: 'Customer with a long display name',
                    email: 'customer@example.com',
                  ),
                ),
                customerAddressesProvider('customer').overrideWith(
                  (ref) async => const [
                    Address(
                      id: 'home',
                      userId: 'customer',
                      label: 'Family home and weekend delivery address',
                      recipientName: 'Long recipient name',
                      phone: '+65 8888 9999',
                      line1: '123 Example Road',
                      postalCode: '123456',
                      isDefault: true,
                    ),
                  ],
                ),
                customerOrdersProvider('customer').overrideWith(
                  (ref) async => [
                    Order(
                      id: '12345678-abcd',
                      userId: 'customer',
                      status: OrderStatus.paid,
                      total: 12345.67,
                      createdAt: DateTime(2026, 10, 23),
                    ),
                  ],
                ),
              ],
              child: MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
                home: const AdminCustomerProfileScreen(userId: 'customer'),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(find.text(r'S$12345.67'), 180);
          await tester.pumpAndSettle();
          expect(find.text(r'S$12345.67').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
      for (final page in [
        const TermsScreen(),
        const PrivacyScreen(),
        const FaqScreen(),
      ]) {
        testWidgets(
          '${page.runtimeType} fits large text at $size ${theme.brightness}',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  theme: theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(2)),
                    child: child!,
                  ),
                  home: page,
                ),
              ),
            );
            await tester.pumpAndSettle();
            if (page is FaqScreen) {
              await tester.tap(find.text('Where do you deliver?'));
              await tester.pumpAndSettle();
            }
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -600),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

class _LoadedReviews extends AdminReviewsPagedNotifier {
  @override
  AsyncValue<PagedListState<ProductReview>> build() => AsyncData(
    PagedListState(
      items: [
        ProductReview(
          id: 'review',
          productId: 'food',
          userId: 'customer',
          authorName: 'Long Customer Name',
          rating: 5,
          comment: 'Food arrived in good condition and my koi enjoy it.',
          createdAt: DateTime(2026),
        ),
      ],
      hasMore: false,
    ),
  );
}

// Opt-in screenshots use real installed fonts; ordinary widget tests remain
// portable and never initialize a backend client or write screenshot files.
void _registerVisualCaptures() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await (FontLoader('.SF Pro Text')..addFont(
          File('/System/Library/Fonts/SFNS.ttf')
              .readAsBytes()
              .then(ByteData.sublistView),
        ))
        .load();
    await (FontLoader('MaterialIcons')..addFont(
          File(
            '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    await Supabase.initialize(
      url: 'https://ui-review.invalid',
      publishableKey: 'test-key',
      httpClient: MockClient(
        (request) async => http.Response(
          request.url.path.contains('/rest/v1/settings')
              ? '{"shop_name":"Marugen Fish Farm","shop_phone":"+65 8888 9999"}'
              : '{"connected":false}',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  const product = Product(
    id: 'food',
    name: 'Premium koi growth food',
    category: ProductCategory.fishFood,
    price: 42.80,
    stockQuantity: 10,
    description: 'Balanced daily food for healthy koi growth. Store in a cool, dry place.',
  );
  const address = Address(
    id: 'home',
    userId: 'customer',
    label: 'Family home and weekend delivery address',
    recipientName: 'Long recipient name',
    phone: '+65 8888 9999',
    line1: '123 Example Road',
    postalCode: '123456',
    isDefault: true,
  );
  for (final dark in [false, true]) {
    final theme = dark ? AppTheme.dark : AppTheme.light;
    final suffix = dark ? 'dark-large' : 'light';
    // Flutter's test-only default font is Ahem for chip styles with no
    // explicit family. Map those capture styles to the app's installed face.
    final captureTheme = theme.copyWith(
      chipTheme: theme.chipTheme.copyWith(
        labelStyle: theme.chipTheme.labelStyle?.copyWith(
          fontFamily: '.SF Pro Text',
        ),
        secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
          fontFamily: '.SF Pro Text',
        ),
      ),
    );
    for (final pageName in [
      'faq',
      'customer-profile',
      'more-menu',
      'review-reply',
      'settings',
      'shop',
      'product-detail',
      'checkout',
    ]) {
      testWidgets('capture $pageName $suffix', (tester) async {
        tester.view.physicalSize = dark
            ? const Size(320, 900)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final Widget page = switch (pageName) {
          'faq' => const FaqScreen(),
          'customer-profile' => const AdminCustomerProfileScreen(
            userId: 'customer',
          ),
          'more-menu' => Scaffold(
            body: AdminMoreMenu(selectedIndex: 3, onSelected: (_) {}),
          ),
          'review-reply' => const AdminReviewsScreen(),
          'settings' => const AdminSettingsScreen(),
          'shop' => const ShopScreen(),
          'product-detail' => const ProductDetailScreen(productId: 'food'),
          'checkout' => const CheckoutScreen(
            buyNowItems: [CartItem(product: product, quantity: 2)],
          ),
          _ => throw StateError(pageName),
        };
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('ui-page-capture'),
            child: ProviderScope(
              overrides: [
                isLoggedInProvider.overrideWithValue(true),
                currentUserIdProvider.overrideWithValue('customer'),
                cartProvider.overrideWith(_CaptureCart.new),
                wishlistProductIdsProvider.overrideWith(_CaptureWishlist.new),
                unreadNotificationCountProvider.overrideWithValue(0),
                shopSettingsProvider.overrideWith(
                  (ref) async => {
                    'shop_phone': '+65 8888 9999',
                    'delivery_fee': 0,
                    'gst_registered': false,
                  },
                ),
                productListProvider.overrideWith(
                  (ref) async => [product, product],
                ),
                productDetailProvider('food')
                    .overrideWith((ref) async => product),
                relatedProductsProvider((
                  id: 'food',
                  category: product.category,
                )).overrideWith((ref) async => []),
                productReviewsProvider('food').overrideWith((ref) async => []),
                adminReviewsPagedProvider.overrideWith(_LoadedReviews.new),
                customerProfileProvider('customer').overrideWith(
                  (ref) async => const AppUser(
                    id: 'customer',
                    fullName: 'Customer with a long display name',
                    email: 'customer@example.com',
                  ),
                ),
                customerAddressesProvider('customer')
                    .overrideWith((ref) async => [address]),
                customerOrdersProvider('customer').overrideWith(
                  (ref) async => [
                    Order(
                      id: '12345678-abcd',
                      userId: 'customer',
                      status: OrderStatus.paid,
                      total: 12345.67,
                      createdAt: DateTime(2026, 10, 23),
                    ),
                  ],
                ),
                myAddressesProvider.overrideWith((ref) async => [address]),
                checkoutShippingQuoteProvider.overrideWith(
                  (ref, key) async => fixtureShippingQuote(key),
                ),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: captureTheme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(dark ? 2 : 1)),
                  child: child!,
                ),
                home: page,
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/images/logo.png'),
            tester.element(find.byType(MaterialApp)),
          ),
        );
        await tester.pumpAndSettle();
        if (pageName == 'faq') {
          await tester.tap(find.text('Where do you deliver?'));
          await tester.pumpAndSettle();
        }
        if (pageName == 'review-reply') {
          await tester.tap(find.text('Reply'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Post Reply'));
          await tester.pumpAndSettle();
        }
        await _savePageCapture(tester, '$pageName-$suffix');
        if (pageName == 'customer-profile') {
          await tester.ensureVisible(find.text(r'S$12345.67'));
          await tester.pumpAndSettle();
          await _savePageCapture(tester, '$pageName-orders-$suffix');
        }
        if (pageName == 'settings') {
          await tester.scrollUntilVisible(
            find.text('EASYPARCEL INTEGRATION'),
            150,
            maxScrolls: 100,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await _savePageCapture(tester, '$pageName-connection-$suffix');
        }
        if (pageName == 'checkout') {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -550),
          );
          await tester.pumpAndSettle();
          await _savePageCapture(tester, '$pageName-summary-$suffix');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Future<void> _savePageCapture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('ui-page-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ImageByteFormat.png);
    final dir = Directory('output/ui-page-review')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

class _CaptureCart extends CartNotifier {
  @override
  List<CartItem> build() => [];
}

class _CaptureWishlist extends WishlistIdsNotifier {
  @override
  AsyncValue<Set<String>> build() => const AsyncData({});
}
