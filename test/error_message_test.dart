import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/shared/utils/error_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('raw database errors never reach the UI', () {
    final message = friendlyErrorMessage(
      const PostgrestException(
        message: 'duplicate key value violates unique constraint "products_slug_key"',
        code: '23505',
      ),
    );
    expect(message, isNot(contains('constraint')));
    expect(message, 'That already exists. Use a different value.');
  });

  test('unknown database errors use the screen fallback', () {
    expect(
      friendlyErrorMessage(
        const PostgrestException(
          message: 'relation "x" does not exist',
          code: '42P01',
        ),
        fallback: 'Could not save the product.',
      ),
      'Could not save the product.',
    );
  });

  test('network failures get connection copy', () {
    const expected = 'Network problem — check your connection and try again.';
    expect(
      friendlyErrorMessage(const SocketException('Failed host lookup')),
      expected,
    );
    expect(friendlyErrorMessage(TimeoutException('slow')), expected);
  });

  test('messages our repositories write for people pass through', () {
    expect(
      friendlyErrorMessage(Exception('Order is already refunded')),
      'Order is already refunded',
    );
  });

  test('Edge Function error field is shown, otherwise fallback', () {
    expect(
      friendlyErrorMessage(
        const FunctionException(
          status: 400,
          details: {'error': 'Tracking number is required'},
        ),
      ),
      'Tracking number is required',
    );
    expect(
      friendlyErrorMessage(
        const FunctionException(status: 500),
        fallback: 'Tracking failed.',
      ),
      'Tracking failed.',
    );
  });

  test('unexpected errors such as StateError use the fallback', () {
    expect(
      friendlyErrorMessage(StateError('bad state: null'), fallback: 'Oops.'),
      'Oops.',
    );
  });
}
