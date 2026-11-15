import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/shared/widgets/simple_markdown.dart';

const _guide = '''
# Water changes
Change **20%** weekly.

WHY IT MATTERS
Nitrate builds up *slowly*.

- Test first
- Then change
1. Fill bucket
2. Add conditioner
''';

void main() {
  testWidgets('headings, bullets and emphasis render without raw markers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SingleChildScrollView(child: SimpleMarkdown(_guide)),
        ),
      ),
    );
    expect(find.text('Water changes'), findsOneWidget);
    expect(find.text('WHY IT MATTERS'), findsOneWidget);
    expect(find.textContaining('#'), findsNothing);
    expect(find.textContaining('**'), findsNothing);
    expect(find.text('•'), findsNWidgets(2));
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('stripMarkdown gives a one-line preview', () {
    expect(
      stripMarkdown('# Title\n- **bold** item\n\n2. second'),
      'Title bold item second',
    );
  });
}
