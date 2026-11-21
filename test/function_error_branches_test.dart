import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marugen_app/features/admin/delivery/delivery_repository.dart';
import 'package:marugen_app/features/admin/delivery/easyparcel_repository.dart';
import 'package:marugen_app/features/auth/data/auth_repository.dart';
import 'package:marugen_app/features/orders/data/shipping_quote_repository.dart';
import 'package:marugen_app/shared/utils/error_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `functions.invoke` throws a FunctionException on every non-2xx response.
/// These repositories used to read the status of a response they never got;
/// each must now surface the function's own sentence, or its hand-written
/// fallback, never raw exception text.
void main() {
  SupabaseClient failing(int status, Object? body) {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (request) async => http.Response(
          body is String ? body : jsonEncode(body),
          status,
          headers: {
            'content-type': body is String ? 'text/plain' : 'application/json',
          },
          request: request,
        ),
      ),
    );
    addTearDown(client.dispose);
    return client;
  }

  const parcel = ParcelDetails(
    weightKg: 1,
    lengthCm: 10,
    widthCm: 10,
    heightCm: 10,
    collectionDate: '2026-11-20',
  );

  /// Every call that reports a failed function as a ServerMessageException.
  final calls = <String, Future<Object?> Function(SupabaseClient)>{
    'track-register': (c) => DeliveryRepository(
      client: c,
    ).registerTracking(orderId: 'o', trackingNumber: 'T1'),
    'track-status': (c) =>
        DeliveryRepository(client: c).refreshTrackingStatus('o'),
    'easyparcel-oauth-start': (c) =>
        EasyParcelRepository(client: c).startOAuth(),
    'easyparcel-status': (c) =>
        EasyParcelRepository(client: c).connectionStatus(),
    'easyparcel-get-rates': (c) =>
        EasyParcelRepository(client: c).getRates('o', parcel: parcel),
    'easyparcel-book-shipment': (c) => EasyParcelRepository(
      client: c,
    ).bookShipment(orderId: 'o', serviceId: 's', parcel: parcel),
    'easyparcel-reconcile-shipment': (c) =>
        EasyParcelRepository(client: c).reconcileShipment('o', 'T1'),
    'easyparcel-pickup-diagnostics': (c) =>
        EasyParcelRepository(client: c).pickupDiagnostics('o'),
    'easyparcel-refresh-status': (c) =>
        EasyParcelRepository(client: c).refreshStatus('o'),
    'checkout-shipping-quote': (c) =>
        ShippingQuoteRepository(client: c).fetchQuote({}),
    'delete-account': (c) => AuthRepository(client: c).deleteAccount(),
  };

  for (final MapEntry(key: name, value: call) in calls.entries) {
    test('$name shows the sentence the function sent', () async {
      Object? thrown;
      try {
        await call(failing(409, {'error': 'Written by the server for $name.'}));
      } catch (error) {
        thrown = error;
      }
      expect(thrown, isA<ServerMessageException>());
      expect(
        friendlyErrorMessage(thrown!, fallback: 'screen fallback'),
        'Written by the server for $name.',
      );
    });

    test('$name falls back to hand-written copy, never exception text', () async {
      Object? thrown;
      try {
        await call(failing(500, 'upstream connect error'));
      } catch (error) {
        thrown = error;
      }
      expect(thrown, isA<ServerMessageException>());
      final message = (thrown! as ServerMessageException).message;
      expect((thrown as ServerMessageException).status, 500);
      expect(message, isNot(contains('FunctionException')));
      expect(message, isNot(contains('upstream')));
      expect(message, isNot(contains('Exception')));
      expect(message.trim(), isNotEmpty);
      expect(message, endsWith('.'));
    });
  }

  group('order-parcels keeps the StateError the parcel panel shows', () {
    test('with the function sentence', () async {
      await expectLater(
        EasyParcelRepository(
          client: failing(409, {'error': 'Parcel plan changed. Refresh.'}),
        ).parcelAction('quote', 'o'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Parcel plan changed. Refresh.',
          ),
        ),
      );
    });

    test('with the fallback when the function sent none', () async {
      await expectLater(
        EasyParcelRepository(
          client: failing(502, 'bad gateway'),
        ).parcelAction('quote', 'o'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Could not update parcels. Refresh and try again.',
          ),
        ),
      );
    });
  });
}
