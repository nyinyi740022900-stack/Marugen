import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/support/support_contact_form.dart';
import 'package:marugen_app/shared/models/support_contact.dart';

void main() {
  testWidgets(
    'staff form refuses invalid channels and returns validated contact',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SupportContact? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: SupportContactForm(onSaved: (value) => saved = value),
        ),
      );
      await tester.tap(find.text('Save contact'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'Staff name'),
        'Mei',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Support type / responsibility'),
        'Order enquiries',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Phone (optional)'),
        '88889999',
      );
      await tester.tap(find.text('Save contact'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'Phone (optional)'),
        '+6588889999',
      );
      await tester.tap(find.text('Save contact'));
      await tester.pumpAndSettle();
      expect(saved?.name, 'Mei');
      expect(saved?.phone, '+6588889999');
    },
  );
}
