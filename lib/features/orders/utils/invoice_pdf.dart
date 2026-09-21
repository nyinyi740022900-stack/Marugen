import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../shared/models/order.dart';
import '../../../shared/providers/settings_providers.dart';

const _brandRed = PdfColor.fromInt(0xFFD31F16);
const _grey = PdfColor.fromInt(0xFF6B6B6B);
const _lightGrey = PdfColor.fromInt(0xFFE3E1DC);

/// Builds a proper tax-invoice PDF for [order] — shop letterhead, bill-to /
/// order-info columns, an itemised table, and a totals block (subtotal,
/// promo discount, GST, grand total). Used for both "Print Invoice" (admin)
/// and the customer's receipt-share action, so both sides see the exact
/// same document.
Future<Uint8List> buildInvoicePdf({
  required Order order,
  required Map<String, dynamic> settings,
}) async {
  final shopName = settings['shop_name'] as String? ?? 'Marugen Koi Farm';
  final shopPhone = settings['shop_phone'] as String?;
  final shopAddress = settings['shop_address'] as String?;
  final gstPercent = (settings['gst_percent'] as num?)?.toDouble() ?? 0;
  final gstIncluded = settings['gst_included_in_price'] as bool? ?? true;

  final discount = order.discountAmount ?? 0;
  final netTotal = order.total;
  final subtotalBeforeGst = gstIncluded ? netTotal / (1 + gstPercent / 100) : netTotal;
  final gstAmount = gstIncluded ? netTotal - subtotalBeforeGst : netTotal * gstPercent / 100;
  final grandTotal = gstIncluded ? netTotal : netTotal + gstAmount;

  final shipping = order.shippingAddress;
  final dateFmt = DateFormat.yMMMd().add_jm();

  final logoBytes = await rootBundle.load('assets/images/logo.png');
  final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());

  final doc = pw.Document();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // --- Letterhead ---------------------------------------------
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.ClipOval(
                      child: pw.SizedBox(
                        width: 44,
                        height: 44,
                        child: pw.Image(logo, fit: pw.BoxFit.cover),
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(shopName,
                            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                        if (shopAddress != null && shopAddress.isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 4),
                            child: pw.Text(shopAddress,
                                style: const pw.TextStyle(fontSize: 9.5, color: _grey)),
                          ),
                        if (shopPhone != null && shopPhone.isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 2),
                            child: pw.Text('Tel: $shopPhone',
                                style: const pw.TextStyle(fontSize: 9.5, color: _grey)),
                          ),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('TAX INVOICE',
                        style: pw.TextStyle(
                            fontSize: 16, fontWeight: pw.FontWeight.bold, color: _brandRed)),
                    pw.SizedBox(height: 4),
                    pw.Text('Invoice #: ${order.displayNumber}',
                        style: const pw.TextStyle(fontSize: 9.5)),
                    pw.Text('Date: ${dateFmt.format(order.createdAt)}',
                        style: const pw.TextStyle(fontSize: 9.5)),
                    pw.Text('Status: ${orderStatusLabel(order.status).toUpperCase()}',
                        style: const pw.TextStyle(fontSize: 9.5)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Divider(color: _lightGrey, thickness: 1),
            pw.SizedBox(height: 16),

            // --- Customer details ------------------------------------------
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _labelRow('Customer Name', (shipping?['recipient_name'] as String?) ?? '—'),
                if ((shipping?['phone'] as String?)?.isNotEmpty ?? false)
                  _labelRow('Phone Number', shipping!['phone'] as String),
                _labelRow(
                  'Address',
                  shipping == null
                      ? '—'
                      : [
                          shipping['line1'],
                          shipping['line2'],
                          shipping['city'],
                          shipping['postal_code'],
                        ].where((p) => p != null && (p as String).isNotEmpty).join(', '),
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            // --- Items table ----------------------------------------------
            pw.Table(
              border: const pw.TableBorder(
                bottom: pw.BorderSide(color: _lightGrey, width: 0.75),
                horizontalInside: pw.BorderSide(color: _lightGrey, width: 0.5),
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(4),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1.6),
                3: pw.FlexColumnWidth(1.6),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF4F2EE)),
                  children: [
                    _cell('ITEM', bold: true, pad: true),
                    _cell('QTY', bold: true, pad: true, align: pw.TextAlign.center),
                    _cell('UNIT PRICE', bold: true, pad: true, align: pw.TextAlign.right),
                    _cell('AMOUNT', bold: true, pad: true, align: pw.TextAlign.right),
                  ],
                ),
                for (final item in order.items)
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(item.productName, style: const pw.TextStyle(fontSize: 9.5)),
                            if (item.optionLabel != null)
                              pw.Text(item.optionLabel!,
                                  style: const pw.TextStyle(fontSize: 8, color: _grey)),
                          ],
                        ),
                      ),
                      _cell('${item.quantity}', pad: true, align: pw.TextAlign.center),
                      _cell(_money(item.unitPrice), pad: true, align: pw.TextAlign.right),
                      _cell(_money(item.subtotal), pad: true, align: pw.TextAlign.right),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 16),

            // --- Payment info (left) + Totals (right) -----------------------
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('PAYMENT',
                          style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: _grey,
                              letterSpacing: 0.8)),
                      pw.SizedBox(height: 4),
                      if (order.stripePaymentIntentId != null &&
                          order.stripePaymentIntentId!.isNotEmpty)
                        pw.Text('Ref: ${order.stripePaymentIntentId}',
                            style: const pw.TextStyle(fontSize: 9.5)),
                      if (order.promoCode != null)
                        pw.Text('Promo code: ${order.promoCode}',
                            style: const pw.TextStyle(fontSize: 9.5)),
                    ],
                  ),
                ),
                pw.SizedBox(
                  width: 220,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      _totalRow('Subtotal (excl. GST)', _money(subtotalBeforeGst)),
                      if (discount > 0)
                        _totalRow(
                          order.promoCode != null
                              ? 'Promo discount (${order.promoCode})'
                              : 'Promo discount',
                          '-${_money(discount)}',
                          color: _brandRed,
                        ),
                      _totalRow('GST (${gstPercent.toStringAsFixed(0)}%)', _money(gstAmount)),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 6),
                        child: pw.Divider(color: _lightGrey, thickness: 1),
                      ),
                      _totalRow('TOTAL', _money(grandTotal), bold: true, fontSize: 13),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 28),
            pw.Divider(color: _lightGrey, thickness: 1),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text('Thank you for shopping with $shopName!',
                  style: const pw.TextStyle(fontSize: 9.5, color: _grey)),
            ),
          ],
        );
      },
    ),
  );

  return doc.save();
}

