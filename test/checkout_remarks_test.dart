import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';

import 'checkout_safety_test.dart' as fixture;

void main() {
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets('large-text requests remain usable in ${theme.brightness}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await fixture.showCheckout(
        tester,
        Future.value({'gst_percent': 9, 'gst_included_in_price': true}),
        textScale: 2,
        theme: theme,
      );
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('order-remarks'));
      await tester.scrollUntilVisible(
        input,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(input, 'မရောက်ခင် ဖုန်းဆက်ပေးပါ။');
      await tester.pumpAndSettle();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('optional checkout requests preserve multiline Myanmar text', (
    tester,
  ) async {
    await fixture.showCheckout(
      tester,
      Future.value({'gst_percent': 9, 'gst_included_in_price': true}),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('order-remarks'));
    await tester.scrollUntilVisible(
      input,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(input, findsOneWidget);
    await tester.enterText(
      input,
      'မရောက်ခင် ဖုန်းဆက်ပေးပါ။\nPlease ring the doorbell.',
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(input).controller!.text,
      contains('မရောက်ခင်'),
    );
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('overlong requests prevent payment and editing restores it', (
    tester,
  ) async {
    await fixture.showCheckout(
      tester,
      Future.value({'gst_percent': 9, 'gst_included_in_price': true}),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('order-remarks'));
    await tester.scrollUntilVisible(
      input,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(input, 'x' * 501);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    expect(
      find.text('Keep your requests within 500 characters.'),
      findsOneWidget,
    );
    await tester.enterText(input, '');
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
