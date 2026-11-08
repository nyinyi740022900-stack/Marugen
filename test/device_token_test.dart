import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marugen_app/core/notifications/push_notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<http.Request> requests;

  Future<void> withClient(
    bool rpcMissing,
    Future<void> Function(SupabaseClient client) body,
  ) async {
    requests = [];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final missing = rpcMissing && request.url.path.contains('/rpc/');
        return http.Response(
          missing
              ? jsonEncode({
                  'code': 'PGRST202',
                  'message': 'Could not find the function',
                })
              : '',
          missing ? 404 : 204,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    try {
      await body(client);
    } finally {
      await client.dispose();
    }
  }

  String describe(http.Request r) =>
      '${r.method} ${r.url.path}'
      '${r.url.query.isEmpty ? '' : '?${r.url.query}'} ${r.body}';

  test('a device registers through the RPC that takes the token away from '
      'its previous account', () async {
    await withClient(false, (client) async {
      await PushNotificationService.saveDeviceToken(
        client,
        userId: 'user-b',
        token: 'phone-token',
        platform: 'android',
      );
      await PushNotificationService.removeDeviceToken(
        client,
        userId: 'user-b',
        token: 'phone-token',
      );
    });
    expect(requests.map(describe), [
      'POST /rest/v1/rpc/register_device_token '
          '{"p_token":"phone-token","p_platform":"android"}',
      'POST /rest/v1/rpc/unregister_device_token {"p_token":"phone-token"}',
    ]);
  });

  test('before migration 0073 the token stays on the profile', () async {
    await withClient(true, (client) async {
      await PushNotificationService.saveDeviceToken(
        client,
        userId: 'user-b',
        token: 'phone-token',
      );
      await PushNotificationService.removeDeviceToken(
        client,
        userId: 'user-b',
        token: 'phone-token',
      );
    });
    expect(requests.map(describe), [
      'POST /rest/v1/rpc/register_device_token '
          '{"p_token":"phone-token","p_platform":null}',
      'PATCH /rest/v1/profiles?id=eq.user-b {"fcm_token":"phone-token"}',
      'POST /rest/v1/rpc/unregister_device_token {"p_token":"phone-token"}',
      'PATCH /rest/v1/profiles?id=eq.user-b {"fcm_token":null}',
    ]);
  });
}
