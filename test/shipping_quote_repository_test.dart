import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:marugen_app/features/orders/data/shipping_quote_repository.dart';

void main() {
  test('a stalled delivery request times out so checkout can retry', () async {
    final response = Completer<http.Response>();
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) => response.future),
    );
    try {
      await expectLater(
        ShippingQuoteRepository(client: client).fetchQuote({}),
        throwsA(isA<TimeoutException>()),
      );
    } finally {
      response.complete(http.Response('{}', 200));
      await client.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 45)));
}
