import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'print_document.dart';

import '../../../shared/models/order.dart';

/// Shop packing label. The carrier's official AWB remains a separate document.
Future<Uint8List> buildPackingSlipPdf(
  Order order, {
  Map<String, dynamic> settings = const {},
}) async {
  final shipping = order.shippingAddress ?? {};
  final tracking = order.qxpressTrackingNo?.trim();
  final hasTracking = tracking != null && tracking.isNotEmpty;
  final barcodeSafe =
      hasTracking && RegExp(r'^[\x20-\x7E]+$').hasMatch(tracking);
  final address = [shipping['line1'], shipping['line2']]
      .where((value) => value != null && value.toString().trim().isNotEmpty)
      .join(', ');
  final region = [shipping['city'] ?? 'Singapore', shipping['postal_code']]
      .where(
        (value) =>
            value != null &&
            value.toString().isNotEmpty &&
            !address.toLowerCase().contains(value.toString().toLowerCase()),
      )
      .join(' ');
  final logoData = await rootBundle.load('assets/images/logo.png');
  final logo = pw.MemoryImage(
    logoData.buffer.asUint8List(logoData.offsetInBytes, logoData.lengthInBytes),
  );
  final doc = pw.Document();
  pw.Widget text(String value, {double size = 9, bool bold = false}) => pw.Text(
    value,
    style: pw.TextStyle(
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : null,
    ),
  );
  pw.Widget box(List<pw.Widget> children) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(7),
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.7)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: children,
    ),
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a6,
      margin: const pw.EdgeInsets.all(10),
      maxPages: 100,
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      ),
      header: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Image(logo, width: 32, height: 32, fit: pw.BoxFit.contain),
            pw.SizedBox(width: 7),
            pw.Expanded(
              child: text(
                settings['shop_name']?.toString() ?? 'MARUGEN FISH FARM',
                size: 10,
                bold: true,
              ),
            ),
            text('PACKING LABEL', size: 7, bold: true),
          ],
        ),
      ),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: text('Attach official courier AWB separately.', size: 6),
            ),
            text('${context.pageNumber} / ${context.pagesCount}', size: 6),
          ],
        ),
      ),
      build: (_) => [
        box([
          text(
            hasTracking ? 'TRACKING NUMBER' : 'ORDER REFERENCE - NOT BOOKED',
            size: 7,
          ),
          pw.SizedBox(height: 4),
          text(
            hasTracking ? tracking : order.displayNumber,
            size: 12,
            bold: true,
          ),
          if (barcodeSafe) ...[
            pw.SizedBox(height: 7),
            pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: tracking,
              width: 250,
              height: 36,
              drawText: false,
            ),
          ],
        ]),
        box([
          text('SHIP TO', size: 7, bold: true),
          pw.SizedBox(height: 4),
          text(
            shipping['recipient_name']?.toString() ?? '-',
            size: 12,
            bold: true,
          ),
          text(
            address.isEmpty ? 'Address not provided' : address,
            size: 13,
            bold: true,
          ),
          if (region.isNotEmpty) text(region, size: 13, bold: true),
          if (shipping['phone'] != null)
            text('Tel: ${shipping['phone']}', size: 9),
        ]),
        box([
          text(
            'FROM: ${settings['shop_name'] ?? 'Marugen Fish Farm'}',
            bold: true,
          ),
          if (settings['shop_address'] != null)
            text(settings['shop_address'].toString(), size: 8),
          if (settings['shop_phone'] != null)
            text('Tel: ${settings['shop_phone']}', size: 8),
        ]),
        box([
          text('Order: ${order.displayNumber}', bold: true),
          text(
            'Items: ${order.items.fold<int>(0, (sum, item) => sum + item.quantity)}',
          ),
        ]),
        pw.TableHelper.fromTextArray(
          headers: ['ITEM / OPTION', 'QTY'],
          headerStyle: pw.TextStyle(
            fontSize: 7,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellPadding: const pw.EdgeInsets.all(5),
          columnWidths: {
            0: const pw.FlexColumnWidth(5),
            1: const pw.FlexColumnWidth(1),
          },
          cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.center},
          border: pw.TableBorder.all(width: 0.7),
          data: order.items
              .map(
                (item) => [
                  [
                    item.productName,
                    item.optionLabel,
                  ].where((v) => v != null && v.isNotEmpty).join('\n'),
                  '${item.quantity}',
                ],
              )
              .toList(),
        ),
      ],
    ),
  );
  return doc.save();
}

Future<void> printPackingSlip(
  Order order, {
  required BuildContext context,
  Map<String, dynamic> settings = const {},
}) async {
  final bytes = await buildPackingSlipPdf(order, settings: settings);
  if (!context.mounted) return;
  await previewPdfDocument(
    context,
    bytes: bytes,
    title: 'Packing label',
    filename: 'Packing-Label-${order.displayNumber}.pdf',
    labelDocument: true,
  );
}
