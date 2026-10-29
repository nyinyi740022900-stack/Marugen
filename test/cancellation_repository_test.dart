import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';

void main() {
  Future<void> invoke(Map<String, dynamic> response) async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    try {
      await OrderRepository(client: client)
          .manageCancellation('order', 'approve');
    } finally {
      await client.dispose();
    }
  }

  test('approval with a failed refund is surfaced separately from confirmed money return', () async {
    await expectLater(
      invoke({
        'request': {'order_id': 'order', 'status': 'approved'},
        'refund_error': 'Provider unavailable',
      }),
      throwsA(isA<CancellationRefundNeedsAttention>()),
    );
  });
  test(
    'missing or wrong-order server acknowledgement never confirms cancellation',
    () async {
      for (final payload in [
        <String, dynamic>{},
        {
          'request': {'order_id': 'different', 'status': 'approved'},
        },
        {
          'request': {'order_id': 'order', 'status': 'rejected'},
        },
      ]) {
        await expectLater(invoke(payload), throwsStateError);
      }
    },
  );
}
