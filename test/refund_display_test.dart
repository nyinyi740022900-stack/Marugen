import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/delivery/easyparcel_providers.dart';
import 'package:marugen_app/features/admin/orders/admin_orders_screen.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/orders/presentation/order_detail_screen.dart';
import 'package:marugen_app/features/orders/presentation/order_payment_section.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/orders/utils/order_payment_line.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/providers/paged_notifier.dart';

final _now = DateTime.utc(2026, 10, 20);

Order _order({
  String id = 'order-12345',
  OrderStatus status = OrderStatus.paid,
  double total = 120,
  String? paymentId = 'pi_3QabcDEFghiJKLmnoPQRstuv',
  String? refundStatus,
  double refundAmount = 0,
  double refundPendingAmount = 0,
}) => Order(
  id: id,
  userId: 'buyer',
  status: status,
  total: total,
  createdAt: _now,
  stripePaymentIntentId: paymentId,
  refundStatus: refundStatus,
  refundAmount: refundAmount,
  refundPendingAmount: refundPendingAmount,
  items: const [
    OrderItem(productId: 'p', productName: 'Koi food', quantity: 1, unitPrice: 120),
  ],
);

class _Orders extends AdminOrdersPagedNotifier {
  _Orders(this.orders);
  final List<Order> orders;

  @override
  AsyncValue<PagedListState<Order>> build() =>
      AsyncData(PagedListState(items: orders, hasMore: false));
}

void main() {
  group('orderPaymentLine', () {
    test('says what was paid and what went back', () {
      expect(orderPaymentLine(_order()).text, 'Paid S\$120.00');
      expect(
        orderPaymentLine(_order(status: OrderStatus.delivered)).text,
        'Paid S\$120.00',
      );
      expect(
        orderPaymentLine(
          _order(refundStatus: 'partially_refunded', refundAmount: 40),
        ).text,
        'Refunded S\$40.00 of S\$120.00',
      );
      expect(
        orderPaymentLine(
          _order(
            status: OrderStatus.refunded,
            refundStatus: 'succeeded',
            refundAmount: 120,
          ),
        ).text,
        'Refunded S\$120.00',
      );
      expect(
        orderPaymentLine(
          _order(status: OrderStatus.refunded, refundStatus: 'succeeded'),
        ).text,
        'Refunded',
      );
    });

    test('unpaid and cancelled-before-payment orders read Unpaid', () {
      expect(
        orderPaymentLine(_order(status: OrderStatus.pending)).text,
        'Unpaid',
      );
      expect(
        orderPaymentLine(
          _order(status: OrderStatus.cancelled, paymentId: null),
        ).text,
        'Unpaid',
      );
    });

    test('a refund still in flight or stuck outranks the amounts', () {
      final pending = orderPaymentLine(
        _order(refundStatus: 'pending', refundPendingAmount: 120),
      );
      expect(pending.text, 'Refund pending');
      expect(pending.tone, PaymentLineTone.pending);
      // Part returned, the rest not confirmed yet.
      expect(
        orderPaymentLine(
          _order(
            refundStatus: 'partially_refunded',
            refundAmount: 40,
            refundPendingAmount: 20,
          ),
        ).text,
        'Refund pending',
      );
      final stuck = orderPaymentLine(
        _order(status: OrderStatus.refunded, refundStatus: 'requires_action'),
      );
      expect(stuck.text, 'Refund needs attention');
      expect(stuck.tone, PaymentLineTone.problem);
      expect(
        orderPaymentLine(_order(refundStatus: 'failed')).text,
        'Refund failed',
      );
      // A refund that was called off leaves the order simply paid.
      expect(
        orderPaymentLine(_order(refundStatus: 'canceled')).text,
        'Paid S\$120.00',
      );
    });
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('admin order cards carry a payment line and the hub has no '
        'Payments tab at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(320, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final orders = [
        _order(id: 'paid-12345'),
        _order(
          id: 'part-12345',
          refundStatus: 'partially_refunded',
          refundAmount: 40,
        ),
        _order(id: 'unpaid-123', status: OrderStatus.pending),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminOrdersPagedProvider.overrideWith(() => _Orders(orders)),
            fulfillmentOrdersProvider.overrideWith((ref) async => <Order>[]),
            easyParcelConnectedProvider.overrideWith((ref) async => false),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const AdminOrdersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Tab, 'Payments'), findsNothing);
      expect(find.byType(Tab), findsNWidgets(2));
      for (final text in [
        'Paid S\$120.00',
        'Refunded S\$40.00 of S\$120.00',
        'Unpaid',
      ]) {
        await tester.scrollUntilVisible(
          find.text(text),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text(text), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  group('admin order payment section', () {
    Future<void> show(WidgetTester tester, Order order, {double scale = 1}) {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminOrderPaymentSection(order: order),
            ),
          ),
        ),
      );
    }

    testWidgets('tapping the payment id copies the whole id', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final handle = tester.ensureSemantics();
      await show(
        tester,
        _order(refundStatus: 'partially_refunded', refundAmount: 40),
        scale: 2,
      );
      expect(find.text('PAYMENT'), findsOneWidget);
      expect(find.text('Stripe'), findsOneWidget);
      expect(find.text('Refunded S\$40.00 of S\$120.00'), findsOneWidget);
      expect(find.text('S\$80.00'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Copy payment ID pi_3QabcDEFghiJKLmnoPQRstuv'),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byType(InkWell)).height,
        greaterThanOrEqualTo(48),
      );

      await tester.tap(find.text('pi_3QabcDEFghiJKLmnoPQRstuv'));
      await tester.pump();
      expect(copied, 'pi_3QabcDEFghiJKLmnoPQRstuv');
      expect(find.text('Payment ID copied'), findsOneWidget);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('an order that never reached Stripe has no id row', (
      tester,
    ) async {
      await show(
        tester,
        _order(status: OrderStatus.pending, paymentId: null),
      );
      expect(find.text('No online payment'), findsOneWidget);
      expect(find.text('Unpaid'), findsOneWidget);
      expect(find.text('Payment ID'), findsNothing);
    });
  });

  for (final role in [UserRole.customer, UserRole.owner]) {
    testWidgets('the order screen shows the payment section to staff only '
        '($role)', (tester) async {
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final order = _order();
      final userId = role == UserRole.customer ? 'buyer' : 'admin';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => const Stream.empty()),
            currentUserIdProvider.overrideWithValue(userId),
            orderByIdProvider(order.id).overrideWith((ref) async => order),
            currentAppUserProvider.overrideWith(
              (ref) async => AppUser(id: userId, role: role),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: OrderDetailScreen(orderId: order.id, order: order),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final staff = role != UserRole.customer;
      expect(
        find.byType(AdminOrderPaymentSection),
        staff ? findsOneWidget : findsNothing,
      );
      expect(
        find.textContaining('pi_3Qabc'),
        staff ? findsOneWidget : findsNothing,
      );
    });
  }
}
