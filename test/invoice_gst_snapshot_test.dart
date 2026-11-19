import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/orders/utils/invoice_pdf.dart';
import 'package:marugen_app/shared/models/order.dart';

Map<String, dynamic> orderRow(Map<String, dynamic> extra) => {
  'id': 'order-12345678',
  'user_id': 'buyer',
  'status': 'paid',
  'total': 112.0,
  'buyer_shipping_cents': 300,
  'created_at': '2026-11-01T00:00:00Z',
  ...extra,
};

void main() {
  test('an order carries the GST the server charged at checkout', () {
    final order = Order.fromMap(
      orderRow({
        'gst_percent': 8.5,
        'gst_included_in_price': false,
        'gst_amount_cents': 854,
      }),
    );
    expect(order.hasGstSnapshot, isTrue);
    expect(order.gstPercent, 8.5);
    expect(order.gstIncludedInPrice, isFalse);
    expect(order.gstAmountCents, 854);

    final legacy = Order.fromMap(orderRow({}));
    expect(legacy.hasGstSnapshot, isFalse);
    expect(legacy.gstPercent, isNull);
  });

  test('changing the GST setting does not restate a past invoice', () {
    final order = Order.fromMap(
      orderRow({
        'gst_percent': 8,
        'gst_included_in_price': true,
        'gst_amount_cents': 807,
      }),
    );
    // The shop has since moved to 9%, added on top.
    final gst = invoiceGst(
      order: order,
      settings: {'gst_percent': 9, 'gst_included_in_price': false},
    );
    expect(gst.percent, 8);
    expect(gst.amount, 8.07);
    expect(gst.included, isTrue);
    expect(gst.label, 'GST included in items (8%)');
  });

  test('GST added on top is labelled as added, with its exact rate', () {
    final gst = invoiceGst(
      order: Order.fromMap(
        orderRow({
          'gst_percent': 8.5,
          'gst_included_in_price': false,
          'gst_amount_cents': 854,
        }),
      ),
      settings: const {},
    );
    expect(gst.amount, 8.54);
    expect(gst.label, 'GST added to items (8.5%)');
  });

  test('an order from before the snapshot keeps the previous calculation', () {
    final gst = invoiceGst(
      order: Order.fromMap(orderRow({})),
      settings: {'gst_percent': 9},
    );
    // Merchandise is the total less the buyer's delivery share: 109.00.
    expect(gst.percent, 9);
    expect(gst.amount, closeTo(109 - 109 / 1.09, 1e-9));
    expect(gst.label, 'GST included in items (9%)');
    expect(
      invoiceGst(order: Order.fromMap(orderRow({})), settings: const {}).amount,
      0,
    );
  });
}
