import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../domain/shipping_quote.dart';

class ShippingQuoteRepository {
  final SupabaseClient _client;
  ShippingQuoteRepository({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;
  Future<ShippingQuote> fetchQuote(Map<String, dynamic> request) async {
    final res = await _client.functions
        .invoke('checkout-shipping-quote', body: request)
        .timeout(const Duration(seconds: 30));
    if (res.status >= 400) {
      final data = res.data;
      throw Exception(
        data is Map
            ? data['error']?.toString() ?? 'Could not calculate shipping.'
            : 'Could not calculate shipping.',
      );
    }
    return ShippingQuote.fromMap(Map<String, dynamic>.from(res.data as Map));
  }
}
