import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/shared/widgets/section_label.dart';

void main() {
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets('SectionLabel paints exactly what the copy-pasted style did '
        '(${theme.brightness.name})', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('RECENT ORDERS', key: Key('role')),
                  // The style every screen used to write out by hand.
                  Text(
                    'RECENT ORDERS',
                    key: const Key('literal'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.8,
                      color: AppPalette.of(context).textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      RenderParagraph paragraph(String key) => tester.renderObject(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(RichText),
          matchRoot: true,
        ),
      );
      final role = paragraph('role');
      final literal = paragraph('literal');
      expect(role.text.style, literal.text.style);
      expect(role.size, literal.size);
      expect(
        role.text.style!.color,
        (theme.brightness == Brightness.dark
                ? AppPalette.dark
                : AppPalette.light)
            .textMuted,
      );
    });
  }

  test('text roles keep the sizes screens already use', () {
    expect(AppTextStyles.sectionLabel.fontSize, 12);
    expect(AppTextStyles.sectionLabel.fontWeight, FontWeight.w700);
    expect(AppTextStyles.sectionLabel.letterSpacing, 0.8);
    expect(AppTextStyles.caption.fontSize, 12);
    expect(AppTextStyles.bodySmall.fontSize, 13);
    expect(AppTextStyles.cardTitle.fontSize, 13.5);
    expect(AppTextStyles.cardTitle.fontWeight, FontWeight.w600);
    expect(AppTextStyles.price.fontSize, 15);
    expect(AppTextStyles.price.fontWeight, FontWeight.w700);
    // Roles carry no colour: that comes from AppPalette where they are used.
    for (final style in [
      AppTextStyles.sectionLabel,
      AppTextStyles.caption,
      AppTextStyles.bodySmall,
      AppTextStyles.cardTitle,
      AppTextStyles.price,
    ]) {
      expect(style.color, isNull);
    }
  });
}
