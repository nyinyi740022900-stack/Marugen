import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/analytics/admin_analytics_screen.dart';
import 'package:marugen_app/features/admin/analytics/analytics_providers.dart';
import 'package:marugen_app/features/admin/analytics/analytics_repository.dart';

void main() {
  for (final dark in [false, true]) {
    for (final size in [const Size(320, 640), const Size(800, 1024)]) {
      for (final period in ['Daily', 'Weekly', 'Monthly']) {
        testWidgets(
          '$period ${dark ? 'dark' : 'light'} $size honors large text and full counts',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final now = DateTime.now();
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  appVisitsProvider.overrideWith(
                    (ref) async => List.filled(1234, now),
                  ),
                  productViewsProvider.overrideWith(
                    (ref) async => List.filled(
                      1234,
                      ProductViewRow(productName: 'Koi', viewedAt: now),
                    ),
                  ),
                ],
                child: MaterialApp(
                  theme: dark ? AppTheme.dark : AppTheme.light,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(2)),
                    child: child!,
                  ),
                  home: const AdminAnalyticsScreen(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            if (period != 'Daily') {
              await tester.ensureVisible(find.text(period));
              await tester.tap(find.text(period));
              await tester.pumpAndSettle();
            }
            expect(
              find.text('0'),
              findsNWidgets(
                period == 'Daily'
                    ? 13
                    : period == 'Weekly'
                    ? 7
                    : 5,
              ),
            );
            expect(tester.takeException(), isNull);
            expect(find.text('1234 visits'), findsOneWidget);
            final chartScroll = find.byWidgetPredicate(
              (widget) =>
                  widget is SingleChildScrollView &&
                  widget.scrollDirection == Axis.horizontal,
            );
            if (chartScroll.evaluate().isNotEmpty) {
              await tester.drag(chartScroll.last, const Offset(-2000, 0));
              await tester.pumpAndSettle();
            }
            expect(find.text('1234'), findsWidgets);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
