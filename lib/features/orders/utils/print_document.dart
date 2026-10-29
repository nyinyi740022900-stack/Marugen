import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

enum LabelPaper { original, letter, a4, a5, b5, fourBySix, custom }

extension on LabelPaper {
  bool get isSheet => {
    LabelPaper.letter,
    LabelPaper.a4,
    LabelPaper.a5,
    LabelPaper.b5,
  }.contains(this);
}

enum PrintDestination { printer, pdf }

/// One-based user input becomes zero-based PDF indexes, without duplicate pages.
List<int> parsePrintPageRange(String input, int pageCount) {
  if (input.trim().isEmpty || input.length > 1000 || pageCount < 1) {
    throw const FormatException('Enter pages such as 1, 3-5.');
  }
  final pages = <int>{};
  for (final part in input.split(',')) {
    final match = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+)\s*)?$').firstMatch(part);
    if (match == null) {
      throw const FormatException('Enter pages such as 1, 3-5.');
    }
    final first = int.tryParse(match[1]!);
    final last = int.tryParse(match[2] ?? match[1]!);
    if (first == null ||
        last == null ||
        first < 1 ||
        last < first ||
        last > pageCount) {
      throw FormatException('Choose pages between 1 and $pageCount.');
    }
    for (var page = first; page <= last; page++) {
      pages.add(page - 1);
    }
  }
  return pages.toList()..sort();
}

Rect scalePrintRect(
  Rect rect,
  double percent, {
  LabelPosition anchor = LabelPosition.center,
}) {
  if (!percent.isFinite || percent < 10 || percent > 200) {
    throw ArgumentError('Scale must be between 10% and 200%.');
  }
  final x = (anchor.index % 3) / 2;
  final y = (anchor.index ~/ 3) / 2;
  final width = rect.width * percent / 100;
  final height = rect.height * percent / 100;
  return Rect.fromLTWH(
    rect.left + (rect.width - width) * x,
    rect.top + (rect.height - height) * y,
    width,
    height,
  );
}

enum LabelSourceArea { wholePage, topHalf, bottomHalf }

Rect labelSourceRect(Size size, LabelSourceArea area) {
  if (!size.width.isFinite ||
      !size.height.isFinite ||
      size.width <= 0 ||
      size.height <= 0) {
    throw ArgumentError('Empty source page');
  }
  final split = (size.height / 2).floorToDouble();
  return switch (area) {
    LabelSourceArea.wholePage => Offset.zero & size,
    LabelSourceArea.topHalf => Rect.fromLTWH(0, 0, size.width, split),
    LabelSourceArea.bottomHalf => Rect.fromLTWH(
      0,
      split,
      size.width,
      size.height - split,
    ),
  };
}

enum LabelPosition {
  topLeft('Top left'),
  topCenter('Top centre'),
  topRight('Top right'),
  centerLeft('Centre left'),
  center('Centre'),
  centerRight('Centre right'),
  bottomLeft('Bottom left'),
  bottomCenter('Bottom centre'),
  bottomRight('Bottom right');

  const LabelPosition(this.label);
  final String label;
}

/// PDF coordinates in points, measured from the top-left of the sheet.
/// A 4x6 sheet and a 4x6 label area on A4 are deliberately separate choices.
class LabelPrintLayout {
  const LabelPrintLayout({
    this.paper = LabelPaper.a4,
    this.position = LabelPosition.topLeft,
    this.insetMm = 5,
    this.widthMm = 101.6,
    this.heightMm = 152.4,
    this.horizontalFraction,
    this.verticalFraction,
  });
  final LabelPaper paper;
  final LabelPosition position;
  final double insetMm, widthMm, heightMm;
  final double? horizontalFraction, verticalFraction;

