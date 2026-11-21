import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marugen_app/core/crash/crash_reporting.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/data/payment_repository.dart';
import 'package:marugen_app/shared/utils/error_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// An Edge Function that answers every call with [status] and [body].
SupabaseClient functionAnswering(int status, Object? body) {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(
      (_) async => http.Response(
        body is String ? body : jsonEncode(body),
        status,
        headers: {
          'content-type': body is String ? 'text/plain' : 'application/json',
        },
      ),
    ),
  );
  addTearDown(client.dispose);
  return client;
}

/// What the screen would show for the error [call] ends with.
Future<String> shown(Future<void> Function() call) async {
  try {
    await call();
  } catch (error) {
    expect(error, isA<ServerMessageException>());
    return friendlyErrorMessage(error, fallback: 'GENERIC');
  }
  fail('expected the call to fail');
}

void main() {
  const items = [
    {'product_id': 'p', 'quantity': 1},
  ];

  test(
    'checkout shows the reason the server gave, not a generic line',
    () async {
      expect(
        await shown(
          () => PaymentRepository(
            client: functionAnswering(409, {
              'error': 'This item just sold out.',
            }),
          ).createPaymentIntent(items: items, idempotencyKey: 'k'),
        ),
        'This item just sold out.',
      );
    },
  );

  test('a failure without a readable reason gets the hand-written line, '
      'never the raw body', () async {
    expect(
      await shown(
        () => PaymentRepository(
          client: functionAnswering(500, '<html>Bad gateway</html>'),
        ).createPaymentIntent(items: items, idempotencyKey: 'k'),
      ),
      'Payment could not be set up. Please try again.',
    );
    expect(
      await shown(
        () => OrderRepository(
          client: functionAnswering(500, {'error': 'x' * 400}),
        ).refundOrder('order'),
      ),
      'Could not process the refund. Check Stripe and try again.',
    );
  });

  test(
    'refund, cancellation decision and cancel surface the server copy',
    () async {
      expect(
        await shown(
          () => OrderRepository(
            client: functionAnswering(409, {
              'error': 'This order has already been refunded.',
            }),
          ).refundOrder('order'),
        ),
        'This order has already been refunded.',
      );
      expect(
        await shown(
          () => OrderRepository(
            client: functionAnswering(409, {
              'message': 'This order has already shipped.',
            }),
          ).manageCancellation('order', 'request'),
        ),
        'This order has already shipped.',
      );
      expect(
        await shown(
          () => OrderRepository(
            client: functionAnswering(400, {'error': 'Order is already paid.'}),
          ).cancelMyOrder('order'),
        ),
        'Order is already paid.',
      );
    },
  );

  test('with no server copy, cancellation keeps its own wording', () async {
    expect(
      await shown(
        () =>
            OrderRepository(client: functionAnswering(500, {}))
                .manageCancellation('order', 'approve'),
      ),
      'Cancellation could not be confirmed. Refresh the order or contact support.',
    );
    expect(
      await shown(
        () =>
            OrderRepository(client: functionAnswering(502, {}))
                .cancelMyOrder('order'),
      ),
      'Cancellation was not confirmed. Refresh the order or contact the shop.',
    );
  });

  test('a server fault is still reported; a refusal is not', () {
    final reported = <String>[];
    CrashReporting.debugReporter = (error, reason) => reported.add('$reason');
    addTearDown(() => CrashReporting.debugReporter = null);
    friendlyErrorMessage(
      const ServerMessageException('Sold out', status: 409),
      context: 'refusal',
    );
    friendlyErrorMessage(
      const ServerMessageException('Try again', status: 503),
      context: 'fault',
    );
    expect(reported, ['fault']);
  });

  test('an uncaught function error also shows its message field', () {
    expect(
      friendlyErrorMessage(
        const FunctionException(
          status: 400,
          details: {'message': 'Postal code is required.'},
        ),
        fallback: 'GENERIC',
      ),
      'Postal code is required.',
    );
    expect(
      friendlyErrorMessage(
        const FunctionException(status: 400, details: 'plain text'),
        fallback: 'GENERIC',
      ),
      'GENERIC',
    );
  });
}
