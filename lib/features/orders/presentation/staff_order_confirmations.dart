import 'package:flutter/material.dart';

import '../../../shared/models/order.dart';
import '../../../shared/utils/price_format.dart';
import '../../../shared/widgets/confirm_dialog.dart';

/// The confirmations staff see before an order action that cannot be taken
/// back. Orders > All, Orders > Fulfillment, Home and the order page all
/// ask through these, so the same action reads the same everywhere.

/// "Refund S$84.50 to the customer's original payment method?" A refund is
/// always the whole order (stripe-refund), so the message and the button
/// both name the amount that will leave the account.
Future<bool> confirmRefundOrder(BuildContext context, Order order) {
  final amount = formatPrice(order.total);
  return confirmDestructiveAction(
    context,
    title: 'Refund this order?',
    message: "Refund $amount to the customer's original payment method?",
    confirmLabel: 'Refund $amount',
    cancelLabel: 'Back',
  );
}

/// Cancelling an unpaid order. The dismiss button is "Keep order": a plain
/// "Cancel" beside "Cancel order" would read as the action itself.
Future<bool> confirmCancelOrder(BuildContext context, Order order) =>
    confirmDestructiveAction(
      context,
      title: 'Cancel this order?',
      message:
          'Order #${order.displayNumber} will be cancelled and any reserved '
          'stock released. This cannot be undone.',
      confirmLabel: 'Cancel order',
      cancelLabel: 'Keep order',
    );

/// Marking an order delivered. [carrierOverride] is the by-hand route for a
/// courier order whose carrier never reported the delivery.
Future<bool> confirmMarkDelivered(
  BuildContext context,
  Order order, {
  bool carrierOverride = false,
}) => confirmAction(
  context,
  title: 'Mark as delivered?',
  message:
      'Confirm that order #${order.displayNumber} has actually been handed '
      'to the recipient. The customer will be notified. This cannot be '
      'undone.'
      '${carrierOverride ? '\n\nUse only if the carrier shows it delivered.' : ''}',
  confirmLabel: 'Mark Delivered',
);