  PdfPageFormat get pageFormat => switch (paper) {
    LabelPaper.a4 => PdfPageFormat.a4,
    LabelPaper.letter => PdfPageFormat.letter,
    LabelPaper.a5 => PdfPageFormat.a5,
    LabelPaper.b5 => const PdfPageFormat(
      176 * PdfPageFormat.mm,
      250 * PdfPageFormat.mm,
    ),
    LabelPaper.fourBySix => const PdfPageFormat(
      4 * PdfPageFormat.inch,
      6 * PdfPageFormat.inch,
    ),
    LabelPaper.custom => PdfPageFormat(
      widthMm * PdfPageFormat.mm,
      heightMm * PdfPageFormat.mm,
    ),
    LabelPaper.original => throw StateError(
      'Original PDF uses its source paper size.',
    ),
  };

  String? get validationError {
    if (!widthMm.isFinite ||
        !heightMm.isFinite ||
        widthMm < 10 ||
        heightMm < 10 ||
        widthMm > 1000 ||
        heightMm > 1000) {
      return 'Enter a width and height between 10 and 1000 mm.';
    }
    if (!insetMm.isFinite || insetMm < 0 || insetMm > 15) {
      return 'Edge inset must be between 0 and 15 mm.';
    }
    for (final fraction in [horizontalFraction, verticalFraction]) {
      if (fraction != null &&
          (!fraction.isFinite || fraction < 0 || fraction > 1)) {
        return 'Position must be within the paper.';
      }
    }
    if (paper == LabelPaper.original) return null;
    final inset = paper.isSheet ? insetMm : 0;
    if ((widthMm + 2 * inset) * PdfPageFormat.mm > pageFormat.width + .001 ||
        (heightMm + 2 * inset) * PdfPageFormat.mm > pageFormat.height + .001) {
      return 'Label size plus edge inset must fit inside the selected paper.';
    }
    return null;
  }

  Rect get labelArea {
    final error = validationError;
    if (error != null) throw ArgumentError(error);
    final width = widthMm * PdfPageFormat.mm;
    final height = heightMm * PdfPageFormat.mm;
    final inset = paper.isSheet ? insetMm * PdfPageFormat.mm : 0.0;
    final freeX = math.max(0.0, pageFormat.width - width - 2 * inset);
    final freeY = math.max(0.0, pageFormat.height - height - 2 * inset);
    return Rect.fromLTWH(
      inset + freeX * (horizontalFraction ?? (position.index % 3) / 2),
      inset + freeY * (verticalFraction ?? (position.index ~/ 3) / 2),
      width,
      height,
    );
  }

  Rect contentRect(Size source) {
    if (!source.width.isFinite ||
        !source.height.isFinite ||
        source.width <= 0 ||
        source.height <= 0) {
      throw ArgumentError('Empty PDF page');
    }
    final area = labelArea;
    final scale = math.min(
      area.width / source.width,
      area.height / source.height,
    );
    final width = source.width * scale;
    final height = source.height * scale;
    return Rect.fromLTWH(
      area.left + (area.width - width) / 2,
      area.top + (area.height - height) / 2,
      width,
      height,
    );
  }
}

class LabelPageImage {
  const LabelPageImage({required this.png, required this.size});
  final Uint8List png;
  final Size size;
}

/// Renders the actual source document once, without rebuilding carrier content.
/// Raster output is 300dpi; it does not retain the source's vector objects.
Future<List<LabelPageImage>> rasterLabelPages(Uint8List source) async {
  final pages = <LabelPageImage>[];
  await for (final page in Printing.raster(source, dpi: 300)) {
    pages.add(
      LabelPageImage(
        png: await page.toPng(),
        size: Size(page.width.toDouble(), page.height.toDouble()),
      ),
    );
  }
  if (pages.isEmpty) throw StateError('The label PDF has no pages.');
  return pages;
}

