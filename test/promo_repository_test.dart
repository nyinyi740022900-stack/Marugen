import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:marugen_app/features/promo/data/promo_repository.dart';

void main() {
  late List<http.Request> requests;

  Future<T> withRepository<T>(
    Object responseBody,
    Future<T> Function(PromoRepository repo) body,
  ) async {
    requests = [];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(responseBody),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    try {
      return await body(PromoRepository(client: client));
    } finally {
      await client.dispose();
    }
  }

  test(
    'checks one exact code through the private RPC, never the table',
    () async {
      final promo = await withRepository([
        {
          'id': 'p1',
          'code': 'SAVE10',
          'discount_type': 'percent',
          'discount_value': 10,
          'active': true,
          'expires_at': null,
          'max_redemptions': null,
          'times_redeemed': 0,
          'already_redeemed': true,
        },
      ], (repo) => repo.lookupCode('  save10 '));

      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/rest/v1/rpc/check_promo_code');
      expect(requests.single.url.query, isNot(contains('ilike')));
      expect(jsonDecode(requests.single.body), {'p_code': 'save10'});
      expect(promo!.code, 'SAVE10');
      expect(promo.alreadyRedeemed, isTrue);
    },
  );

  test('a wildcard is sent as a literal code and finds nothing', () async {
    final promo = await withRepository(
      const <Object>[],
      (repo) => repo.lookupCode('%'),
    );
    expect(promo, isNull);
    expect(jsonDecode(requests.single.body), {'p_code': '%'});
  });

  test('blank input never calls the server', () async {
    final promo = await withRepository(
      const <Object>[],
      (repo) => repo.lookupCode('   '),
    );
    expect(promo, isNull);
    expect(requests, isEmpty);
  });
}
