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