/// Crops only after an explicit source-area choice. Pixels are copied from the
/// existing carrier PDF; tracking text, barcodes and QR codes are never rebuilt.
Future<LabelPageImage> cropLabelPage(
  LabelPageImage page,
  LabelSourceArea area,
) async {
  if (area == LabelSourceArea.wholePage) return page;
  final codec = await ui.instantiateImageCodec(page.png);
  final frame = await codec.getNextFrame();
  final sourceRect = labelSourceRect(
    Size(frame.image.width.toDouble(), frame.image.height.toDouble()),
    area,
  );
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    frame.image,
    sourceRect,
    Rect.fromLTWH(0, 0, sourceRect.width, sourceRect.height),
    ui.Paint()..filterQuality = ui.FilterQuality.none,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    sourceRect.width.toInt(),
    sourceRect.height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  frame.image.dispose();
  codec.dispose();
  return LabelPageImage(png: data!.buffer.asUint8List(), size: sourceRect.size);
}

Future<Uint8List> composeLabelPdf(
  List<LabelPageImage> pages,
  LabelPrintLayout layout, {
  LabelSourceArea sourceArea = LabelSourceArea.wholePage,
  double scalePercent = 100,
  LabelPosition scaleAnchor = LabelPosition.center,
}) async {
  if (pages.isEmpty) throw ArgumentError('The label PDF has no pages.');
  final document = pw.Document();
  for (final source in pages) {
    final page = await cropLabelPage(source, sourceArea);
    final rect = scalePrintRect(
      layout.contentRect(page.size),
      scalePercent,
      anchor: scaleAnchor,
    );
    final image = pw.MemoryImage(page.png);
    document.addPage(
      pw.Page(
        pageFormat: layout.pageFormat,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            pw.Positioned(
              left: rect.left,
              top: rect.top,
              child: pw.SizedBox(
                width: rect.width,
                height: rect.height,
                child: pw.Image(image, fit: pw.BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }
  return document.save();
}

/// Keep each selected page separate; changing paper or scale never creates
/// extra label copies. Original/unmodified PDFs bypass this raster conversion.
Future<Uint8List> composePrintDocument(
  List<LabelPageImage> pages, {
  PdfPageFormat? paper,
  double scalePercent = 100,
  LabelPosition scaleAnchor = LabelPosition.center,
}) async {
  if (pages.isEmpty) throw ArgumentError('Select at least one page.');
  final document = pw.Document();
  for (final page in pages) {
    final format =
        paper ??
        PdfPageFormat(
          page.size.width * PdfPageFormat.inch / 300,
          page.size.height * PdfPageFormat.inch / 300,
        );
    final fit = math.min(
      format.width / page.size.width,
      format.height / page.size.height,
    );
    final rect = scalePrintRect(
      Rect.fromCenter(
        center: Offset(format.width / 2, format.height / 2),
        width: page.size.width * fit,
        height: page.size.height * fit,
      ),
      scalePercent,
      anchor: scaleAnchor,
    );
    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            pw.Positioned(
              left: rect.left,
              top: rect.top,
              child: pw.SizedBox(
                width: rect.width,
                height: rect.height,
                child: pw.Image(
                  pw.MemoryImage(page.png),
                  fit: pw.BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  return document.save();
}

Future<void> previewPdfDocument(
  BuildContext context, {
  required Uint8List bytes,
  required String title,
  required String filename,
  bool labelDocument = false,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => PrintDocumentScreen(
      bytes: bytes,
      title: title,
      filename: filename,
      labelDocument: labelDocument,
    ),
  ),
);

/// Opens only the already-booked carrier label. It never books a shipment.
Future<void> previewShippingLabel(
  BuildContext context, {
  required String url,
  String? orderNumber,
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw const FormatException('The shipping label link is invalid.');
  }
  final data = await NetworkAssetBundle(uri)
      .load(uri.toString())
      .timeout(const Duration(seconds: 30));
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  // A PDF header may follow a short binary prefix in some carrier documents.
  final header = String.fromCharCodes(bytes.take(1024));
  if (!header.contains('%PDF-')) {
    throw const FormatException(
      'The carrier link did not return a PDF label. Open the original label in EasyParcel.',
    );
  }
  if (!context.mounted) return;
  await previewPdfDocument(
    context,
    bytes: bytes,
    title: 'Shipping label',
    filename: 'Shipping-Label-${orderNumber ?? 'carrier'}.pdf',
    labelDocument: true,
  );
}

class PrintDocumentScreen extends StatefulWidget {
  const PrintDocumentScreen({
    super.key,
    required this.bytes,
    required this.title,
    required this.filename,
    this.labelDocument = false,
  });
  final Uint8List bytes;
  final String title;
  final String filename;
  final bool labelDocument;
  @override
  State<PrintDocumentScreen> createState() => _PrintDocumentScreenState();
}

class _PrintDocumentScreenState extends State<PrintDocumentScreen> {
  LabelPaper _paper = LabelPaper.original;
  PdfPageFormat? _originalFormat;
  LabelPosition _position = LabelPosition.topLeft;
  double _inset = 5;
  double _widthMm = 101.6, _heightMm = 152.4;
  double _horizontal = 0, _vertical = 0;
  LabelSourceArea _sourceArea = LabelSourceArea.wholePage;
  final _widthController = TextEditingController(text: '101.6');
  final _heightController = TextEditingController(text: '152.4');
  late final Future<List<LabelPageImage>> _pages;
  late Future<Uint8List> _document;
  final _sourceCache = <LabelSourceArea, Future<List<LabelPageImage>>>{};
  PrintDestination _destination = PrintDestination.printer;
  bool _customPages = false, _customScale = false;
  double _scale = 100;
  LabelPosition _scaleAnchor = LabelPosition.topLeft;
  int? _pageCount;
  final _pageController = TextEditingController();
  final _scaleController = TextEditingController(text: '100');
  bool _acting = false;
  bool _adjusting = false;
  LabelPrintLayout get _layout => LabelPrintLayout(
    paper: _paper,
    position: _position,
    insetMm: _inset,
    widthMm: _widthMm,
    heightMm: _heightMm,
    horizontalFraction: _horizontal,
    verticalFraction: _vertical,
  );

  @override
  void initState() {
    super.initState();
    _pages = rasterLabelPages(widget.bytes).then((pages) {
      _pageCount = pages.length;
      return pages;
    });
    _document = _buildDocument();
  }

  PdfPageFormat get _pageFormat => _paper == LabelPaper.original
      ? (_originalFormat ?? PdfPageFormat.a4)
      : _layout.pageFormat;

  String? get _settingsError {
    if (_customScale && (!_scale.isFinite || _scale < 10 || _scale > 200)) {
      return 'Enter a scale between 10% and 200%.';
    }
    if (_customPages && _pageCount != null) {
      try {
        parsePrintPageRange(_pageController.text, _pageCount!);
      } on FormatException catch (error) {
        return error.message;
      }
    }
    if (_paper != LabelPaper.original &&
        (widget.labelDocument || _paper == LabelPaper.custom)) {
      return _layout.validationError;
    }
    return null;
  }

  Future<Uint8List> _buildDocument() async {
    final layout = _layout;
    final paper = _paper;
    final sourceArea = _sourceArea;
    final customPages = _customPages;
    final range = _pageController.text;
    final scale = _customScale ? _scale : 100.0;
    final scaleAnchor = _scaleAnchor;
    if (_settingsError != null) return Uint8List(0);
    final pages = await _pages;
    _originalFormat = PdfPageFormat(
      pages.first.size.width * PdfPageFormat.inch / 300,
      pages.first.size.height * PdfPageFormat.inch / 300,
    );
    final indexes = customPages
        ? parsePrintPageRange(range, pages.length)
        : List.generate(pages.length, (i) => i);
    if (paper == LabelPaper.original && !customPages && scale == 100) {
      return widget.bytes;
    }
    if (widget.labelDocument && paper != LabelPaper.original) {
      final cropped = await _sourceCache.putIfAbsent(
        sourceArea,
        () => Future.wait(pages.map((page) => cropLabelPage(page, sourceArea))),
      );
      return composeLabelPdf(
        indexes.map((i) => cropped[i]).toList(),
        layout,
        scalePercent: scale,
        scaleAnchor: scaleAnchor,
      );
    }
    return composePrintDocument(
      indexes.map((i) => pages[i]).toList(),
      paper: paper == LabelPaper.original ? null : layout.pageFormat,
      scalePercent: scale,
      scaleAnchor: scaleAnchor,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scaleController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _changePaper(LabelPaper paper) {
    _paper = paper;
    if (paper == LabelPaper.original) _sourceArea = LabelSourceArea.wholePage;
    if (paper == LabelPaper.fourBySix) {
      _widthMm = 101.6;
      _heightMm = 152.4;
      _widthController.text = '101.6';
      _heightController.text = '152.4';
    }
  }

  Widget _dimensionField({required bool width}) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      key: ValueKey(width ? 'label-width-mm' : 'label-height-mm'),
      controller: width ? _widthController : _heightController,
      enabled: !_acting,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        labelText: _paper == LabelPaper.custom
            ? (width ? 'Paper width (mm)' : 'Paper height (mm)')
            : (width ? 'Label width (mm)' : 'Label height (mm)'),
      ),
      onChanged: (value) => _update(() {
        final number =
            double.tryParse(value.replaceAll(',', '.')) ?? double.nan;
        if (width) {
          _widthMm = number;
        } else {
          _heightMm = number;
        }
      }),
    ),
  );

  void _update(VoidCallback change) => setState(() {
    change();
    _document = _buildDocument();
  });
  Future<void> _action(Uint8List bytes, {required bool print}) async {
    setState(() => _acting = true);
    try {
      if (print) {
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: widget.filename,
          format: _pageFormat,
          dynamicLayout: false,
        );
      } else {
        await Printing.sharePdf(bytes: bytes, filename: widget.filename);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              print
                  ? 'Could not start printing. Please try again.'
                  : 'Could not share the PDF. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Widget _printSettings() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<PrintDestination>(
          initialValue: _destination,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Destination'),
          items: const [
            DropdownMenuItem(
              value: PrintDestination.printer,
              child: Text('Printer (system dialog)'),
            ),
            DropdownMenuItem(
              value: PrintDestination.pdf,
              child: Text('Save as PDF'),
            ),
          ],
          onChanged: _acting
              ? null
              : (value) {
                  if (value != null) setState(() => _destination = value);
                },
        ),
        const SizedBox(height: 4),
        Text(
          _destination == PrintDestination.printer
              ? 'Choose your printer in the system print dialog.'
              : 'Choose Save to Files or a folder in the share dialog.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<LabelPageImage>>(
          future: _pages,
          builder: (context, snapshot) => DropdownButtonFormField<bool>(
            initialValue: _customPages,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Pages',
              helperText: snapshot.hasError
                  ? 'Could not read PDF pages. Reopen the document.'
                  : snapshot.hasData
                  ? '${snapshot.data!.length} page(s) in this document'
                  : 'Reading pages…',
            ),
            items: const [
              DropdownMenuItem(value: false, child: Text('All pages')),
              DropdownMenuItem(value: true, child: Text('Custom pages')),
            ],
            onChanged: _acting
                ? null
                : (value) {
                    if (value != null) _update(() => _customPages = value);
                  },
          ),
        ),
        if (_customPages) ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('print-pages'),
            controller: _pageController,
            enabled: !_acting,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: 'Page range',
              hintText: '1, 3-5',
            ),
            onChanged: (_) => _update(() {}),
          ),
        ],
        const SizedBox(height: 16),
        DropdownButtonFormField<LabelPaper>(
          key: ValueKey(_paper),
          isExpanded: true,
          initialValue: _paper,
          decoration: const InputDecoration(labelText: 'Paper size'),
          items: const [
            DropdownMenuItem(
              value: LabelPaper.original,
              child: Text('Original PDF'),
            ),
            DropdownMenuItem(value: LabelPaper.letter, child: Text('Letter')),
            DropdownMenuItem(value: LabelPaper.a4, child: Text('A4 sheet')),
            DropdownMenuItem(value: LabelPaper.a5, child: Text('A5')),
            DropdownMenuItem(value: LabelPaper.b5, child: Text('B5 (ISO)')),
            DropdownMenuItem(
              value: LabelPaper.fourBySix,
              child: Text('4 × 6 inch paper'),
            ),
            DropdownMenuItem(
              value: LabelPaper.custom,
              child: Text('Custom paper'),
            ),
          ],
          onChanged: _acting
              ? null
              : (value) {
                  if (value != null) _update(() => _changePaper(value));
                },
        ),
        if (!widget.labelDocument && _paper == LabelPaper.custom) ...[
          _dimensionField(width: true),
          _dimensionField(width: false),
        ],
        const SizedBox(height: 16),
        DropdownButtonFormField<bool>(
          initialValue: _customScale,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Scale'),
          items: const [
            DropdownMenuItem(
              value: false,
              child: Text('Default (fit to paper)'),
            ),
            DropdownMenuItem(value: true, child: Text('Custom scale')),
          ],
          onChanged: _acting
              ? null
              : (value) {
                  if (value != null) _update(() => _customScale = value);
                },
        ),
        if (_customScale) ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('print-scale'),
            controller: _scaleController,
            enabled: !_acting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: const InputDecoration(
              labelText: 'Scale (%)',
              helperText: '10–200% of the default preview size',
            ),
            onChanged: (value) => _update(
              () => _scale =
                  double.tryParse(value.replaceAll(',', '.')) ?? double.nan,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<LabelPosition>(
            key: const ValueKey('print-scale-anchor'),
            initialValue: _scaleAnchor,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Scale anchor'),
            items: LabelPosition.values
                .map(
                  (position) => DropdownMenuItem(
                    value: position,
                    child: Text(position.label),
                  ),
                )
                .toList(),
            onChanged: _acting
                ? null
                : (value) {
                    if (value != null) _update(() => _scaleAnchor = value);
                  },
          ),
          const SizedBox(height: 4),
          Text(
            'This point stays fixed when the content is resized.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_scale > 100)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Enlarged content may extend beyond the paper. Check that the full text and barcode remain visible.',
              ),
            ),
        ],
        if (_settingsError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _settingsError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SafeArea(
      child: ListView(
        children: [
          _printSettings(),
          if (widget.labelDocument)
            ExpansionTile(
              title: const Text('Label layout'),
              subtitle: const Text('Copies, dimensions and position'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<LabelSourceArea>(
                        key: ValueKey(_sourceArea),
                        initialValue: _sourceArea,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Source area / copies',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: LabelSourceArea.wholePage,
                            child: Text('Whole page'),
                          ),
                          DropdownMenuItem(
                            value: LabelSourceArea.topHalf,
                            child: Text('Top half (1 copy)'),
                          ),
                          DropdownMenuItem(
                            value: LabelSourceArea.bottomHalf,
                            child: Text('Bottom half (1 copy)'),
                          ),
                        ],
                        onChanged: _acting
                            ? null
                            : (area) {
                                if (area != null) {
                                  _update(() {
                                    _sourceArea = area;
                                    if (area != LabelSourceArea.wholePage &&
                                        _paper == LabelPaper.original) {
                                      _paper = LabelPaper.a4;
                                    }
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _sourceArea == LabelSourceArea.wholePage
                            ? 'Two copies already in your PDF? Choose a half to print one. This switches Original PDF to A4.'
                            : 'Only the selected half is printed. Check the preview includes a complete label and barcode.',
                      ),
                      if (_paper != LabelPaper.original) ...[
                        _dimensionField(width: true),
                        _dimensionField(width: false),
                        if (_layout.validationError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _layout.validationError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        const Text(
                          'The selected source area fits inside these dimensions without stretching.',
                        ),
                      ],
                      if (_paper.isSheet) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<LabelPosition>(
                          isExpanded: true,
                          initialValue: _position,
                          decoration: InputDecoration(
                            labelText: _paper == LabelPaper.a4
                                ? 'Position on A4'
                                : 'Position on paper',
                          ),
                          items: LabelPosition.values
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(p.label),
                                ),
                              )
                              .toList(),
                          onChanged: _acting
                              ? null
                              : (value) {
                                  if (value != null) {
                                    _update(() {
                                      _position = value;
                                      _horizontal = (value.index % 3) / 2;
                                      _vertical = (value.index ~/ 3) / 2;
                                    });
                                  }
                                },
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Edge inset: ${_inset.round()} mm'),
                            Slider(
                              value: _inset,
                              min: 0,
                              max: 15,
                              divisions: 15,
                              label: '${_inset.round()} mm',
                              onChanged: _acting
                                  ? null
                                  : (v) => setState(() {
                                      _inset = v;
                                      _adjusting = true;
                                    }),
                              onChangeEnd: (v) => _update(() {
                                _inset = v;
                                _adjusting = false;
                              }),
                            ),
                          ],
                        ),
                      ],
                      if (_paper.isSheet) ...[
                        Text(
                          'Horizontal position: ${(_horizontal * 100).round()}%',
                        ),
                        Slider(
                          value: _horizontal,
                          label: '${(_horizontal * 100).round()}%',
                          onChanged: _acting
                              ? null
                              : (v) => setState(() {
                                  _horizontal = v;
                                  _adjusting = true;
                                }),
                          onChangeEnd: (v) => _update(() {
                            _horizontal = v;
                            _adjusting = false;
                          }),
                        ),
                        const Text('0% left · 100% right'),
                        Text(
                          'Vertical position: ${(_vertical * 100).round()}%',
                        ),
                        Slider(
                          value: _vertical,
                          label: '${(_vertical * 100).round()}%',
                          onChanged: _acting
                              ? null
                              : (v) => setState(() {
                                  _vertical = v;
                                  _adjusting = true;
                                }),
                          onChangeEnd: (v) => _update(() {
                            _vertical = v;
                            _adjusting = false;
                          }),
                        ),
                        const Text('0% top · 100% bottom'),
                      ],
                      Text(
                        _paper == LabelPaper.original
                            ? 'Original source paper and all copies are preserved.'
                            : 'Custom sizing uses the selected source pixels. Check barcode size before printing.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          FutureBuilder<Uint8List>(
            future: _document,
            builder: (context, snapshot) {
              if (_settingsError != null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Correct the print settings above to preview and print.',
                  ),
                );
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Could not prepare this PDF preview. Go back and reopen the document to try again.',
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Back'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final bytes = snapshot.data!;
              if (bytes.isEmpty) return const SizedBox.shrink();
              return Column(
                children: [
                  SizedBox(
                    height: math.max(
                      320,
                      MediaQuery.sizeOf(context).height * .5,
                    ),
                    child: PdfPreview(
                      key: ObjectKey(bytes),
                      build: (_) async => bytes,
                      initialPageFormat: _pageFormat,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      canDebug: false,
                      useActions: false,
                      pdfFileName: widget.filename,
                      maxPageWidth: 640,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: _acting || _adjusting
                              ? null
                              : () => _action(
                                  bytes,
                                  print:
                                      _destination == PrintDestination.printer,
                                ),
                          icon: Icon(
                            _destination == PrintDestination.printer
                                ? Icons.print_outlined
                                : Icons.save_alt,
                          ),
                          label: Text(
                            _destination == PrintDestination.printer
                                ? 'Print PDF'
                                : 'Save PDF',
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_destination == PrintDestination.printer)
                          OutlinedButton.icon(
                            onPressed: _acting || _adjusting
                                ? null
                                : () => _action(bytes, print: false),
                            icon: const Icon(Icons.ios_share),
                            label: const Text('Share / save PDF'),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          _destination == PrintDestination.printer
                              ? 'The preview includes your page and scale choices. In the system print dialog, choose matching paper and 100% to avoid scaling twice.'
                              : 'The saved PDF uses the pages, paper size and scale shown in the preview.',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
