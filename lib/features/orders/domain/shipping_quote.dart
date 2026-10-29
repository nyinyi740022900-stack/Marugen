/// Server-owned, already-converted SGD shipping allocation. Monetary values
/// stay in cents so the displayed buyer charge matches payment creation.
class ShippingQuote {
  final String quoteId;
  final DateTime expiresAt;
  final String fulfillmentMethod;
  final String carrierName;
  final int totalShippingCents;
  final int buyerShippingCents;
  final int sellerShippingCents;
  final String policy;
  final String sourceCurrency;
  final double sourceAmount;
  final double fxRate;
  final String? fxDate;
  const ShippingQuote({
    required this.quoteId,
    required this.expiresAt,
    required this.fulfillmentMethod,
    required this.carrierName,
    required this.totalShippingCents,
    required this.buyerShippingCents,
    required this.sellerShippingCents,
    required this.policy,
    required this.sourceCurrency,
    required this.sourceAmount,
    required this.fxRate,
    this.fxDate,
  });
  bool get isShopDelivery => fulfillmentMethod == 'shop_delivery';
  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());
  factory ShippingQuote.fromMap(Map<String, dynamic> map) {
    final id = map['quote_id'];
    final expires = DateTime.tryParse(map['expires_at']?.toString() ?? '');
    final total = map['total_shipping_cents'];
    final buyer = map['buyer_shipping_cents'];
    final seller = map['seller_shipping_cents'];
    final method = map['fulfillment_method'];
    final policy = map['shipping_cost_policy'];
    final shop = method == 'shop_delivery' && policy == 'seller_100';
    final source = map['source_currency'] ?? (shop ? 'SGD' : null);
    final sourceAmount = map['source_shipping_amount'] ?? (shop ? 0 : null);
    final fxRate = map['fx_rate'] ?? (shop ? 1 : null);
    final valid =
        id is String &&
        id.isNotEmpty &&
        expires != null &&
        map['currency'] == 'SGD' &&
        total is int &&
        buyer is int &&
        seller is int &&
        total >= 0 &&
        buyer >= 0 &&
        seller >= 0 &&
        buyer + seller == total &&
        (method == 'shop_delivery' && policy == 'seller_100' && buyer == 0 ||
            method == 'courier' &&
                policy == 'shared_50_50' &&
                map['carrier_name'] is String &&
                (map['carrier_name'] as String).trim().isNotEmpty &&
                total > 0 &&
                buyer == total ~/ 2 &&
                seller == total - buyer) &&
        const {'SGD', 'MYR'}.contains(source) &&
        sourceAmount is num &&
        sourceAmount.isFinite &&
        sourceAmount >= 0 &&
        fxRate is num &&
        fxRate.isFinite &&
        fxRate > 0 &&
        (source != 'MYR' ||
            DateTime.tryParse(map['fx_date']?.toString() ?? '') != null);
    if (!valid) {
      throw const FormatException(
        'Could not verify the SGD delivery quote. Please refresh.',
      );
    }
    return ShippingQuote(
      quoteId: id,
      expiresAt: expires,
      fulfillmentMethod: method as String,
      carrierName:
          map['carrier_name']?.toString() ??
          (method == 'shop_delivery' ? 'Shop delivery' : 'Courier'),
      totalShippingCents: total,
      buyerShippingCents: buyer,
      sellerShippingCents: seller,
      policy: policy as String,
      sourceCurrency: source as String,
      sourceAmount: (sourceAmount).toDouble(),
      fxRate: (fxRate).toDouble(),
      fxDate: map['fx_date']?.toString(),
    );
  }
}
