import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/admin/payments/admin_payments_screen.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/shared/models/order.dart';

void main() {
  testWidgets('payment ledger excludes unpaid orders and explains pending refunds at large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 10, 20);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        adminOrdersProvider.overrideWith((ref) async => [
          Order(id: 'pending-123', userId: 'buyer', status: OrderStatus.pending,
            total: 100, createdAt: now, stripePaymentIntentId: 'pi_unpaid'),
          Order(id: 'paid-12345', userId: 'buyer', status: OrderStatus.paid,
            total: 20, createdAt: now, stripePaymentIntentId: 'pi_paid',
            refundStatus: 'requires_action', refundPendingAmount: 20),
        ]),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(body: AdminPaymentsPane()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Collected after refunds'), findsOneWidget);
    expect(find.text('S\$120.00'), findsNothing);
    expect(find.text('S\$20.00'), findsWidgets);
    await tester.scrollUntilVisible(find.text('REFUND NEEDS ATTENTION — CONTACT SHOP'), 150);
    expect(tester.takeException(), isNull);
  });
}
