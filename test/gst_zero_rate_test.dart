// The shop is not GST-registered: at a 0% rate nothing a customer or staff
// member reads may say "GST" or "tax invoice". An order that was charged
// GST (a 9% snapshot from before the change) keeps its own GST wording.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/cart/presentation/cart_screen.dart';
import 'package:marugen_app/features/legal/terms_screen.dart';
import 'package:marugen_app/features/orders/utils/checkout_totals.dart';
import 'package:marugen_app/features/orders/utils/invoice_pdf.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';

import 'checkout_safety_test.dart' as checkout;
import 'order_page_review_fixes_test.dart' as order_page;

const zeroRate = <String, dynamic>{
  'gst_percent': 0,
  'gst_included_in_price': true,
};
const nineRate = <String, dynamic>{
  'gst_percent': 9,
  'gst_included_in_price': true,
};

class _Cart extends CartNotifier {
  _Cart(this.items);
  final List<CartItem> items;

  @override
  List<CartItem> build() => items;

  @override
  Future<CartRefreshResult> refreshFromServer() async =>
      CartRefreshResult(removed: 0, adjusted: 0, isEmpty: items.isEmpty);
}

Order invoiceOrder([Map<String, dynamic> extra = const {}]) => Order.fromMap({
  'id': 'order-12345678',
  'order_number': 'ORD-9',
  'user_id': 'buyer',
  'status': 'paid',
  'total': 112.0,
  'buyer_shipping_cents': 300,
  'shipping_quote_id': 'quote-1',
  'created_at': '2026-11-01T00:00:00Z',
  ...extra,
});

/// Every string on screen, for "the word is nowhere" assertions.
String allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text, skipOffstage: false))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  group('at 0% GST', () {
    testWidgets('the cart says nothing about GST', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue(null),
            cartProvider.overrideWith(
              () => _Cart(const [
                CartItem(
                  product: Product(
                    id: 'food',
                    name: 'Koi Food',
                    category: ProductCategory.fishFood,
                    price: 12,
                    stockQuantity: 10,
                  ),
                  quantity: 1,
                ),
              ]),
            ),
            shopSettingsProvider.overrideWith((ref) async => zeroRate),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const CartScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delivery is calculated at checkout.'), findsOneWidget);
      expect(allText(tester), isNot(contains('GST')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('checkout totals read "Total" and never mention GST', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await checkout.showCheckout(tester, Future.value(zeroRate));
      await tester.pumpAndSettle();
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Total (incl. GST)'), findsNothing);
      expect(allText(tester), isNot(contains('GST')));
      expect(tester.takeException(), isNull);
    });

    test('the total label names GST only for a rate above 0 inside the '
        'prices', () {
      expect(checkoutTotalLabel(gstPercent: 0, gstIncluded: true), 'Total');
      expect(checkoutTotalLabel(gstPercent: 0, gstIncluded: false), 'Total');
      expect(
        checkoutTotalLabel(gstPercent: 9, gstIncluded: true),
        'Total (incl. GST)',
      );
      expect(checkoutTotalLabel(gstPercent: 9, gstIncluded: false), 'Total');
    });

    testWidgets('an order with a 0% snapshot shows no GST on its page', (
      tester,
    ) async {
      final container = order_page.containerFor(
        order_page.Server(
          order_page.order(
            OrderStatus.paid,
            gstPercent: 0,
            gstIncluded: true,
            gstCents: 0,
          ),
        ),
        // The shop's rate today is irrelevant to an order with a snapshot.
        extra: [shopSettingsProvider.overrideWith((ref) async => nineRate)],
      );
      await order_page.openOrder(tester, container, reachedWithGo: false);
      expect(find.text('Total'), findsOneWidget);
      expect(allText(tester), isNot(contains('GST')));
    });

    test('the invoice is an INVOICE with no GST line', () {
      // Snapshot at 0%: the shop's current rate does not bring GST back.
      final snapshot = invoiceOrder({
        'gst_percent': 0,
        'gst_included_in_price': true,
        'gst_amount_cents': 0,
      });
      expect(invoiceTitle(order: snapshot, settings: nineRate), 'INVOICE');
      expect(
        invoiceTotalLines(
          order: snapshot,
          settings: nineRate,
        ).any((l) => l.label.contains('GST')),
        isFalse,
      );

      // No snapshot: the current setting applies.
      final legacy = invoiceOrder();
      expect(invoiceTitle(order: legacy, settings: zeroRate), 'INVOICE');
      expect(invoiceTitle(order: legacy, settings: const {}), 'INVOICE');
      final lines = invoiceTotalLines(order: legacy, settings: zeroRate);
      expect(lines.any((l) => l.label.contains('GST')), isFalse);
      expect(lines.first.label, 'Items');
    });

    test('the admin sales caption drops GST', () {
      expect(salesIncludesCaption(zeroRate), 'Includes delivery fees');
      // Not known yet: say nothing about GST rather than guess.
      expect(salesIncludesCaption(null), 'Includes delivery fees');
      expect(salesIncludesCaption(nineRate), 'Includes delivery fees and GST');
    });

    testWidgets('the Terms say no GST is charged', (tester) async {
      tester.view.physicalSize = const Size(390, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopSettingsProvider.overrideWith(
              (ref) async => {'gst_percent': 0, 'gst_included_in_price': true},
            ),
          ],
          child: const MaterialApp(home: TermsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final text = allText(tester);
      expect(
        text,
        contains(
          'All prices are shown in Singapore Dollars (SGD). Marugen Fish Farm '
          'is not GST-registered, so no GST is charged. Some products may be '
          'marked "Contact us for price" and require you to reach out to the '
          'shop directly. We reserve the right to correct pricing errors and '
          'to cancel or refuse an order at our discretion, for example when '
          'a product is no longer available.',
        ),
      );
      expect(text, isNot(contains('Goods and Services Tax')));
      expect(text, isNot(contains('where indicated')));
    });
  });

  group('an order charged 9% GST keeps its GST wording at a 0% setting', () {
    testWidgets('the order page still shows its GST note', (tester) async {
      final container = order_page.containerFor(
        order_page.Server(
          order_page.order(
            OrderStatus.paid,
            gstPercent: 9,
            gstIncluded: true,
            gstCents: 180,
          ),
        ),
        extra: [shopSettingsProvider.overrideWith((ref) async => zeroRate)],
      );
      await order_page.openOrder(tester, container, reachedWithGo: false);
      expect(find.text('Includes GST (9%) of S\$1.80'), findsOneWidget);
    });

    test('the invoice is a TAX INVOICE with its GST line', () async {
      final order = invoiceOrder({
        'gst_percent': 9,
        'gst_included_in_price': true,
        'gst_amount_cents': 900,
      });
      expect(invoiceTitle(order: order, settings: zeroRate), 'TAX INVOICE');
      expect(
        [
          for (final l in invoiceTotalLines(order: order, settings: zeroRate))
            l.label,
        ],
        [
          'Items (incl. GST)',
          'of which GST included in items (9%): S\$9.00',
          'Delivery - buyer share',
        ],
      );
      // An order with no snapshot follows a shop that does charge GST.
      expect(
        invoiceTitle(order: invoiceOrder(), settings: nineRate),
        'TAX INVOICE',
      );

      TestWidgetsFlutterBinding.ensureInitialized();
      for (final settings in [zeroRate, nineRate]) {
        final bytes = await buildInvoicePdf(order: order, settings: settings);
        expect(bytes.length, greaterThan(1000));
      }
    });
  });
}
