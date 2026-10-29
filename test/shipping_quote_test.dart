import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/orders/domain/shipping_quote.dart';

Map<String, dynamic> quoteJson({
  String currency = 'SGD',
  int total = 405,
  int buyer = 202,
  int seller = 203,
  String policy = 'shared_50_50',
}) => {
  'quote_id': 'quote-1',
  'expires_at': '2099-01-01T00:00:00Z',
  'currency': currency,
  'fulfillment_method': policy == 'seller_100' ? 'shop_delivery' : 'courier',
  'carrier_name': policy == 'seller_100' ? 'Shop delivery' : 'TracX Logis',
  'total_shipping_cents': total,
  'buyer_shipping_cents': buyer,
  'seller_shipping_cents': seller,
  'shipping_cost_policy': policy,
  'source_currency': 'SGD',
  'source_shipping_amount': total / 100,
  'fx_rate': 1,
  'fx_date': '2026-10-19',
};
void main() {
  test('SGD shipping snapshot preserves odd-cent seller remainder', () {
    final quote = ShippingQuote.fromMap(quoteJson());
    expect(quote.buyerShippingCents, 202);
    expect(quote.sellerShippingCents, 203);
    expect(quote.totalShippingCents, 405);
    expect(quote.carrierName, 'TracX Logis');
  });
  test('shop delivery charges buyer nothing', () {
    final quote = ShippingQuote.fromMap(
      quoteJson(total: 0, buyer: 0, seller: 0, policy: 'seller_100'),
    );
    expect(quote.isShopDelivery, isTrue);
    expect(quote.buyerShippingCents, 0);
  });
  test('shop quote without courier or FX metadata remains free for buyer', () {
    final json = quoteJson(total: 0, buyer: 0, seller: 0, policy: 'seller_100')
      ..['source_currency'] = null
      ..['source_shipping_amount'] = null
      ..['fx_rate'] = null
      ..['fx_date'] = null
      ..['carrier_name'] = null;
    expect(ShippingQuote.fromMap(json).isShopDelivery, isTrue);
  });
  test('foreign display currency and invalid allocations fail closed', () {
    expect(
      () => ShippingQuote.fromMap(quoteJson(currency: 'MYR')),
      throwsFormatException,
    );
    expect(
      () => ShippingQuote.fromMap(quoteJson(buyer: 203, seller: 203)),
      throwsFormatException,
    );
    expect(
      () => ShippingQuote.fromMap(quoteJson(buyer: 405, seller: 0)),
      throwsFormatException,
    );
    expect(
      () => ShippingQuote.fromMap(quoteJson(buyer: -1, seller: 406)),
      throwsFormatException,
    );
  });
  test('all named couriers support SGD checkout but blank identities fail', () {
    expect(
      ShippingQuote.fromMap(quoteJson()..['carrier_name'] = 'J&T Express')
          .carrierName,
      'J&T Express',
    );
    expect(
      () => ShippingQuote.fromMap(quoteJson()..['carrier_name'] = '  '),
      throwsFormatException,
    );
  });
  test('MYR conversion must include an auditable FX snapshot', () {
    final json = quoteJson()
      ..['source_currency'] = 'MYR'
      ..['source_shipping_amount'] = 13.49
      ..['fx_rate'] = 0.3
      ..['fx_date'] = '2026-10-19';
    expect(ShippingQuote.fromMap(json).sourceCurrency, 'MYR');
    json.remove('fx_rate');
    expect(() => ShippingQuote.fromMap(json), throwsFormatException);
  });
  test('expired quote cannot enable payment', () {
    final json = quoteJson()..['expires_at'] = '2020-01-01T00:00:00Z';
    expect(ShippingQuote.fromMap(json).isExpired, isTrue);
  });
}
