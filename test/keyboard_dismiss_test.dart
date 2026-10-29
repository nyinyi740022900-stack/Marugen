import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/shared/widgets/keyboard_dismiss_region.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      '$platform numeric keyboard has Done and blank taps dismiss without actions',
      (tester) async {
        final focus = FocusNode();
        final controller = TextEditingController();
        addTearDown(focus.dispose);
        addTearDown(controller.dispose);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var submitted = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(viewInsets: const EdgeInsets.only(bottom: 300)),
              child: KeyboardDismissRegion(child: child!),
            ),
            home: Scaffold(
              body: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  TextField(
                    focusNode: focus,
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(key: ValueKey('blank'), height: 160),
                  const TextFieldTapRegion(
                    child: SizedBox(
                      key: ValueKey('scroll-region'),
                      height: 160,
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => submitted = true,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.enterText(find.byType(TextField), '70');
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        expect(
          tester.getBottomRight(find.text('Done')).dy,
          lessThanOrEqualTo(544),
        );
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isFalse);
        expect(controller.text, '70');
        expect(submitted, isFalse);
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        await tester.tapAt(
          tester.getCenter(find.byKey(const ValueKey('blank'))),
          kind: PointerDeviceKind.touch,
        );
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isFalse);
        expect(submitted, isFalse);
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        await tester.dragFrom(
          tester.getCenter(find.byKey(const ValueKey('scroll-region'))),
          const Offset(0, -120),
        );
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('no toolbar or extra space when the keyboard is closed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => KeyboardDismissRegion(child: child!),
        home: const Scaffold(body: Text('Page')),
      ),
    );
    expect(find.text('Done'), findsNothing);
    expect(
      tester.getSize(find.byType(Scaffold)),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
  });
}
