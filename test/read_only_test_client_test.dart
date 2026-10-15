import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../integration_test/support/read_only_http_client.dart';

void main() {
  test(
    'native smoke tests forward reads and never transmit backend writes',
    () async {
      final transmitted = <String>[];
      final client = ReadOnlyHttpClient(
        MockClient((request) async {
          transmitted.add(request.method);
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      await client.get(Uri.parse('https://audit.invalid/rest/v1/products'));
      for (final method in ['POST', 'PATCH', 'PUT', 'DELETE']) {
        await expectLater(
          client.send(
            http.Request(
              method,
              Uri.parse('https://audit.invalid/rest/v1/app_visits'),
            ),
          ),
          throwsStateError,
        );
      }
      expect(transmitted, ['GET']);
      expect(client.blockedWrites, 4);
    },
  );
}
