import 'shipping_test_fixtures.dart';

import 'package:marugen_app/features/orders/presentation/shipping_quote_providers.dart';
import 'package:marugen_app/features/orders/domain/shipping_quote.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/orders/presentation/checkout_screen.dart';
import 'package:marugen_app/features/orders/presentation/purchase_intent.dart';
import 'package:marugen_app/features/profile/presentation/address_providers.dart';
import 'package:marugen_app/shared/models/address.dart';
import 'package:marugen_app/shared/models/promo_code.dart';
import 'package:marugen_app/features/promo/data/promo_repository.dart';
import 'package:marugen_app/features/promo/presentation/promo_providers.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';

ShippingQuote testShippingQuote() => ShippingQuote(
  quoteId: 'checkout-test-quote',
  expiresAt: DateTime.utc(2099),
  fulfillmentMethod: 'courier',
  carrierName: 'TracX Logis',
  totalShippingCents: 0,
  buyerShippingCents: 0,
  sellerShippingCents: 0,
  policy: 'shared_50_50',
  sourceCurrency: 'SGD',
  sourceAmount: 0,
  fxRate: 1,
);

final checkoutUserProvider = StateProvider<String?>((ref) => 'a');

const selectedItem = CartItem(
  product: Product(
    id: 'selected',
    name: 'Fish food',
    category: ProductCategory.accessories,
    price: 10,
  ),
  quantity: 2,
);
const address = Address(
  id: 'address',
  userId: 'a',
  recipientName: 'Customer',
  phone: '12345678',
  line1: '1 Street',
  postalCode: '123456',
);

Future<void> showCheckout(
  WidgetTester tester,
  Future<Map<String, dynamic>> settings, {
  PromoRepository? promoRepository,
  double textScale = 1,
  ThemeData? theme,
  List<CartItem> items = const [selectedItem],
  Future<ShippingQuote> Function(String)? quoteLoader,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWith(
          (ref) => ref.watch(checkoutUserProvider),
        ),
        if (promoRepository != null)
          promoRepositoryProvider.overrideWithValue(promoRepository),
        shopSettingsProvider.overrideWith((ref) => settings),
        myAddressesProvider.overrideWith((ref) async => [address]),
        checkoutShippingQuoteProvider.overrideWith(
          (ref, key) async => quoteLoader == null
              ? fixtureShippingQuote(key)
              : quoteLoader(key),
        ),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: CheckoutScreen(buyNowItems: items),
      ),
    ),
  );
  await tester.pump();
}

