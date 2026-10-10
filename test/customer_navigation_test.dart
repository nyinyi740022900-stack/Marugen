import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/shop/presentation/customer_shell.dart';

void main() {
  for (final size in [
    const Size(390, 700),
    const Size(820, 1180),
    const Size(1024, 500),
  ]) {
    testWidgets('Labeled navigation remains usable at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AdaptiveCustomerNavigation(
            index: 0,
            onSelected: (i) => selected = i,
            body: const Center(child: Text('Products')),
          ),
        ),
      );
      expect(
        find.byType(size.width >= 700 ? NavigationRail : BottomNavigationBar),
        findsOneWidget,
      );
      if (size.width >= 700) {
        final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
        final foreground = rail.selectedIconTheme!.color!.computeLuminance();
        final background = rail.indicatorColor!.computeLuminance();
        expect((foreground + 0.05) / (background + 0.05), greaterThanOrEqualTo(3));
      }
      await tester.tap(find.text('Orders'));
      expect(selected, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
