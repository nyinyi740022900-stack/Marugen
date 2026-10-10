import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/utils/order_remarks.dart';

/// Talks to the `create-payment-intent` Edge Function, which validates
/// cart lines against DB prices/stock, creates a pending order, and
/// returns a Stripe PaymentIntent for the *server-calculated* total.
class PaymentRepository {
  final SupabaseClient _client;
  PaymentRepository({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  /// Creates a pending checkout. Do not send a client-computed [amount] —
  /// the server ignores it and recalculates from the database.
  ///
  /// [idempotencyKey], when provided, should stay the same across every
  /// retry of one checkout attempt (see checkout_screen.dart) — a dropped
  /// response after the server actually succeeded would otherwise look
  /// like a failure to the client and cause a retry that reserves stock
  /// and creates a Stripe PaymentIntent a second time. The server returns
  /// the original order/PaymentIntent instead when it sees a repeat key.
  Future<Map<String, dynamic>> createPaymentIntent({
    required List<Map<String, dynamic>> items,
    Map<String, dynamic>? shippingAddress,
    String currency = 'sgd',
    String? promoCode,
    String? idempotencyKey,
    String? customerRemarks,
    int customerRemarksRevision = 0,
  }) async {
    final remarks = normaliseOrderRemarks(customerRemarks);
    if (customerRemarksRevision < 0 || customerRemarksRevision > 2147483647) {
      throw const FormatException('Invalid order requests revision.');
    }
    final res = await _client.functions.invoke(
      'create-payment-intent',
      body: {
        'currency': currency,
        'items': items,
        'shipping_address': ?shippingAddress,
        if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode,
        'idempotency_key': ?idempotencyKey,
        'customer_remarks': remarks,
        'customer_remarks_revision': customerRemarksRevision,
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
