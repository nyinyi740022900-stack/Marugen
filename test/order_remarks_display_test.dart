import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/orders/presentation/order_detail_screen.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/shared/models/order.dart';

void main() {
  for (final role in [UserRole.customer, UserRole.owner]) {
    testWidgets('saved customer requests are readable by $role in dark mode', (
      tester,
    ) async {
      const note = 'မရောက်ခင် ဖုန်းဆက်ပေးပါ။\nCall before delivery.';
      final order = Order(
        id: 'order-12345',
        userId: 'customer',
        status: OrderStatus.paid,
        total: 20,
        createdAt: DateTime(2026, 10, 10),
        customerRemarks: note,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAppUserProvider.overrideWith(
              (ref) async => AppUser(
                id: role == UserRole.customer ? 'customer' : 'admin',
                role: role,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: OrderDetailScreen(orderId: order.id, order: order),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final noteWidget = find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == note,
      );
      await tester.scrollUntilVisible(
        noteWidget,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(noteWidget, findsOneWidget);
      expect(find.text('CUSTOMER REQUESTS / REMARKS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
