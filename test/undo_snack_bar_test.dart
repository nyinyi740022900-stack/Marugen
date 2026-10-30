import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/shared/widgets/undo_snack_bar.dart';

void main() {
  Future<void> showBar(
    WidgetTester tester, {
    required VoidCallback onAction,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showUndoSnackBar(
                ScaffoldMessenger.of(context),
                message: 'Removed Koi food',
                onAction: onAction,
              ),
              child: const Text('Remove'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
  }

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      'counts down from 5 and closes itself (${theme.brightness.name})',
      (tester) async {
        await showBar(tester, onAction: () {}, theme: theme);
        expect(find.text('Removed Koi food'), findsOneWidget);
        expect(find.text('Undo'), findsOneWidget);
        expect(find.text('5'), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('4'), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('3'), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Undo runs its action once and closes the bar', (tester) async {
    var undone = 0;
    await showBar(tester, onAction: () => undone++);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('screen reader users keep the bar, without a countdown', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await showBar(tester, onAction: () {});
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Removed Koi food'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('5'), findsNothing);
  });

  testWidgets('the ticking number is not announced', (tester) async {
    final semantics = tester.ensureSemantics();
    await showBar(tester, onAction: () {});
    expect(find.bySemanticsLabel(RegExp('Removed Koi food')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^5$')), findsNothing);
    semantics.dispose();
  });
}
