import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/products/admin_products_screen.dart';
import 'package:marugen_app/features/admin/dashboard/admin_dashboard_screen.dart';
import 'package:marugen_app/features/admin/payments/admin_payments_screen.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/orders/presentation/order_success_screen.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/reviews/presentation/review_providers.dart';
import 'package:marugen_app/features/shop/presentation/product_detail_screen.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:marugen_app/shared/providers/paged_notifier.dart';
import 'package:marugen_app/shared/widgets/product_card.dart';

final product = Product.fromMap({
  'id': 'p',
  'name': 'Premium koi food with colour enhancing nutrients',
  'category': 'fish_food',
  'price': 118.80,
  'stock_quantity': 10,
});

void viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget app(Widget child, double scale, Brightness brightness) => MaterialApp(
  theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);

void main() {
  for (final width in [320.0, 360.0, 390.0, 820.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('paged admin grid fits width $width at text scale $scale', (
        tester,
      ) async {
        viewport(tester, Size(width, 900));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              adminProductsPagedProvider.overrideWith(_LoadedProducts.new),
              isLoggedInProvider.overrideWithValue(false),
              shopSettingsProvider.overrideWith((ref) async => {}),
            ],
            child: app(const AdminProductsScreen(), scale, Brightness.light),
          ),
        );
        await tester.pumpAndSettle();
        final cards = find.byType(ProductCard);
        expect(cards, findsWidgets);
        if (width == 360 || width == 390) {
          if (scale == 1) {
            expect(
              tester.getTopLeft(cards.at(0)).dy,
              tester.getTopLeft(cards.at(1)).dy,
            );
          } else {
            expect(tester.getSize(cards.first).width, greaterThan(300));
          }
        }
        if (width == 820) {
          expect(tester.getSize(cards.first).width, lessThanOrEqualTo(300));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'admin products fit large text on compact phone in $brightness',
      (tester) async {
        viewport(tester, const Size(360, 800));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              adminProductSearchQueryProvider.overrideWith((ref) => 'premium'),
              productListProvider.overrideWith(
                (ref) async => [product, product],
              ),
              isLoggedInProvider.overrideWithValue(false),
              shopSettingsProvider.overrideWith((ref) async => {}),
            ],
            child: app(const AdminProductsScreen(), 2, brightness),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final cards = find.byType(ProductCard);
        expect(tester.getSize(cards.first).width, greaterThan(300));
      },
    );

    testWidgets(
      'order confirmation remains scrollable on compact phone in $brightness',
      (tester) async {
        viewport(tester, const Size(360, 600));
        final order = Order(
          id: '12345678-abcd',
          userId: 'u',
          status: OrderStatus.paid,
          total: 12345.67,
          createdAt: DateTime(2026, 10, 11),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              orderByIdProvider(order.id).overrideWith((ref) async => order),
            ],
            child: app(OrderSuccessScreen(orderId: order.id), 2, brightness),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('Continue Shopping'), 200);
        expect(find.text('Continue Shopping').hitTestable(), findsOneWidget);
        expect(find.text(r'S$12345.67'), findsOneWidget);
      },
    );

    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'recommended product cards fit their carousel at $scale in $brightness',
        (tester) async {
          viewport(tester, const Size(360, 800));
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                productDetailProvider('p').overrideWith((ref) async => product),
                relatedProductsProvider((id: 'p', category: product.category))
                    .overrideWith((ref) async => [product]),
                productReviewsProvider('p').overrideWith((ref) async => []),
                isLoggedInProvider.overrideWithValue(false),
                shopSettingsProvider.overrideWith((ref) async => {}),
              ],
              child: app(
                const ProductDetailScreen(productId: 'p'),
                scale,
                brightness,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Recommended for you').last,
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(ProductCard), findsOneWidget);
        },
      );
    }
    for (final screen in [
      const AdminDashboardScreen(),
      const Scaffold(body: AdminPaymentsPane()),
    ]) {
      testWidgets(
        '${screen is Scaffold ? 'AdminPaymentsPane' : 'AdminDashboardScreen'} handles large text in $brightness',
        (tester) async {
          viewport(tester, const Size(360, 800));
          final order = Order(
            id: '12345678-abcd',
            userId: 'u',
            status: OrderStatus.paid,
            total: 12345.67,
            stripePaymentIntentId: 'test-layout',
            createdAt: DateTime(2026, 10, 11),
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                productListProvider.overrideWith((ref) async => [product]),
                adminOrdersProvider.overrideWith((ref) async => [order]),
                shopSettingsProvider.overrideWith((ref) async => {}),
                unreadNotificationCountProvider.overrideWith((ref) => 0),
              ],
              child: app(screen, 2, brightness),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

class _LoadedProducts extends AdminProductsPagedNotifier {
  @override
  AsyncValue<PagedListState<Product>> build() => AsyncData(
    PagedListState(items: [product, product, product, product], hasMore: false),
  );
}
