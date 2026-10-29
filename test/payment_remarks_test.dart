import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:marugen_app/features/orders/data/payment_repository.dart';

void main() {
  for (final note in [
    '  မရောက်ခင် ဖုန်းဆက်ပေးပါ။\nRing the bell.  ',
    '  \n ',
  ]) {
    test('checkout request sends normalized remarks without changing payment items', () async {
      Map<String, dynamic>? sent;
      final client = SupabaseClient(
        'https://example.invalid',
        'test-anon-key',
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            '{"orderId":"order-12345"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final repository = PaymentRepository(client: client);
      await repository.createPaymentIntent(
        items: [
          {'product_id': 'food', 'quantity': 2},
        ],
        shippingAddress: {'line1': '1 Street'},
        idempotencyKey: 'retry-key',
        shippingQuoteId: 'server-quote-id',
        customerRemarks: note,
        customerRemarksRevision: 7,
      );
      expect(
        sent!['customer_remarks'],
        note.trim().isEmpty ? null : 'မရောက်ခင် ဖုန်းဆက်ပေးပါ။\nRing the bell.',
      );
      expect(sent!['items'], [
        {'product_id': 'food', 'quantity': 2},
      ]);
      expect(sent!['idempotency_key'], 'retry-key');
      expect(sent!['shipping_quote_id'], 'server-quote-id');
      expect(sent!.containsKey('shipping_amount'), isFalse);
      expect(sent!.containsKey('amount'), isFalse);
      expect(sent!['customer_remarks_revision'], 7);
    });
  }
  test('invalid requests never reach payment creation', () async {
    var requests = 0;
    final client = SupabaseClient(
      'https://example.invalid',
      'test-anon-key',
      httpClient: MockClient((request) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.dispose);
    await expectLater(
      PaymentRepository(client: client).createPaymentIntent(
        items: [
          {'product_id': 'food', 'quantity': 1},
        ],
        customerRemarks: 'x' * 501,
      ),
      throwsFormatException,
    );
    expect(requests, 0);
  });
}
