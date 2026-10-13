import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/legal/privacy_screen.dart';
import 'package:marugen_app/features/legal/privacy_content.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'Privacy requests remain readable on a compact $brightness screen',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: const PrivacyScreen(),
          ),
        );
        expect(find.text(privacyContactEmail), findsOneWidget);
        expect(find.text('Email a privacy request'), findsOneWidget);
        expect(find.textContaining('placeholder'), findsNothing);
        await tester.scrollUntilVisible(
          find.text('10. Privacy contact'),
          400,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('10. Privacy contact'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
