import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/features/auth/data/auth_repository.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/data/payment_repository.dart';
import 'package:marugen_app/features/orders/presentation/checkout_screen.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/orders/presentation/shipping_quote_providers.dart';
import 'package:marugen_app/features/profile/presentation/address_providers.dart';
import 'package:marugen_app/features/promo/data/promo_repository.dart';
import 'package:marugen_app/features/promo/presentation/promo_providers.dart';
import 'package:marugen_app/features/shop/data/product_repository.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/address.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/models/promo_code.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shipping_test_fixtures.dart';

const address = Address(
  id: 'address',
  userId: 'a',
  recipientName: 'Customer',
  phone: '81234567',
  line1: '1 Street',
  postalCode: '123456',
);

Product food(double price) => Product(
  id: 'food',
  name: 'Fish food',
  category: ProductCategory.accessories,
  price: price,
  stockQuantity: 10,
);

/// The shop as the server sees it right now. The app's copy goes stale
/// whenever a test changes it.
class Shop {
  Map<String, dynamic> settings = {
    'gst_percent': 9,
    'gst_included_in_price': true,
  };
  double price = 10;
  PromoCode? promo;

  /// What create-payment-intent would charge for two units, in cents,
  /// delivery (S$2.02 buyer share in the fixture quote) included.
  int get amountCents {
    final subtotal = (price * 2 * 100).round();
    final net = subtotal - ((promo?.discountFor(price * 2) ?? 0) * 100).round();
    final added = settings['gst_included_in_price'] == true
        ? 0
        : (net * (settings['gst_percent'] as num) / 100).round();
    return net + added + 202;
  }
}

class Payments implements PaymentRepository {
  Payments(this.shop);
  final Shop shop;
  final promoCodes = <String?>[];

