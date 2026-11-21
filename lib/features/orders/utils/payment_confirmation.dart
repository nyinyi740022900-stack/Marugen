import '../../../shared/models/order.dart';

/// PaymentSheet completion is provisional until the owning account's order
/// reflects a paid status. Temporary read failures do not restart payment.
Future<bool> confirmOrderPayment({
  required String orderId,
  required String? ownerId,
  required bool Function() ownsCheckout,
  required Future<Order?> Function(String) fetchOrder,
  Future<void> Function(Duration)? delay,
}) async {
  if (ownerId == null) return false;
  final wait = delay ?? (duration) => Future<void>.delayed(duration);
  for (var attempt = 0; attempt < 10; attempt++) {
    if (!ownsCheckout()) return false;
    Order? order;
    try {
      order = await fetchOrder(orderId);
    } catch (_) {
      // A lost confirmation read must never offer a second payment.
    }
    if (!ownsCheckout()) return false;
    if (order?.id == orderId &&
        order?.userId == ownerId &&
        paidOrderStatuses.contains(order?.status)) {
      return true;
    }
    if (attempt < 9) await wait(const Duration(milliseconds: 600));
  }
  return false;
}

/// The statuses that mean the server has recorded the payment.
const paidOrderStatuses = {
  OrderStatus.paid,
  OrderStatus.packing,
  OrderStatus.shipped,
  OrderStatus.delivered,
};

/// How long, and how often, an order screen keeps re-checking an order whose
/// payment sheet succeeded but whose webhook has not landed yet: seven
/// checks backing off over 60 seconds.
const paymentConfirmationBackoff = [
  Duration(seconds: 2),
  Duration(seconds: 3),
  Duration(seconds: 5),
  Duration(seconds: 8),
  Duration(seconds: 12),
  Duration(seconds: 15),
  Duration(seconds: 15),
];

/// A reused attempt may already have completed. Its existing order replaces
/// the native payment flow even when no client secret is returned.
///
/// Returns true only when the payment sheet itself ran and reported success
/// for the account that started it. A dismissed or failed sheet throws, and
/// a skipped sheet returns false — neither may be shown as "payment
/// received".
Future<bool> presentPendingPayment({
  required Map<String, dynamic> intent,
  required bool Function() ownsCheckout,
  required Future<void> Function(String) presentPayment,
}) async {
  if (!ownsCheckout() || intent['paymentStatus'] != null) return false;
  final secret = intent['clientSecret'];
  if (secret is! String || secret.isEmpty) {
    throw const FormatException(
      'Payment setup did not return a client secret.',
    );
  }
  await presentPayment(secret);
  return ownsCheckout();
}
