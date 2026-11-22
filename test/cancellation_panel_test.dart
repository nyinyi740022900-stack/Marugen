import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/orders/presentation/order_cancellation_panel.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/shared/models/order.dart';

import 'order_cancellation_test.dart' show orderMap;

class CancellationRepository implements OrderRepository {
  final calls = <String>[];
  @override
  Future<void> manageCancellation(
    String id,
    String action, {
    String? reason,
  }) async {
    calls.add(action);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final activeAccount = StateProvider<String>((ref) => 'customer');

Future<ProviderContainer> pumpPanel(
  WidgetTester tester,
  Order order,
  CancellationRepository repo, {
  bool admin = false,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWith((ref) => ref.watch(activeAccount)),
        currentAppUserProvider.overrideWith(
          (ref) async => AppUser(
            id: ref.watch(activeAccount),
            fullName: 'Test',
            email: 'test@example.com',
            role: admin ? UserRole.owner : UserRole.customer,
          ),
        ),
        orderRepositoryProvider.overrideWithValue(repo),
        orderByIdProvider(order.id).overrideWith((ref) async => order),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: OrderCancellationPanel(order: order),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(OrderCancellationPanel)),
  );
}

void main() {
  testWidgets('customer submits a request, not a direct refund', (
    tester,
  ) async {
    final repo = CancellationRepository();
    await pumpPanel(tester, Order.fromMap(orderMap()), repo);
    await tester.tap(find.text('Request cancellation'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not cancelled yet'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Ordered by mistake');
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['request']);
  });
  testWidgets('account switching closes off a pending confirmation', (
    tester,
  ) async {
    final repo = CancellationRepository();
    final container = await pumpPanel(tester, Order.fromMap(orderMap()), repo);
    await tester.tap(find.text('Request cancellation'));
    await tester.pumpAndSettle();
    container.read(activeAccount.notifier).state = 'other';
    await tester.pumpAndSettle();
    final button = find.text('Send request');
    if (button.evaluate().isNotEmpty) {
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    expect(repo.calls, isEmpty);
  });
  testWidgets(
    'pending request explains hold without claiming refund completed',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final order = Order.fromMap(
        orderMap({
          'order_cancellation_requests': {
            'status': 'requested',
            'reason': 'A long reason for the shop to review',
          },
        }),
      );
      await pumpPanel(tester, order, CancellationRepository(), scale: 2);
      expect(find.text('Cancellation requested'), findsOneWidget);
      expect(find.text('Approve & refund'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('owner can review request with explicit refund confirmation', (
    tester,
  ) async {
    final repo = CancellationRepository();
    final order = Order.fromMap(
      orderMap({
        'order_cancellation_requests': {'status': 'requested'},
      }),
    );
    await pumpPanel(tester, order, repo, admin: true);
    await tester.tap(find.text('Approve & refund'));
    await tester.pumpAndSettle();
    // The amount is on the message and on the button; the other button
    // only closes the dialog, so it does not read as a decision.
    expect(
      find.text(
        "Refund S\$20.00 to the customer's original payment method? "
        'Delivery stays paused until Stripe confirms.',
      ),
      findsOneWidget,
    );
    expect(find.text('Keep order'), findsNothing);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);

    await tester.tap(find.text('Approve & refund'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refund S\$20.00'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['approve']);
  });

  testWidgets('declining is dismissed with Back, not "Keep order"', (
    tester,
  ) async {
    final repo = CancellationRepository();
    final order = Order.fromMap(
      orderMap({
        'order_cancellation_requests': {'status': 'requested'},
      }),
    );
    await pumpPanel(tester, order, repo, admin: true);
    await tester.tap(find.text('Decline request'));
    await tester.pumpAndSettle();
    expect(find.text('Keep order'), findsNothing);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
  });

  testWidgets('the customer keeps "Keep order" on their own request', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      Order.fromMap(orderMap()),
      CancellationRepository(),
    );
    await tester.tap(find.text('Request cancellation'));
    await tester.pumpAndSettle();
    expect(find.text('Keep order'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
  });

  testWidgets('each side reads the panel in its own voice', (tester) async {
    final order = Order.fromMap(
      orderMap({
        'refund_status': 'failed',
        'order_cancellation_requests': {
          'status': 'approved',
          'reason': 'Ordered twice',
        },
      }),
    );
    await pumpPanel(tester, order, CancellationRepository(), admin: true);
    expect(find.text('Customer reason: Ordered twice'), findsOneWidget);
    expect(
      find.textContaining('Refund failed — check Stripe'),
      findsOneWidget,
    );
    expect(find.textContaining('contact shop'), findsNothing);

    // A fresh scope: the customer's own view of the same order.
    await tester.pumpWidget(const SizedBox());
    await pumpPanel(tester, order, CancellationRepository());
    expect(find.text('Your reason: Ordered twice'), findsOneWidget);
    expect(find.textContaining('Customer reason'), findsNothing);
    expect(find.textContaining('Refund failed — contact shop'), findsOneWidget);
  });

  test('staff status labels point at Stripe or the courier, never at '
      '"the shop"', () {
    final failed = Order.fromMap(
      orderMap({'status': 'refunded', 'refund_status': 'failed'}),
    );
    expect(failed.fulfillmentStatusLabel, 'Refund failed — contact shop');
    expect(failed.staffFulfillmentStatusLabel, 'Refund failed — check Stripe');
    expect(
      Order.fromMap(
        orderMap({'refund_status': 'requires_action'}),
      ).staffRefundStatusLabel,
      'Refund needs attention — check Stripe',
    );
    final issue = Order.fromMap(
      orderMap({
        'status': 'shipped',
        'tracking_provider': 'easyparcel',
        'tracking_status_code': 6,
      }),
    );
    expect(issue.fulfillmentStatusLabel, 'Delivery issue — contact shop');
    expect(
      issue.staffFulfillmentStatusLabel,
      'Delivery issue — check the courier',
    );
    // Everything else is the same wording for both.
    final paid = Order.fromMap(orderMap());
    expect(paid.staffFulfillmentStatusLabel, paid.fulfillmentStatusLabel);
  });
}
