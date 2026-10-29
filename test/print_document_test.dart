import 'dart:io';

import 'package:flutter/services.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/orders/utils/print_document.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:marugen_app/features/orders/utils/packing_slip_pdf.dart';
import 'package:marugen_app/shared/models/order.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final compact in [false, true]) {
    testWidgets(
      '${compact ? '320x640 at 2x text: ' : ''}preview separates paper from A4 placement and stacks print actions',
      (tester) async {
        const channel = MethodChannel('net.nfet.printing');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'printingInfo') {
            return <String, dynamic>{
              'canRaster': true,
              'canPrint': true,
              'canShare': true,
            };
          }
          if (call.method == 'rasterPdf') {
            final job = (call.arguments as Map)['job'];
            Future<void> send(
              String method,
              Map<String, dynamic> arguments,
            ) async {
              final data = const StandardMethodCodec().encodeMethodCall(
                MethodCall(method, arguments),
              );
              await messenger.handlePlatformMessage(
                'net.nfet.printing',
                data,
                (_) {},
              );
            }

            Future.microtask(() async {
              await send('onPageRasterized', {
                'job': job,
                'width': 2,
                'height': 3,
                'image': Uint8List.fromList(List.filled(24, 255)),
              });
              await send('onPageRasterEnd', {'job': job});
            });
          }
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await tester.binding.setSurfaceSize(
          compact ? const Size(320, 640) : const Size(390, 844),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await Printing.info();
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(compact ? 2 : 1)),
              child: child!,
            ),
            home: PrintDocumentScreen(
              bytes: Uint8List.fromList([1]),
              title: 'Packing label',
              filename: 'sample.pdf',
              labelDocument: true,
            ),
          ),
        );
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await tester.pump(const Duration(seconds: 1));
        }
        expect(find.text('Original PDF'), findsOneWidget);
        for (
          var i = 0;
          i < 8 && find.byType(PdfPreview).evaluate().isEmpty;
          i++
        ) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -350));
          await tester.pump(const Duration(seconds: 1));
        }
        expect(
          await tester
              .widget<PdfPreview>(find.byType(PdfPreview))
              .build(PdfPageFormat.a4),
          orderedEquals([1]),
        );
        expect(find.text('Position on A4'), findsNothing);
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pump();
        await tester.scrollUntilVisible(
          find.text('Label layout'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Label layout'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.ensureVisible(
          find.byType(DropdownButtonFormField<LabelSourceArea>),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byType(DropdownButtonFormField<LabelSourceArea>));
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.text('Top half (1 copy)').last);
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await tester.pump(const Duration(seconds: 1));
        }
        expect(find.text('Position on A4'), findsOneWidget);
        // Position controls confirm that the explicit crop selected A4.
        expect(find.text('Top half (1 copy)'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('label-width-mm')),
          '500',
        );
        await tester.pump();
        expect(
          find.text(
            'Label size plus edge inset must fit inside the selected paper.',
          ),
          findsWidgets,
        );
        await tester.enterText(
          find.byKey(const ValueKey('label-width-mm')),
          '160',
        );
        await tester.enterText(
          find.byKey(const ValueKey('label-height-mm')),
          '100',
        );
        await tester.pump();
        expect(
          find.text(
            'Label size plus edge inset must fit inside the selected paper.',
          ),
          findsNothing,
        );
        FocusManager.instance.primaryFocus?.unfocus();

        for (
          var i = 0;
          i < 10 && find.text('Print PDF').evaluate().isEmpty;
          i++
        ) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -350));
          await tester.pump(const Duration(seconds: 1));
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
        }
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await tester.pump(const Duration(seconds: 1));
        }
        expect(find.text('Print PDF'), findsOneWidget);
        expect(find.text('Share / save PDF'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Print PDF')).dy,
          lessThan(tester.getTopLeft(find.text('Share / save PDF')).dy),
        );
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pump();
        await tester.tap(find.byType(DropdownButtonFormField<LabelPaper>));
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await tester.pump(const Duration(seconds: 1));
        }
        await tester.tap(find.text('4 × 6 inch paper').last);
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await tester.pump(const Duration(seconds: 1));
        }
        expect(find.text('Position on A4'), findsNothing);
        expect(find.byType(Slider), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'composed output keeps all source pages and correct physical media',
    () async {
      final dir = await Directory.systemTemp.createTemp('marugen-print-');
      try {
        final order = Order(
          id: 'print-demo',
          userId: 'demo',
          orderNumber: 'DEMO-0001',
          status: OrderStatus.shipped,
          total: 0,
          createdAt: DateTime(2026, 10, 24),
          qxpressTrackingNo: 'DEMO123456789',
          shippingAddress: {
            'recipient_name': 'Sample Customer',
            'line1': '123 Sample Street',
            'line2': '#04-01',
            'city': 'Singapore',
            'postal_code': '123456',
            'phone': '00000000',
          },
          items: [
            OrderItem(
              productId: 'demo',
              productName: 'JPD Yamato Koi Food',
              quantity: 2,
              unitPrice: 0,
              sizeLabel: '3 kg',
            ),
          ],
        );
        final source = File('${dir.path}/source.pdf');
        await source.writeAsBytes(await buildPackingSlipPdf(order));
        final render = await Process.run('pdftoppm', [
          '-png',
          '-r',
          '300',
          '-singlefile',
          source.path,
          '${dir.path}/source',
        ]);
        expect(render.exitCode, 0);
        final png = await File('${dir.path}/source.png').readAsBytes();
        final codec = await ui.instantiateImageCodec(png);
        final frame = await codec.getNextFrame();
        final page = LabelPageImage(
          png: png,
          size: Size(
            frame.image.width.toDouble(),
            frame.image.height.toDouble(),
          ),
        );
        frame.image.dispose();
        codec.dispose();
        final output = Directory('output/pdf');
        await output.create(recursive: true);
        for (final entry in {
          'a4-top-left': const LabelPrintLayout(),
          'a4-bottom-right': const LabelPrintLayout(
            position: LabelPosition.bottomRight,
            insetMm: 12,
          ),
          '4x6': const LabelPrintLayout(paper: LabelPaper.fourBySix),
        }.entries) {
          final file = File('${output.path}/packing-preview-${entry.key}.pdf');
          await file.writeAsBytes(
            await composeLabelPdf([page, page], entry.value),
          );
          final info = await Process.run('pdfinfo', [file.path]);
          expect(info.exitCode, 0);
          expect(info.stdout.toString(), matches(RegExp(r'Pages:\s+2')));
          expect(
            info.stdout.toString(),
            contains(
              entry.value.paper == LabelPaper.a4
                  ? '595.276 x 841.89'
                  : '288 x 432',
            ),
          );
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'official carrier source remains complete on A4 placements and 4x6',
    () async {
      final source = File('output/split-parcels/QSP223261096.pdf');
      final dir = await Directory.systemTemp.createTemp(
        'marugen-carrier-acceptance-',
      );
      try {
        final render = await Process.run('pdftoppm', [
          '-png',
          '-r',
          '300',
          '-singlefile',
          source.path,
          '${dir.path}/source',
        ]);
        expect(render.exitCode, 0);
        final png = await File('${dir.path}/source.png').readAsBytes();
        final codec = await ui.instantiateImageCodec(png);
        final frame = await codec.getNextFrame();
        final page = LabelPageImage(
          png: png,
          size: Size(
            frame.image.width.toDouble(),
            frame.image.height.toDouble(),
          ),
        );
        frame.image.dispose();
        codec.dispose();
        for (final entry in {
          'a4-top-left': const LabelPrintLayout(),
          'a4-bottom-right': const LabelPrintLayout(
            position: LabelPosition.bottomRight,
            insetMm: 12,
          ),
          '4x6': const LabelPrintLayout(paper: LabelPaper.fourBySix),
          'top-copy-custom-a4': const LabelPrintLayout(
            widthMm: 180,
            heightMm: 128,
            insetMm: 10,
            horizontalFraction: .2,
            verticalFraction: .3,
          ),
          'bottom-copy-custom-paper': const LabelPrintLayout(
            paper: LabelPaper.custom,
            widthMm: 180,
            heightMm: 128,
          ),
        }.entries) {
          final area = entry.key.startsWith('top-copy')
              ? LabelSourceArea.topHalf
              : entry.key.startsWith('bottom-copy')
              ? LabelSourceArea.bottomHalf
              : LabelSourceArea.wholePage;
          final bytes = await composeLabelPdf(
            [page],
            entry.value,
            sourceArea: area,
          );
          final file = File('output/pdf/carrier-preview-${entry.key}.pdf');
          await file.writeAsBytes(bytes);
          final info = await Process.run('pdfinfo', [file.path]);
          expect(info.exitCode, 0);
          expect(info.stdout.toString(), matches(RegExp(r'Pages:\s+1')));
          expect(
            info.stdout.toString(),
            contains(
              entry.value.paper == LabelPaper.a4
                  ? '595.276 x 841.89'
                  : entry.value.paper == LabelPaper.custom
                  ? '510.236 x 362.835'
                  : '288 x 432',
            ),
          );
          final finalRender = await Process.run('pdftoppm', [
            '-png',
            '-r',
            '150',
            '-singlefile',
            file.path,
            'output/pdf/carrier-preview-${entry.key}',
          ]);
          expect(finalRender.exitCode, 0);
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
    skip: !File('output/split-parcels/QSP223261096.pdf').existsSync(),
  );
  test('custom label dimensions and position stay inside A4', () {
    const layout = LabelPrintLayout(
      widthMm: 160,
      heightMm: 100,
      insetMm: 8,
      horizontalFraction: .25,
      verticalFraction: .75,
    );
    expect(layout.validationError, isNull);
    expect(layout.labelArea.width, closeTo(160 * PdfPageFormat.mm, .001));
    expect(layout.labelArea.height, closeTo(100 * PdfPageFormat.mm, .001));
    expect(
      layout.labelArea.left,
      closeTo((8 + (210 - 160 - 16) * .25) * PdfPageFormat.mm, .001),
    );
    expect(layout.labelArea.bottom, lessThan(PdfPageFormat.a4.height));
    const paper = LabelPrintLayout(
      paper: LabelPaper.custom,
      widthMm: 80,
      heightMm: 120,
    );
    expect(paper.pageFormat.width, closeTo(80 * PdfPageFormat.mm, .001));
    expect(paper.labelArea.left, 0);
  });
  test('invalid dimensions and out of bounds positions fail clearly', () {
    for (final layout in [
      const LabelPrintLayout(widthMm: 0),
      const LabelPrintLayout(widthMm: double.nan),
      const LabelPrintLayout(widthMm: 205, insetMm: 5),
      const LabelPrintLayout(heightMm: 300),
      const LabelPrintLayout(horizontalFraction: 1.1),
    ]) {
      expect(layout.validationError, isNotNull);
      expect(() => layout.labelArea, throwsArgumentError);
    }
  });
  test('explicit half-page source choices retain one full half', () {
    const size = Size(2480, 3508);
    expect(
      labelSourceRect(size, LabelSourceArea.wholePage),
      const Rect.fromLTWH(0, 0, 2480, 3508),
    );
    expect(
      labelSourceRect(size, LabelSourceArea.topHalf),
      const Rect.fromLTWH(0, 0, 2480, 1754),
    );
    expect(
      labelSourceRect(size, LabelSourceArea.bottomHalf),
      const Rect.fromLTWH(0, 1754, 2480, 1754),
    );
  });
  test('A4 holds a true 4 by 6 inch area at each position', () {
    for (final position in LabelPosition.values) {
      final layout = LabelPrintLayout(position: position);
      final rect = layout.labelArea;
      expect(layout.pageFormat.width, PdfPageFormat.a4.width);
      expect(rect.width, closeTo(4 * PdfPageFormat.inch, .001));
      expect(rect.height, closeTo(6 * PdfPageFormat.inch, .001));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(layout.pageFormat.width));
      expect(rect.bottom, lessThanOrEqualTo(layout.pageFormat.height));
    }
  });
  test('4 by 6 media is distinct from A4 placement and has no inset', () {
    final layout = LabelPrintLayout(paper: LabelPaper.fourBySix, insetMm: 15);
    expect(layout.pageFormat.width, 288);
    expect(layout.pageFormat.height, 432);
    expect(layout.labelArea.left, 0);
    expect(layout.labelArea.top, 0);
    expect(layout.labelArea.width, closeTo(288, .001));
    expect(layout.labelArea.height, closeTo(432, .001));
  });
  test('wide and tall source pages fit proportionally with no cropping', () {
    const layout = LabelPrintLayout(position: LabelPosition.bottomRight);
    for (final size in [const Size(1800, 1200), const Size(400, 2000)]) {
      final rect = layout.contentRect(size);
      expect(rect.width / rect.height, closeTo(size.aspectRatio, .00001));
      expect(layout.labelArea.contains(rect.topLeft), isTrue);
      expect(rect.right, lessThanOrEqualTo(layout.labelArea.right + .0001));
      expect(rect.bottom, lessThanOrEqualTo(layout.labelArea.bottom + .0001));
    }
  });
  test('inset adjusts top-left placement in millimetres', () {
    const layout = LabelPrintLayout(insetMm: 12);
    expect(layout.labelArea.left, closeTo(12 * PdfPageFormat.mm, .001));
    expect(layout.labelArea.top, closeTo(12 * PdfPageFormat.mm, .001));
  });
}
