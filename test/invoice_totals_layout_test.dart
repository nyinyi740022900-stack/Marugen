// Page review 22 Nov 2026: the invoice's totals read as a sum (discount and
// GST are notes, not rows), a 0% rate prints no GST line, and a hand-
// delivered order's packing label has no courier wording.
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/orders/utils/invoice_pdf.dart';
import 'package:marugen_app/features/orders/utils/packing_slip_pdf.dart';
import 'package:marugen_app/shared/models/order.dart';

Order _order([Map<String, dynamic> extra = const {}]) => Order.fromMap({
  'id': 'order-12345678',
  'order_number': 'ORD-9',
  'user_id': 'buyer',
  'status': 'paid',
  'total': 112.0,
  'buyer_shipping_cents': 300,
  'seller_shipping_cents': 300,
  'shipping_quote_id': 'quote-1',
  'shipping_cost_policy': 'shared_50_50',
  'discount_amount': 10,
  'promo_code': 'SAVE10',
  'gst_percent': 9,
  'gst_included_in_price': true,
  'gst_amount_cents': 900,
  'created_at': '2026-11-01T00:00:00Z',
  ...extra,
});

void main() {
  group('invoice totals', () {
    test('the amount rows add up to the total; discount, GST and the '
        "shop's delivery share are notes", () {
      final order = _order();
      final lines = invoiceTotalLines(order: order, settings: const {});
      expect(
        [for (final l in lines) (l.label, l.amount)],
        [
          ('Items after discount (incl. GST)', 109.0),
          ('after S\$10.00 discount (SAVE10)', null),
          ('of which GST included in items (9%): S\$9.00', null),
          ('Delivery - buyer share', 3.0),
          ('the shop pays a further S\$3.00 of delivery', null),
        ],
      );
      final sum = lines
          .where((l) => !l.note)
          .fold<double>(0, (total, l) => total + l.amount!);
      expect(sum, order.total);
      // Nothing that is not added up sits in the amount column, and no
      // line subtracts.
      expect(lines.where((l) => l.note).every((l) => l.amount == null), isTrue);
      expect(lines.any((l) => l.label.contains('-S\$')), isFalse);
    });

    test('a 0% rate prints no GST line and no "incl. GST"', () {
      final lines = invoiceTotalLines(
        order: _order({
          'gst_percent': 0,
          'gst_amount_cents': 0,
          'discount_amount': null,
          'promo_code': null,
        }),
        settings: const {'gst_percent': 9},
      );
      expect(lines.any((l) => l.label.contains('GST')), isFalse);
      expect(lines.first.label, 'Items');
    });

    test('an order with no snapshot and no GST setting has no GST line', () {
      final lines = invoiceTotalLines(
        order: _order({
          'gst_percent': null,
          'gst_included_in_price': null,
          'gst_amount_cents': null,
        }),
        settings: const {},
      );
      expect(lines.any((l) => l.label.contains('GST')), isFalse);
    });

    test('the invoice still builds', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final bytes = await buildInvoicePdf(order: _order(), settings: const {});
      expect(bytes.length, greaterThan(1000));
    });
  });

  group('packing label', () {
    test('a hand-delivered order says HAND DELIVERY, with no courier or '
        'AWB wording', () {
      final copy = packingLabelCopy(
        _order({'fulfillment_method': 'shop_delivery'}),
      );
      expect(copy.heading, 'HAND DELIVERY');
      expect(copy.reference, 'ORD-9');
      expect(copy.footerNote, isNull);
      expect(copy.showBarcode, isFalse);
    });

    test('a courier order keeps its booking state and AWB reminder', () {
      final unbooked = packingLabelCopy(
        _order({'fulfillment_method': 'courier'}),
      );
      expect(unbooked.heading, 'ORDER REFERENCE - NOT BOOKED');
      expect(unbooked.footerNote, 'Attach official courier AWB separately.');

      final booked = packingLabelCopy(
        _order({'fulfillment_method': 'courier', 'qxpress_tracking_no': 'AWB123'}),
      );
      expect(booked.heading, 'TRACKING NUMBER');
      expect(booked.reference, 'AWB123');
      expect(booked.showBarcode, isTrue);
    });

    test('both labels still build', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      for (final method in ['shop_delivery', 'courier']) {
        final bytes = await buildPackingSlipPdf(
          _order({'fulfillment_method': method}),
        );
        expect(bytes.length, greaterThan(1000));
      }
    });
  });
}
