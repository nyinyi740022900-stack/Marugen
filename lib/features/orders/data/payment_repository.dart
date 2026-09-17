import '../../../core/supabase/supabase_client.dart';

/// Talks to the `create-payment-intent` Edge Function, which validates
/// cart lines against DB prices/stock, creates a pending order, and
/// returns a Stripe PaymentIntent for the *server-calculated* total.
class PaymentRepository {
  final _client = SupabaseService.client;

  /// Creates a pending checkout. Do not send a client-computed [amount] —
  /// the server ignores it and recalculates from the database.
  Future<Map<String, dynamic>> createPaymentIntent({
    required List<Map<String, dynamic>> items,
    required String fulfillment, // 'delivery' | 'pickup'
    Map<String, dynamic>? shippingAddress,
    String currency = 'sgd',
    String? promoCode,
  }) async {
    final res = await _client.functions.invoke(
      'create-payment-intent',
      body: {
        'currency': currency,
        'fulfillment': fulfillment,
        'items': items,
        'shipping_address': ?shippingAddress,
        if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode,
      },
    );
    if (res.status >= 400) {
      final data = res.data;
      final message = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'Payment setup failed (${res.status})';
      throw Exception(message);
    }
    return Map<String, dynamic>.from(res.data as Map);
  }
}
