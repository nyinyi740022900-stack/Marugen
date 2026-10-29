import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/admin/products/admin_product_edit_screen.dart';
import 'package:marugen_app/shared/models/product.dart';

import 'forms_responsive_test.dart' as forms;

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

void main() {
  setUpAll(() async {
    if (Platform.environment['PRODUCT_CAPTURE'] != '1') return;
    await (FontLoader('.SF Pro Text')..addFont(File('/System/Library/Fonts/SFNS.ttf').readAsBytes().then((b) => ByteData.sublistView(b)))).load();
    await (FontLoader('MaterialIcons')..addFont(File('/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes().then((b) => ByteData.sublistView(b)))).load();
  });
  testWidgets(
    'optional packed size requires three positive dimensions when entered',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('product-size-preview'),
        child: forms.host(const AdminProductEditScreen(), 0, Brightness.light, textScale: 1),
      ));
      await tester.pumpAndSettle();
      final category = tester.widget<DropdownButtonFormField<ProductCategory>>(
        find.byType(DropdownButtonFormField<ProductCategory>),
      );
      category.onChanged!(ProductCategory.accessories);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        field('Length (cm)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(field('Length (cm)'), '20');
      await tester.enterText(field('Width (cm)'), '0');
      final form = tester.state<FormState>(find.byType(Form).first);
      expect(form.validate(), isFalse);
      await tester.pump();
      expect(find.text('Enter a positive size.'), findsWidgets);
      await tester.enterText(field('Width (cm)'), '10');
      await tester.enterText(field('Height (cm)'), '8');
      for (final label in ['Length (cm)', 'Width (cm)', 'Height (cm)']) {
        final element = find
            .ancestor(of: field(label), matching: find.byType(TextFormField))
            .evaluate()
            .single;
        expect((element as StatefulElement).state is FormFieldState, isTrue);
        expect((element.state as FormFieldState).validate(), isTrue);
      }
      expect(tester.takeException(), isNull);
      if (Platform.environment['PRODUCT_CAPTURE'] == '1') {
        await tester.ensureVisible(find.text('Packed size (optional)'));
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('product-size-preview')));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ImageByteFormat.png);
          File('output/shipping-investigation/product-packed-size.png').writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );
  testWidgets(
    'kg generates an editable option label and preserves custom units',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        forms.host(
          const AdminProductEditScreen(),
          0,
          Brightness.light,
          textScale: 1,
        ),
      );
      await tester.pumpAndSettle();
      final category = tester.widget<DropdownButtonFormField<ProductCategory>>(
        find.byType(DropdownButtonFormField<ProductCategory>),
      );
      category.onChanged!(ProductCategory.fishFood);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Add Weight'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Add Weight'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Weight'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('kg').last);
      await tester.enterText(field('kg').last, '0.5');
      await tester.pump();
      expect(tester.widget<TextField>(field('Label')).controller!.text, '500g');
      await tester.enterText(field('kg').last, '2');
      await tester.pump();
      expect(tester.widget<TextField>(field('Label')).controller!.text, '2kg');
      await tester.enterText(field('Label'), '500ml');
      await tester.enterText(field('kg').last, '0.6');
      await tester.pump();
      expect(
        tester.widget<TextField>(field('Label')).controller!.text,
        '500ml',
      );
      await tester.enterText(field('Label'), '');
      await tester.enterText(field('kg').last, '1.25');
      await tester.pump();
      expect(
        tester.widget<TextField>(field('Label')).controller!.text,
        '1.25kg',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
