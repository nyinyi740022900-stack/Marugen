import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/orders/utils/print_document.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'pdf_tools.dart';

void main() {
  testWidgets(
    'invoice page selection, paper, scale and save destination affect the output',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('net.nfet.printing');
      Uint8List? shared;
      Future<void> send(String method, Map<String, dynamic> arguments) async {
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (_) {},
        );
      }

      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'printingInfo') {
          return {'canRaster': true, 'canPrint': true, 'canShare': true};
        }
        if (call.method == 'sharePdf') {
          shared = (call.arguments as Map)['doc'] as Uint8List;
          return 1;
        }
        if (call.method == 'rasterPdf') {
          final job = (call.arguments as Map)['job'];
          Future.microtask(() async {
            for (var i = 0; i < 3; i++) {
              await send('onPageRasterized', {
                'job': job,
                'width': 40,
                'height': 60,
                'image': Uint8List.fromList(
                  List.generate(40 * 60 * 4, (i) => i % 4 == 3 ? 255 : 0),
                ),
              });
            }
            await send('onPageRasterEnd', {'job': job});
          });
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await Printing.info();
      await tester.pumpWidget(
        MaterialApp(
          home: PrintDocumentScreen(
            bytes: Uint8List.fromList([1]),
            title: 'Invoice',
            filename: 'invoice.pdf',
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 300));
        }
      }

      Finder select(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<bool> &&
            widget.decoration.labelText == label,
      );
      await settle();
      for (
        var i = 0;
        i < 10 && find.text('3 page(s) in this document').evaluate().isEmpty;
        i++
      ) {
        await settle();
      }
      expect(find.text('3 page(s) in this document'), findsOneWidget);
      tester.widget<DropdownButtonFormField<bool>>(select('Pages')).onChanged!(
        true,
      );
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('print-pages')), '4');
      await settle();
      expect(find.text('Choose pages between 1 and 3.'), findsOneWidget);
      expect(find.byType(PdfPreview), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('print-pages')), '1,3');
      tester
          .widget<DropdownButtonFormField<LabelPaper>>(
            find.byType(DropdownButtonFormField<LabelPaper>),
          )
          .onChanged!(LabelPaper.letter);
      await tester.pump();
      tester.widget<DropdownButtonFormField<bool>>(select('Scale')).onChanged!(
        true,
      );
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('print-scale')), '0');
      await tester.pump();
      expect(find.text('Enter a scale between 10% and 200%.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('print-scale')), '50');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('print-scale')))
            .textInputAction,
        TextInputAction.done,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('print-scale')),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isFalse,
      );
      final anchor = tester.widget<DropdownButtonFormField<LabelPosition>>(
        find.byKey(const ValueKey('print-scale-anchor')),
      );
      expect(anchor.initialValue, LabelPosition.topLeft);
      anchor.onChanged!(LabelPosition.center);
      tester
          .widget<DropdownButtonFormField<PrintDestination>>(
            find.byType(DropdownButtonFormField<PrintDestination>),
          )
          .onChanged!(PrintDestination.pdf);
      FocusManager.instance.primaryFocus?.unfocus();
      await settle();
      await tester.scrollUntilVisible(
        find.byType(PdfPreview),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await settle();
      final preview = tester.widget<PdfPreview>(find.byType(PdfPreview));
      final bytes = await preview.build(PdfPageFormat.a4);
      expect(preview.initialPageFormat!.width, PdfPageFormat.letter.width);
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp(
          'marugen-print-options-',
        );
        try {
          final file = File('${dir.path}/selected.pdf');
          await file.writeAsBytes(bytes);
          final info = await Process.run('pdfinfo', [file.path]);
          expect(info.exitCode, 0);
          expect(info.stdout.toString(), matches(RegExp(r'Pages:\s+2')));
          expect(info.stdout.toString(), contains('612 x 792 pts (letter)'));
          final raster = await Process.run('pdftoppm', [
            '-png',
            '-r',
            '72',
            '-singlefile',
            file.path,
            '${dir.path}/selected',
          ]);
          expect(raster.exitCode, 0);
          final codec = await ui.instantiateImageCodec(
            await File('${dir.path}/selected.png').readAsBytes(),
          );
          final frame = await codec.getNextFrame();
          final pixels = await frame.image.toByteData();
          final width = frame.image.width;
          int value(int x, int y) => pixels!.getUint8((y * width + x) * 4);
          expect(value(306, 396), 0); // Centre of the scaled source is black.
          expect(value(170, 396), 255); // Outside the 264px-wide 50% source.
          expect(value(178, 396), 0);
          expect(value(306, 194), 255); // Outside its 396px height.
          expect(value(306, 202), 0);
          frame.image.dispose();
          codec.dispose();
        } finally {
          await dir.delete(recursive: true);
        }
      });
      await tester.scrollUntilVisible(
        find.text('Save PDF'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save PDF'));
      await settle();
      expect(shared, orderedEquals(bytes));
      expect(tester.takeException(), isNull);
    },
    skip: popplerMissing,
  );
}
