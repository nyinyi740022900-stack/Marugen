import 'dart:convert';

import 'package:marugen_app/features/orders/domain/shipping_quote.dart';

ShippingQuote fixtureShippingQuote(String key, {int total = 405}) {
  final request = jsonDecode(key) as Map;
  final items = request['items'] as List;
  final shop = items.any((item) => item['product_id'] == 'koi');
  return ShippingQuote.fromMap({
    'quote_id': 'quote-${request['shipping_address']['postal_code']}',
    'expires_at': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 15))
        .toIso8601String(),
    'currency': 'SGD',
    'fulfillment_method': shop ? 'shop_delivery' : 'courier',
    'carrier_name': shop ? 'Shop delivery' : 'TracX Logis',
    'total_shipping_cents': shop ? 0 : total,
    'buyer_shipping_cents': shop ? 0 : total ~/ 2,
    'seller_shipping_cents': shop ? 0 : total - total ~/ 2,
    'shipping_cost_policy': shop ? 'seller_100' : 'shared_50_50',
    'source_currency': 'SGD',
    'source_shipping_amount': shop ? 0 : total / 100,
    'fx_rate': 1,
    'fx_date': '2026-10-20',
  });
}
