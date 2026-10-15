import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/shared/models/order.dart';

void main() {
  test('paid orders offer refund instead of unpaid cancellation', () {
    for (final status in [OrderStatus.paid, OrderStatus.packing]) {
      expect(validNextStatuses(status), isNot(contains(OrderStatus.cancelled)));
      expect(validNextStatuses(status), contains(OrderStatus.refunded));
    }
  });
  test('customer cancellation invokes verified server endpoint rather than direct status write', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://audit.invalid',
      'fixture',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          '{"cancelled":true}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await OrderRepository(client: client).cancelMyOrder('order-12345');
    expect(requests.single.url.path, '/functions/v1/cancel-order');
    expect(jsonDecode(requests.single.body), {'order_id': 'order-12345'});
  });
}
