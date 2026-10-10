import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/shared/widgets/skeleton.dart';
import 'package:marugen_app/shared/widgets/empty_state.dart';
import 'package:marugen_app/core/theme/app_theme.dart';

void main() {
  testWidgets('shared loading card uses the nearest dark surface', (
    tester,
  ) async {
    final theme = AppTheme.dark;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 270,
              child: ProductCardSkeleton(),
            ),
          ),
        ),
      ),
    );
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(ProductCardSkeleton),
            matching: find.byType(Container),
          )
          .first,
    );
    final color = (container.decoration! as BoxDecoration).color!;
    expect(color.computeLuminance(), lessThan(0.15));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('dark empty state has readable secondary copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: EmptyState(
            icon: Icons.search,
            title: 'No products',
            subtitle: 'Try another search',
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('Try another search'));
    final foreground = text.style!.color!.computeLuminance();
    final background = AppTheme.dark.scaffoldBackgroundColor.computeLuminance();
    expect(
      (foreground + 0.05) / (background + 0.05),
      greaterThanOrEqualTo(4.5),
    );
  });
}
