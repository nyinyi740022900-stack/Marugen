import '../../../core/supabase/supabase_client.dart';

/// Talks to the `create-payment-intent` Supabase Edge Function, which holds
/// the Stripe secret key server-side and creates a PaymentIntent for the
/// cart total. See `supabase/functions/create-payment-intent/index.ts`.
class PaymentRepository {
  final _client = SupabaseService.client;

  Future<Map<String, dynamic>> createPaymentIntent({
    required double amount,
    required String currency,
    required List<Map<String, dynamic>> items,
  }) async {
    final res = await _client.functions.invoke(
      'create-payment-intent',
      body: {
        'amount': (amount * 100).round(), // Stripe expects the smallest unit
        'currency': currency,
        'items': items,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }
}
