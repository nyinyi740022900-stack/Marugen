import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';

import 'checkout_safety_test.dart' as checkout;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('checkout exposes usable accessible controls in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        await checkout.showCheckout(
          tester,
          Future.value({'gst_percent': 9, 'gst_included_in_price': true}),
          theme: brightness == Brightness.light
              ? AppTheme.light
              : AppTheme.dark,
        );
        await tester.pumpAndSettle();
        expect(tester, meetsGuideline(androidTapTargetGuideline));
        expect(tester, meetsGuideline(labeledTapTargetGuideline));
        await tester.scrollUntilVisible(
          find.text('Total (incl. GST)'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester, meetsGuideline(androidTapTargetGuideline));
        expect(tester, meetsGuideline(labeledTapTargetGuideline));
        expect(find.textContaining('22.02 with Stripe'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });
  }
}
