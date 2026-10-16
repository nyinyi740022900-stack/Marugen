import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';

void main() {
  for (final entry in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    testWidgets('AlertDialog title is readable in ${entry.key} theme', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: entry.value,
          home: const AlertDialog(
            title: Text('Delete product?'),
            content: Text('Body'),
          ),
        ),
      );
      final title = tester.widget<RichText>(
        find.descendant(
          of: find.text('Delete product?'),
          matching: find.byType(RichText),
        ),
      );
      final color = title.text.style!.color!;
      final background = entry.value.dialogTheme.backgroundColor!;
      // Title must contrast with the dialog surface (regression: white on
      // white in the light theme).
      expect(
        (color.computeLuminance() - background.computeLuminance()).abs(),
        greaterThan(0.5),
      );
    });
  }
}
