import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/widgets/support_contact_picker.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/order_repository.dart' show CancellationRefundNeedsAttention;
import 'orders_providers.dart';

/// Customer intent never directly cancels a paid order or labels a refund paid.
class OrderCancellationPanel extends ConsumerStatefulWidget {
  final Order order;
  const OrderCancellationPanel({super.key, required this.order});
  @override
  ConsumerState<OrderCancellationPanel> createState() =>
      _OrderCancellationPanelState();
}

class _OrderCancellationPanelState
    extends ConsumerState<OrderCancellationPanel> {
  bool _busy = false;

  bool _authorized(String actor, String action) {
    final profile = ref.read(currentAppUserProvider);
    final snapshot = ref.read(orderByIdProvider(widget.order.id));
    if (ref.read(currentUserIdProvider) != actor ||
        profile.isLoading ||
        profile.hasError ||
        profile.valueOrNull?.id != actor ||
        snapshot.isLoading ||
        snapshot.hasError) {
      return false;
    }
    final order = snapshot.valueOrNull;
    if (order?.id != widget.order.id) return false;
    final admin = profile.valueOrNull!.role.isAdmin;
    if (action == 'request') {
      return !admin && order!.userId == actor && order.canRequestCancellation;
    }
    return admin &&
        (action == 'refresh'
            ? order!.cancellationRequest?.status == 'approved'
            : action == 'approve'
            ? const {
                'requested',
                'approved',
              }.contains(order!.cancellationRequest?.status)
            : order!.cancellationRequest?.status == 'requested');
  }

  Future<void> _act(String action) async {
    final actor = ref.read(currentUserIdProvider);
    if (_busy ||
        actor == null ||
        ModalRoute.of(context)?.isCurrent != true ||
        !_authorized(actor, action)) {
      return;
    }
    String? note;
    if (action != 'refresh') {
      var noteInput = '';
      final form = GlobalKey<FormState>();
      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => Consumer(
          builder: (ctx, dialogRef, _) {
            dialogRef.watch(currentUserIdProvider);
            dialogRef.watch(currentAppUserProvider);
            dialogRef.watch(orderByIdProvider(widget.order.id));
            final eligible = mounted && _authorized(actor, action);
            return AlertDialog(
              title: Text(
                action == 'request'
                    ? 'Request cancellation?'
                    : action == 'reject'
                    ? 'Decline cancellation?'
                    : 'Approve cancellation & refund?',
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action == 'request'
                            ? 'Your order is not cancelled yet. Delivery will pause while the shop reviews your request. If approved, your payment will be refunded.'
                            : action == 'reject'
                            ? 'The order will continue. Explain the decision to the customer.'
                            : 'This issues a real refund to the customer’s original payment method. Delivery stays paused. Payment provider confirmation is required before the order shows Refunded.',
                      ),
                      if (action != 'approve') ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          onChanged: (value) => noteInput = value,
                          maxLength: 500,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: action == 'request'
                                ? 'Reason (optional)'
                                : 'Reason for declining',
                          ),
                          validator: (value) =>
                              action == 'reject' &&
                                  (value?.trim().isEmpty ?? true)
                              ? 'Enter a reason for the customer.'
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Keep order'),
                ),
                TextButton(
                  onPressed: eligible
                      ? () {
                          if (form.currentState!.validate()) {
                            Navigator.pop(ctx, true);
                          }
                        }
                      : null,
                  child: Text(
                    action == 'request'
                        ? 'Send request'
                        : action == 'reject'
                        ? 'Decline request'
                        : 'Confirm refund',
                  ),
                ),
              ],
            );
          },
        ),
      );
      note = noteInput.trim();
      if (!mounted ||
          approved != true ||
          ModalRoute.of(context)?.isCurrent != true ||
          !_authorized(actor, action)) {
        return;
      }
    }
    setState(() => _busy = true);
    final repository = ref.read(orderRepositoryProvider);
    try {
      await repository.manageCancellation(
        widget.order.id,
        action,
        reason: note?.isEmpty == true ? null : note,
      );
      if (!mounted || ref.read(currentUserIdProvider) != actor) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'request'
                ? 'Cancellation request sent. The shop will review it.'
                : action == 'reject'
                ? 'Cancellation declined. The order can continue.'
                : 'Decision saved. Check the order for the confirmed refund status.',
          ),
        ),
      );
    } on CancellationRefundNeedsAttention {
      if (mounted &&
          ref.read(currentUserIdProvider) == actor &&
          ModalRoute.of(context)?.isCurrent == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cancellation is approved and delivery stays paused. The refund needs attention; check its status before retrying.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted && ref.read(currentUserIdProvider) == actor) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not confirm the result. Refresh this order before trying again or contact support.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (ref.read(currentUserIdProvider) == actor) {
          ref.invalidate(orderByIdProvider(widget.order.id));
          ref.invalidate(myOrdersProvider);
          if (ref.read(currentAppUserProvider).valueOrNull?.role.isAdmin ==
              true) {
            refreshAdminOrders(ref);
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(currentUserIdProvider);
    final profile = ref.watch(currentAppUserProvider);
    final snapshot = ref.watch(orderByIdProvider(widget.order.id));
    if (actor == null ||
        profile.isLoading ||
        profile.hasError ||
        profile.valueOrNull?.id != actor) {
      return const SizedBox.shrink();
    }
    final admin = profile.valueOrNull!.role.isAdmin;
    final order = snapshot.valueOrNull;
    if (order == null ||
        order.id != widget.order.id ||
        (!admin && order.userId != actor)) {
      return const SizedBox.shrink();
    }
    final request = order.cancellationRequest;
    if (request == null && admin) return const SizedBox.shrink();
    if (request == null &&
        !order.canRequestCancellation &&
        !const {
          OrderStatus.paid,
          OrderStatus.packing,
          OrderStatus.shipped,
        }.contains(order.status)) {
      return const SizedBox.shrink();
    }
    final enabled = !_busy && !snapshot.isLoading && !snapshot.hasError;
    final completed =
        order.status == OrderStatus.refunded &&
        order.refundStatus == 'succeeded';
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (request == null && !order.canRequestCancellation) ...[
            const Text(
              'Delivery is already being arranged. Contact support about a cancellation.',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => showSupportContactPicker(
                context,
                message: 'I need help with order #${order.displayNumber}.',
              ),
              icon: const Icon(Icons.support_agent, size: 20),
              label: const Text('Contact support'),
            ),
          ] else if (request == null) ...[
            OutlinedButton.icon(
              onPressed: enabled ? () => _act('request') : null,
              icon: const Icon(Icons.cancel_outlined, size: 20),
              label: const Text('Request cancellation'),
            ),
            const SizedBox(height: 8),
            Text(
              'The shop reviews paid-order cancellations before a refund is issued.',
              style: TextStyle(color: palette.textMuted),
            ),
          ] else ...[
            Text(
              completed
                  ? 'Cancellation completed'
                  : request.status == 'requested'
                  ? 'Cancellation requested'
                  : request.status == 'rejected'
                  ? 'Cancellation declined'
                  : 'Cancellation approved',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              completed
                  ? 'Your payment has been refunded to the original payment method. Your bank may take additional time to show the credit.'
                  : request.status == 'requested'
                  ? admin
                        ? 'Delivery is paused. Review the customer’s request before continuing.'
                        : 'Delivery is paused while the shop reviews your request. No refund has been confirmed yet.'
                  : request.status == 'rejected'
                  ? 'The order will continue. Contact support if you need help.'
                  : completed
                  ? 'Your payment has been refunded to the original payment method. Your bank may take additional time to show the credit.'
                  : '${order.refundStatusLabel ?? 'Refund is being arranged'}. Delivery remains paused until the refund is resolved.',
            ),
            if (request.reason?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Customer reason: ${request.reason}'),
              ),
            if (request.reviewNote?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Shop response: ${request.reviewNote}'),
              ),
            const SizedBox(height: 12),
            if (admin && request.status == 'requested') ...[
              ElevatedButton(
                onPressed: enabled ? () => _act('approve') : null,
                child: const Text('Approve & refund'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: enabled ? () => _act('reject') : null,
                child: const Text('Decline request'),
              ),
            ],
            if (admin && request.status == 'approved' && !completed) ...[
              OutlinedButton(
                onPressed: enabled ? () => _act('refresh') : null,
                child: const Text('Check refund'),
              ),
              if (order.refundStatus == null)
                TextButton(
                  onPressed: enabled ? () => _act('approve') : null,
                  child: const Text('Retry approved refund'),
                ),
            ],
            if (!admin)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => showSupportContactPicker(
                        context,
                        message:
                            'I need help with cancellation for order #${order.displayNumber}.',
                      ),
                icon: const Icon(Icons.support_agent, size: 20),
                label: const Text('Contact support'),
              ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