  @override
  Future<Map<String, dynamic>> createPaymentIntent({
    required List<Map<String, dynamic>> items,
    Map<String, dynamic>? shippingAddress,
    String currency = 'sgd',
    String? promoCode,
    String? shippingQuoteId,
    String? idempotencyKey,
    String? customerRemarks,
    int customerRemarksRevision = 0,
  }) async {
    promoCodes.add(promoCode);
    return {
      'orderId': 'order-${promoCodes.length}',
      'amountCents': shop.amountCents,
      'currency': 'sgd',
      // Already settled, so no payment sheet is needed in a test.
      'paymentStatus': 'paid',
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A first answer that is still awaiting payment, so the amount is checked.
class UnpaidFirst extends Payments {
  UnpaidFirst(super.shop);

  @override
  Future<Map<String, dynamic>> createPaymentIntent({
    required List<Map<String, dynamic>> items,
    Map<String, dynamic>? shippingAddress,
    String currency = 'sgd',
    String? promoCode,
    String? shippingQuoteId,
    String? idempotencyKey,
    String? customerRemarks,
    int customerRemarksRevision = 0,
  }) async {
    final intent = await super.createPaymentIntent(
      items: items,
      promoCode: promoCode,
    );
    if (promoCodes.length == 1) {
      intent
        ..remove('paymentStatus')
        ..['clientSecret'] = 'secret';
    }
    return intent;
  }
}

class Orders implements OrderRepository {
  final cancelled = <String>[];
  var adminListFetches = 0;

  @override
  Future<void> cancelMyOrder(String orderId) async => cancelled.add(orderId);

  @override
  Future<Order?> fetchOrderById(String id) async => Order(
    id: id,
    userId: 'a',
    status: OrderStatus.paid,
    total: 0,
    createdAt: DateTime.utc(2026, 11, 1),
  );

  @override
  Future<List<Order>> fetchMyOrders() async => [];

  @override
  Future<List<Order>> fetchAllOrdersPage({
    OrderStatus? status,
    required int offset,
    required int limit,
  }) async {
    adminListFetches++;
    return [];
  }

  @override
  Future<List<Order>> fetchAllOrders({OrderStatus? status}) async {
    adminListFetches++;
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Catalogue implements ProductRepository {
  Catalogue(this.shop);
  final Shop shop;

  @override
  Future<Product?> fetchProductById(String id) async => food(shop.price);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Promos implements PromoRepository {
  Promos(this.shop);
  final Shop shop;

  @override
  Future<PromoCode?> lookupCode(String code) async => shop.promo;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class VerifiedAuth implements AuthRepository {
  @override
  bool get isEmailVerified => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const changedMessage =
    'Checkout total changed. Review your order before paying.';

void main() {
  late Shop shop;
  late Orders orders;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    shop = Shop();
    orders = Orders();
  });

  Future<void> showCheckout(
    WidgetTester tester,
    Payments payments, {
    UserRole role = UserRole.customer,
  }) async {
    tester.view.physicalSize = const Size(500, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => CheckoutScreen(
            buyNowItems: [CartItem(product: food(10), quantity: 2)],
          ),
        ),
        GoRoute(
          path: '/orders/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Placed ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('a'),
          currentAppUserProvider.overrideWith(
            (ref) async => AppUser(id: 'a', role: role),
          ),
          shopSettingsProvider.overrideWith(
            (ref) async => Map<String, dynamic>.of(shop.settings),
          ),
          myAddressesProvider.overrideWith((ref) async => const [address]),
          checkoutShippingQuoteProvider.overrideWith(
            (ref, key) async => fixtureShippingQuote(key),
          ),
          paymentRepositoryProvider.overrideWithValue(payments),
          orderRepositoryProvider.overrideWithValue(orders),
          productRepositoryProvider.overrideWithValue(Catalogue(shop)),
          promoRepositoryProvider.overrideWithValue(Promos(shop)),
          authRepositoryProvider.overrideWithValue(VerifiedAuth()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    // The signed-in profile is loaded by the app's router long before
    // anyone reaches checkout.
    ProviderScope.containerOf(tester.element(find.byType(CheckoutScreen)))
        .listen(currentAppUserProvider, (_, _) {});
    await tester.pumpAndSettle();
  }

  Future<void> tapPay(WidgetTester tester) async {
    await tester.tap(find.textContaining('with Stripe'));
    // The confirmation poll and the route change, without waiting forever.
    await tester.pumpAndSettle();
  }

  testWidgets('after the shop changes how GST is charged, the second Pay '
      'tap goes through without leaving checkout', (tester) async {
    final payments = UnpaidFirst(shop);
    await showCheckout(tester, payments);
    expect(find.textContaining('22.02 with Stripe'), findsOneWidget);

    // GST is now added on top; this screen still holds the old setting.
    shop.settings = {'gst_percent': 9, 'gst_included_in_price': false};
    await tapPay(tester);
    expect(orders.cancelled, ['order-1']);
    expect(find.text(changedMessage), findsOneWidget);
    // The new total is on screen, on the same checkout.
    expect(find.textContaining('23.82 with Stripe'), findsOneWidget);
    expect(find.textContaining('Placed'), findsNothing);

    await tapPay(tester);
    expect(find.text('Placed order-2'), findsOneWidget);
    expect(orders.cancelled, ['order-1']);
  });

  testWidgets('a changed price and an ended promo code are both refreshed', (
    tester,
  ) async {
    const save10 = PromoCode(
      id: 'p1',
      code: 'SAVE10',
      discountType: DiscountType.percent,
      discountValue: 10,
      active: true,
    );
    shop.promo = save10;
    final payments = UnpaidFirst(shop);
    await showCheckout(tester, payments);
    await tester.enterText(find.byKey(const ValueKey('promo-code')), 'SAVE10');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.textContaining('20.02 with Stripe'), findsOneWidget);

    // Since the page loaded: the price went up and the code was switched off.
    shop
      ..price = 12
      ..promo = null;
    await tapPay(tester);
    expect(find.text(changedMessage), findsOneWidget);
    expect(find.text('This promo code can no longer be used.'), findsOneWidget);
    expect(find.textContaining('26.02 with Stripe'), findsOneWidget);

    await tapPay(tester);
    expect(find.text('Placed order-2'), findsOneWidget);
    expect(payments.promoCodes, ['SAVE10', null]);
  });

  testWidgets('a customer\'s purchase does not start the admin order lists', (
    tester,
  ) async {
    await showCheckout(tester, Payments(shop));
    await tapPay(tester);
    expect(find.text('Placed order-1'), findsOneWidget);
    expect(orders.adminListFetches, 0);
  });

  testWidgets('staff buying on their own account still refresh them', (
    tester,
  ) async {
    await showCheckout(tester, Payments(shop), role: UserRole.staff);
    await tapPay(tester);
    expect(find.text('Placed order-1'), findsOneWidget);
    expect(orders.adminListFetches, greaterThan(0));
  });
}
