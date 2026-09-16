import 'package:intl/intl.dart';

import '../../../shared/models/order.dart';

/// Builds a plain-text tax invoice / receipt for [order] — shared via
/// `share_plus` from the order detail screen. Deliberately plain text
/// rather than a rendered PDF: it's readable, easy to forward, and needs
/// no extra rendering dependency.
String buildReceiptText({
  required Order order,
  required Map<String, dynamic> settings,
}) {
  final shopName = settings['shop_name'] as String? ?? 'Marugen Koi Farm';
  final shopPhone = settings['shop_phone'] as String?;
  final shopAddress = settings['shop_address'] as String?;
  final gstPercent = (settings['gst_percent'] as num?)?.toDouble() ?? 0;
  final gstIncluded = settings['gst_included_in_price'] as bool? ?? true;

  final discount = order.discountAmount ?? 0;
  final netTotal = order.total; // total already reflects the discount applied at checkout
  final subtotalBeforeGst = gstIncluded ? netTotal / (1 + gstPercent / 100) : netTotal;
  final gstAmount = gstIncluded ? netTotal - subtotalBeforeGst : netTotal * gstPercent / 100;

  final buffer = StringBuffer();
  buffer.writeln(shopName);
  if (shopAddress != null && shopAddress.isNotEmpty) buffer.writeln(shopAddress);
  if (shopPhone != null && shopPhone.isNotEmpty) buffer.writeln('Tel: $shopPhone');
  buffer.writeln('=' * 32);
  buffer.writeln('TAX INVOICE / RECEIPT');
  buffer.writeln('Order #: ${order.id}');
  buffer.writeln('Date: ${DateFormat.yMMMd().add_jm().format(order.createdAt)}');
  if (order.stripePaymentIntentId != null && order.stripePaymentIntentId!.isNotEmpty) {
    buffer.writeln('Payment ID: ${order.stripePaymentIntentId}');
  }
  buffer.writeln('=' * 32);
  buffer.writeln('ITEMS');
  for (final item in order.items) {
    buffer.writeln(item.variantLabel != null && item.variantLabel!.isNotEmpty
        ? '${item.productName} — ${item.variantLabel}'
        : item.productName);
    buffer.writeln(
        '  ${item.quantity} x S\$${item.unitPrice.toStringAsFixed(2)} = S\$${item.subtotal.toStringAsFixed(2)}');
  }
  buffer.writeln('-' * 32);
  buffer.writeln('Subtotal (excl. GST): S\$${subtotalBeforeGst.toStringAsFixed(2)}');
  if (discount > 0) {
    buffer.writeln('Promo discount${order.promoCode != null ? ' (${order.promoCode})' : ''}: '
        '-S\$${discount.toStringAsFixed(2)}');
  }
  buffer.writeln('GST (${gstPercent.toStringAsFixed(0)}%): S\$${gstAmount.toStringAsFixed(2)}');
  buffer.writeln('TOTAL: S\$${netTotal.toStringAsFixed(2)}');
  buffer.writeln('=' * 32);
  buffer.writeln('Thank you for shopping with $shopName!');
  return buffer.toString();
}
