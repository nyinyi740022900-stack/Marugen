import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';
import '../../../shared/utils/error_message.dart';
import '../../admin/admin_shell.dart'
    show adminTabIndexProvider, kAdminOrdersTab;
import 'orders_providers.dart';
import 'staff_order_confirmations.dart';

/// The one thing staff should do next with an order, as offered on the
/// order page. Mirrors the Fulfillment card's own choice of primary action
/// (admin_delivery_screen.dart `_primaryAction`): anything that needs the
/// courier sheet, tracking entry or a delivery review is "Manage delivery",
/// which opens that card.
enum StaffOrderAction { startPacking, manageDelivery, markDelivered }

StaffOrderAction? staffPrimaryActionFor(Order order) {
  // The cancellation panel on the same page owns a held order.
  if (order.hasCancellationHold) return null;
  final hasBooking =
      order.hasParcelPlan ||
      order.trackingRegistered ||
      (order.qxpressTrackingNo?.isNotEmpty ?? false) ||
      order.trackingProvider == 'easyparcel';
  switch (order.status) {
    case OrderStatus.paid:
      return order.needsDeliveryReview ||
              order.needsBookingAttention ||
              hasBooking
          ? StaffOrderAction.manageDelivery
          : StaffOrderAction.startPacking;
    case OrderStatus.packing:
      return StaffOrderAction.manageDelivery;
    case OrderStatus.shipped:
      return order.isShopDelivery
          ? StaffOrderAction.markDelivered
          : StaffOrderAction.manageDelivery;
    case OrderStatus.pending:
    case OrderStatus.delivered:
    case OrderStatus.cancelled:
    case OrderStatus.refunded:
      return null;
  }
}

/// Same rule as the admin Orders card: a refund only while none exists.
bool staffCanRefund(Order order) =>
    !order.hasCancellationHold &&
    order.canRequestRefund &&
    validNextStatuses(order.status).contains(OrderStatus.refunded);

/// Same rule as the admin Orders card: only an unpaid order can be cancelled
/// outright; a paid one is refunded.
bool staffCanCancel(Order order) =>
    !order.hasCancellationHold &&
    validNextStatuses(order.status).contains(OrderStatus.cancelled);

/// Staff's next action on the order page: one primary button by state plus
/// an overflow for refund / cancel. Calls the same repository methods, with
/// the same confirmations, as the admin Orders and Fulfillment screens.
class StaffOrderActionBar extends ConsumerStatefulWidget {
  final Order order;
  const StaffOrderActionBar({super.key, required this.order});

  @override
  ConsumerState<StaffOrderActionBar> createState() =>
      _StaffOrderActionBarState();
}

enum _Overflow { refund, cancel }

class _StaffOrderActionBarState extends ConsumerState<StaffOrderActionBar> {
  bool _busy = false;

  Order get _order => widget.order;

  Future<void> _run(Future<void> Function() write, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await write();
      if (mounted && success != null) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorMessage(
                e,
                fallback: 'Could not complete this action. Refresh the order and try again.',
                context: 'admin.orderDetail',
              ),
            ),
          ),
        );
      }
    } finally {
      // A failed request can still have changed the order: always re-read.
      if (mounted) {
        refreshAdminOrders(ref);
        ref.invalidate(myOrdersProvider);
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _startPacking() => _run(
    () => ref
        .read(orderRepositoryProvider)
        .updateOrderStatus(_order.id, OrderStatus.packing),
    success:
        '#${_order.displayNumber} → ${orderStatusLabel(OrderStatus.packing)}',
  );

  void _manageDelivery() {
    ref.read(focusFulfillmentOrderProvider.notifier).state = _order.id;
    ref.read(requestedOrdersTabProvider.notifier).state = 1;
    ref.read(adminTabIndexProvider.notifier).state = kAdminOrdersTab;
    context.go('/admin');
  }

  Future<void> _markDelivered() async {
    if (_busy) return;
    final confirmed = await confirmMarkDelivered(context, _order);
    if (!confirmed || !mounted) return;
    await _run(
      () => ref
          .read(orderRepositoryProvider)
          .updateOrderStatus(_order.id, OrderStatus.delivered),
      success:
          '#${_order.displayNumber} → ${orderStatusLabel(OrderStatus.delivered)}',
    );
  }

  Future<void> _refund() async {
    if (_busy) return;
    final confirmed = await confirmRefundOrder(context, _order);
    if (!confirmed || !mounted) return;
    await _run(
      () => ref.read(orderRepositoryProvider).refundOrder(_order.id),
      success: 'Refund requested for #${_order.displayNumber}',
    );
  }

  Future<void> _cancel() async {
    if (_busy) return;
    final confirmed = await confirmCancelOrder(context, _order);
    if (!confirmed || !mounted) return;
    await _run(
      () => ref
          .read(orderRepositoryProvider)
          .updateOrderStatus(_order.id, OrderStatus.cancelled),
      success:
          '#${_order.displayNumber} → ${orderStatusLabel(OrderStatus.cancelled)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = staffPrimaryActionFor(_order);
    final canRefund = staffCanRefund(_order);
    final canCancel = staffCanCancel(_order);
    if (primary == null && !canRefund && !canCancel) {
      return const SizedBox.shrink();
    }
    final (label, icon, onPressed) = switch (primary) {
      StaffOrderAction.startPacking => (
        'Start packing',
        Icons.inventory_2_outlined,
        _startPacking,
      ),
      StaffOrderAction.manageDelivery => (
        'Manage delivery',
        Icons.local_shipping_outlined,
        _manageDelivery,
      ),
      StaffOrderAction.markDelivered => (
        'Mark as delivered',
        Icons.check_circle_outline,
        _markDelivered,
      ),
      null => (null, null, null),
    };
    final overflow = canRefund || canCancel
        ? PopupMenuButton<_Overflow>(
            tooltip: 'More order actions',
            enabled: !_busy,
            onSelected: (choice) => switch (choice) {
              _Overflow.refund => _refund(),
              _Overflow.cancel => _cancel(),
            },
            itemBuilder: (context) => [
              if (canRefund)
                const PopupMenuItem(
                  value: _Overflow.refund,
                  child: Text('Refund order…'),
                ),
              if (canCancel)
                const PopupMenuItem(
                  value: _Overflow.cancel,
                  child: Text('Cancel order…'),
                ),
            ],
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppPalette.of(context).border),
              ),
              child: Icon(Icons.more_horiz, color: AppPalette.of(context).text),
            ),
          )
        : null;
    return Row(
      children: [
        Expanded(
          child: label == null
              ? Text(
                  'No delivery step is waiting on this order.',
                  style: TextStyle(color: AppPalette.of(context).textMuted),
                )
              : ElevatedButton.icon(
                  onPressed: _busy ? null : onPressed,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : Icon(icon, size: 18),
                  label: Text(label),
                ),
        ),
        if (overflow != null) ...[
          const SizedBox(width: AppSpacing.sm),
          overflow,
        ],
      ],
    );
  }
}
