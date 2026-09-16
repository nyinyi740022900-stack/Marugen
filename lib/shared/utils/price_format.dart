/// Single place that turns a number into the customer-facing "S$12.50"
/// string so every screen (cards, detail, cart, checkout, orders,
/// receipts) formats money the same way.
String formatPrice(double amount) => 'S\$${amount.toStringAsFixed(2)}';