class PendingPromoRepository implements PromoRepository {
  final Completer<PromoCode?> result = Completer<PromoCode?>();
  @override
  Future<PromoCode?> lookupCode(String code) => result.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('payment waits for shipping and includes only buyer share once', (
    tester,
  ) async {
    final quote = Completer<ShippingQuote>();
    String? request;
    await showCheckout(
      tester,
      Future.value({'gst_percent': 9, 'gst_included_in_price': true}),
      quoteLoader: (key) {
        request = key;
        return quote.future;
      },
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    quote.complete(fixtureShippingQuote(request!));
    await tester.pumpAndSettle();
    expect(find.textContaining('22.02 with Stripe'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });
  testWidgets(
    'failed shipping offers retry without misleading calculating totals',
    (tester) async {
      var attempts = 0;
      await showCheckout(
        tester,
        Future.value({'gst_percent': 9, 'gst_included_in_price': true}),
        quoteLoader: (key) async {
          if (++attempts == 1) throw Exception('No TracX service available');
          return fixtureShippingQuote(key);
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry delivery'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Subtotal'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Calculating…'), findsNothing);
      expect(find.text('Waiting for shipping'), findsNothing);
      expect(find.text('Delivery unavailable'), findsOneWidget);
      await tester.tap(find.text('Retry delivery'));
      await tester.pumpAndSettle();
      expect(find.textContaining('22.02 with Stripe'), findsOneWidget);
    },
  );
  testWidgets('expired shipping cannot enable payment', (tester) async {
    await showCheckout(
      tester,
      Future.value({'gst_percent': 9, 'gst_included_in_price': true}),
      quoteLoader: (key) async {
        final q = fixtureShippingQuote(key);
        return ShippingQuote(
          quoteId: q.quoteId,
          expiresAt: DateTime(2020),
          fulfillmentMethod: q.fulfillmentMethod,
          carrierName: q.carrierName,
          totalShippingCents: q.totalShippingCents,
          buyerShippingCents: q.buyerShippingCents,
          sellerShippingCents: q.sellerShippingCents,
          policy: q.policy,
          sourceCurrency: q.sourceCurrency,
          sourceAmount: q.sourceAmount,
          fxRate: q.fxRate,
        );
      },
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
  });

  testWidgets('checkout states courier method cost and configured lead time', (
    tester,
  ) async {
    await showCheckout(
      tester,
      Future.value({
        'gst_percent': 9,
        'gst_included_in_price': true,
        'delivery_lead_days_min': 3,
        'delivery_lead_days_max': 6,
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Courier delivery'), findsNothing);
    expect(find.textContaining('Estimated arrival:'), findsOneWidget);
    expect(find.textContaining('50%'), findsNothing);
    expect(find.textContaining('TracX Logis'), findsNothing);
    expect(find.textContaining('Total delivery:'), findsNothing);
  });
  testWidgets('mixed live-fish checkout promises one arranged shop delivery', (
    tester,
  ) async {
    await showCheckout(
      tester,
      Future.value({'gst_percent': 9, 'gst_included_in_price': true}),
      items: const [
        selectedItem,
        CartItem(
          product: Product(
            id: 'koi',
            name: 'Koi',
            category: ProductCategory.koi,
            price: 100,
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Shop delivery'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('arrange the delivery time'), findsOneWidget);
    expect(find.textContaining('arrive together'), findsOneWidget);
    expect(find.text('Courier delivery'), findsNothing);
  });

  testWidgets('checkout remains readable on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showCheckout(
      tester,
      Future.value({'gst_percent': 9, 'gst_included_in_price': true}),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Total (incl. GST)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });
  testWidgets('checkout hides former account selection after account changes', (
    tester,
  ) async {
    await showCheckout(
      tester,
      Future.value({'gst_percent': 9, 'gst_included_in_price': true}),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CheckoutScreen)),
    );
    container.read(checkoutUserProvider.notifier).state = 'b';
    await tester.pumpAndSettle();
    expect(find.text('Fish food'), findsNothing);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
  });
  testWidgets(
    'token selection mounts and is consumed without account cart fallback',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('a'),
          checkoutShippingQuoteProvider.overrideWith(
            (ref, key) async => testShippingQuote(),
          ),
          shopSettingsProvider.overrideWith(
            (ref) async => {'gst_percent': 9, 'gst_included_in_price': true},
          ),
          myAddressesProvider.overrideWith((ref) async => [address]),
          checkoutShippingQuoteProvider.overrideWith(
            (ref, key) async => fixtureShippingQuote(key),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(purchaseIntentProvider.notifier);
      final token = notifier.start([selectedItem]);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: CheckoutScreen(purchaseIntentId: token)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('22.02 with Stripe'), findsOneWidget);
      expect(container.read(purchaseIntentProvider), isNull);
      expect(notifier.consume(token), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('payment is disabled throughout promo validation', (
    tester,
  ) async {
    final repo = PendingPromoRepository();
    await showCheckout(
      tester,
      Future.value({'gst_percent': 9, 'gst_included_in_price': true}),
      promoRepository: repo,
    );
    await tester.pumpAndSettle();
    final promoField = find.byKey(const ValueKey('promo-code'));
    await tester.scrollUntilVisible(
      promoField,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(promoField, 'SAVE');
    await tester.ensureVisible(find.text('Apply'));
    await tester.tap(find.text('Apply'));
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    expect(tester.widget<TextField>(promoField).enabled, isFalse);
    repo.result.complete(null);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });
  testWidgets(
    'payment stays disabled until totals are loaded then shows tax-inclusive amount',
    (tester) async {
      final settings = Completer<Map<String, dynamic>>();
      await showCheckout(tester, settings.future);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      settings.complete({'gst_percent': 9, 'gst_included_in_price': false});
      await tester.pumpAndSettle();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull,
      );
      expect(find.textContaining('23.82 with Stripe'), findsOneWidget);
    },
  );
  testWidgets(
    'failed totals cannot enable payment even with items and address',
    (tester) async {
      final settings = Completer<Map<String, dynamic>>();
      await showCheckout(tester, settings.future);
      settings.completeError(Exception('unavailable'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.text('Retry'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Retry'), findsOneWidget);
    },
  );
  testWidgets('isolated item removal can be undone without losing quantity', (
    tester,
  ) async {
    await showCheckout(
      tester,
      Future.value({'gst_percent': 9, 'gst_included_in_price': true}),
    );
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    expect(find.textContaining('22.02 with Stripe'), findsOneWidget);
  });
}
