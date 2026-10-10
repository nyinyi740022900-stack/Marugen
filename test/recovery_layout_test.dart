import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/shared/widgets/empty_state.dart';

void main() {
  testWidgets(
    'Error recovery remains reachable with large text on a short screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 260);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 260),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(body: ErrorState(onRetry: () => retries++)),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    },
  );
}
