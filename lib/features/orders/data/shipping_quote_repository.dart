import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/utils/error_message.dart';
import '../domain/shipping_quote.dart';

class ShippingQuoteRepository {
  final SupabaseClient _client;
  ShippingQuoteRepository({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;
  Future<ShippingQuote> fetchQuote(Map<String, dynamic> request) async {
    final FunctionResponse res;
    try {
      res = await _client.functions
          .invoke('checkout-shipping-quote', body: request)
          .timeout(const Duration(seconds: 30));
    } on FunctionException catch (e) {
      // invoke() throws on every non-2xx response; the function's `error`
      // field is fixed copy written for the customer.
      throw ServerMessageException.fromFunction(
        e,
        fallback: 'Could not calculate delivery. Please try again.',
      );
    }
    return ShippingQuote.fromMap(Map<String, dynamic>.from(res.data as Map));
  }
}
