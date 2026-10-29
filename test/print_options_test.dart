import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/orders/utils/print_document.dart';
import 'package:pdf/pdf.dart';

void main() {
  test('page ranges select exact pages once and reject invalid ranges', () {
    expect(parsePrintPageRange('1, 3-5, 3', 5), [0, 2, 3, 4]);
    for (final input in ['', '0', '6', '4-2', '1,,2', '1.5', '-1', '1-6']) {
      expect(() => parsePrintPageRange(input, 5), throwsFormatException);
    }
  });
  test('standard paper choices have their actual physical dimensions', () {
    expect(
      const LabelPrintLayout(paper: LabelPaper.letter).pageFormat.width,
      PdfPageFormat.letter.width,
    );
    expect(
      const LabelPrintLayout(paper: LabelPaper.a5).pageFormat.width,
      PdfPageFormat.a5.width,
    );
    expect(
      const LabelPrintLayout(paper: LabelPaper.b5).pageFormat.width,
      closeTo(176 * PdfPageFormat.mm, .001),
    );
  });
  test('top-left scaling keeps the chosen corner fixed', () {
    const source = Rect.fromLTWH(20, 40, 100, 200);
    expect(
      scalePrintRect(source, 50, anchor: LabelPosition.topLeft),
      const Rect.fromLTWH(20, 40, 50, 100),
    );
    expect(
      scalePrintRect(source, 50, anchor: LabelPosition.bottomRight),
      const Rect.fromLTWH(70, 140, 50, 100),
    );
  });
  test(
    'custom scale preserves aspect ratio and anchors the content centre',
    () {
      final source = const Rect.fromLTWH(20, 40, 100, 200);
      final scaled = scalePrintRect(source, 50);
      expect(scaled, const Rect.fromLTWH(45, 90, 50, 100));
      expect(scalePrintRect(source, 100), source);
      for (final value in [double.nan, double.infinity, 0.0, 201.0]) {
        expect(() => scalePrintRect(source, value), throwsArgumentError);
      }
    },
  );
}