String _money(double v) => 'S\$${v.toStringAsFixed(2)}';

pw.Widget _labelRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      children: [
        pw.SizedBox(
          width: 100,
          child: pw.Text(label, style: const pw.TextStyle(fontSize: 9.5, color: _grey)),
        ),
        pw.Text(value,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
}

pw.Widget _cell(String text,
    {bool bold = false, bool pad = false, pw.TextAlign align = pw.TextAlign.left}) {
  final child = pw.Text(
    text,
    textAlign: align,
    style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : null),
  );
  return pad
      ? pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: child)
      : child;
}

pw.Widget _totalRow(String label, String value, {bool bold = false, double fontSize = 10, PdfColor? color}) {
  final style = pw.TextStyle(
    fontSize: fontSize,
    fontWeight: bold ? pw.FontWeight.bold : null,
    color: color,
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: style.copyWith(color: color ?? _grey, fontSize: fontSize - (bold ? 0 : 0.5))),
        pw.Text(value, style: style),
      ],
    ),
  );
}

/// Opens the native print/share preview (AirPrint on iOS) for [order]'s
/// invoice — this is what both the admin "Print Invoice" button and the
/// customer's receipt-share icon call.
Future<void> shareReceipt(WidgetRef ref, Order order) async {
  final settings = await ref.read(shopSettingsProvider.future);
  final bytes = await buildInvoicePdf(order: order, settings: settings);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: 'Invoice-${order.displayNumber}.pdf',
  );
}
