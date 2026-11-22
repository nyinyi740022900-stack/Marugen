/// Matches server money stages: subtotal -> rounded discount -> net -> GST.
/// Shipping is already tax-inclusive and is added once after merchandise tax.
class CheckoutTotals {
  final int subtotalCents;
  final int discountCents;
  final int gstCents;
  final int merchandiseCents;
  const CheckoutTotals(
    this.subtotalCents,
    this.discountCents,
    this.gstCents,
    this.merchandiseCents,
  );
  int payableCents(int buyerShippingCents) =>
      merchandiseCents + buyerShippingCents;
}

CheckoutTotals checkoutTotals({
  required double subtotal,
  required double discount,
  required double gstPercent,
  required bool gstIncluded,
}) {
  final subtotalCents = (subtotal * 100).round();
  final discountCents = (discount * 100).round().clamp(0, subtotalCents);
  final netCents = subtotalCents - discountCents;
  final taxCents = gstIncluded
      ? (netCents - netCents / (1 + gstPercent / 100)).round()
      : (netCents * gstPercent / 100).round();
  return CheckoutTotals(
    subtotalCents,
    discountCents,
    taxCents,
    gstIncluded ? netCents : netCents + taxCents,
  );
}

/// A GST rate without trailing zeros: 9 -> "9", 8.5 -> "8.5".
String gstPercentText(double percent) => percent == percent.roundToDouble()
    ? percent.toStringAsFixed(0)
    : percent.toString();

/// The note under a total whose prices already include GST, so the rows
/// above it add up to the total. Shared by checkout and the order page.
String includesGstLine({required double percent, required double amount}) =>
    'Includes GST (${gstPercentText(percent)}%) of S\$${amount.toStringAsFixed(2)}';

/// The label of the checkout total. GST is named only when a rate above 0
/// is inside the prices: a shop that is not GST-registered (0%) must never
/// show the word.
String checkoutTotalLabel({
  required double gstPercent,
  required bool gstIncluded,
}) => gstPercent > 0 && gstIncluded ? 'Total (incl. GST)' : 'Total';

/// The caption under the admin sales figure. [settings] is null while the
/// shop settings are loading or failed; GST is then not mentioned rather
/// than guessed.
String salesIncludesCaption(Map<String, dynamic>? settings) =>
    ((settings?['gst_percent'] as num?)?.toDouble() ?? 0) > 0
    ? 'Includes delivery fees and GST'
    : 'Includes delivery fees';
