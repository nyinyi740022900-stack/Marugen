import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/admin/products/admin_product_edit_screen.dart';
import 'package:marugen_app/shared/models/product.dart';

import 'forms_responsive_test.dart' as forms;

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

String textOf(WidgetTester tester, String label) =>
    tester.widget<TextField>(field(label)).controller!.text;

String? errorOf(String label) {
  final element =
      find
              .ancestor(of: field(label), matching: find.byType(TextFormField))
              .evaluate()
              .single
          as StatefulElement;
  final state = element.state as FormFieldState<String>;
  state.validate();
  return state.errorText;
}

void main() {
  testWidgets('prices must be amounts above zero, a sale must be below the '
      'price, and stock takes whole numbers only', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
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
    tester
        .widget<DropdownButtonFormField<ProductCategory>>(
          find.byType(DropdownButtonFormField<ProductCategory>),
        )
        .onChanged!(ProductCategory.accessories);
    await tester.pumpAndSettle();

    const price = 'Price (SGD)';
    const sale = 'Sale price (SGD, optional)';
    expect(errorOf(price), 'Enter a price');
    await tester.enterText(field(price), '0');
    expect(errorOf(price), 'Price must be more than 0');
    await tester.enterText(field(price), '12.345');
    expect(errorOf(price), 'Enter an amount like 12.50');
    await tester.enterText(field(price), '1x2');
    expect(textOf(tester, price), '12');
    expect(errorOf(price), isNull);

    expect(errorOf(sale), isNull);
    await tester.enterText(field(sale), '15');
    expect(errorOf(sale), 'Sale price must be lower than the price');
    await tester.enterText(field(sale), '9.50');
    expect(errorOf(sale), isNull);

    await tester.enterText(field('Stock quantity'), '-3');
    expect(textOf(tester, 'Stock quantity'), '3');

    await tester.scrollUntilVisible(
      find.text('Add Weight'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add Weight'));
    await tester.pumpAndSettle();
    // An unlabelled row is skipped on save, so it needs no price yet.
    expect(errorOf('Price'), isNull);
    await tester.enterText(field('Label'), '1kg');
    expect(errorOf('Price'), 'Enter a price');
    await tester.enterText(field('Price'), '0.00');
    expect(errorOf('Price'), 'Price must be more than 0');
    await tester.enterText(field('Price'), '18.90');
    expect(errorOf('Price'), isNull);
    // Variant prices replace the product price, so it is no longer checked.
    await tester.enterText(field(price), '');
    expect(errorOf(price), isNull);
  });
}
