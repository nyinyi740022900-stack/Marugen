import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/crash/crash_reporting.dart';
import 'image_upload.dart';

/// The copy an Edge Function sent with a failed call: the `error` (or
/// `message`) field of its JSON body. Those are fixed, hand-written
/// sentences on the server. Null when the body has none.
String? functionErrorMessage(FunctionException error) {
  final details = error.details;
  if (details is! Map) return null;
  for (final field in const ['error', 'message']) {
    final value = details[field];
    if (value is String && value.trim().isNotEmpty && value.length < 200) {
      return value.trim();
    }
  }
  return null;
}

/// A failed Edge Function call, reduced to copy that is safe to show: the
/// server's own sentence, or the repository's hand-written one when the
/// server sent none. `functions.invoke` throws on every non-2xx response,
/// so repositories convert that [FunctionException] into this.
class ServerMessageException implements Exception {
  final String message;

  /// HTTP status of the failed call; 5xx is still reported as a bug.
  final int status;

  const ServerMessageException(this.message, {required this.status});

  factory ServerMessageException.fromFunction(
    FunctionException error, {
    required String fallback,
  }) => ServerMessageException(
    functionErrorMessage(error) ?? fallback,
    status: error.status,
  );

  @override
  String toString() => message;
}

/// Maps an exception to short, user-safe copy so screens never show raw
/// Postgres/HTTP/stack text (`'Error: $e'`). The original error is logged
/// via `dart:developer` under [context] so it stays debuggable.
///
/// Messages our own repositories throw (`Exception('...')`, usually the
/// Edge Function's `error` field) are already written for people and are
/// passed through unchanged.
String friendlyErrorMessage(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
  String context = 'app',
  StackTrace? stackTrace,
}) {
  developer.log('Error shown to user', name: context, error: error);
  final (message, unexpected) = _describe(error, fallback);
  // Dropped connections and messages written for people are expected. A
  // database, storage or server failure, or anything that fell back to
  // generic copy, is a bug that release builds would otherwise hide.
  if (unexpected) {
    CrashReporting.recordError(
      error,
      stackTrace ?? StackTrace.current,
      reason: context,
    );
  }
  return message;
}

/// The copy to show and whether the error is unexpected.
(String, bool) _describe(Object error, String fallback) {
  if (error is SocketException ||
      error is TimeoutException ||
      error is HttpException) {
    return ('Network problem — check your connection and try again.', false);
  }
  if (error is ServerMessageException) {
    return (error.message, error.status >= 500);
  }
  if (error is FunctionException) {
    final message = functionErrorMessage(error);
    if (message != null) return (message, error.status >= 500);
    return (fallback, true);
  }
  if (error is PostgrestException) {
    switch (error.code) {
      case '42501':
        return ("You don't have permission to do that.", true);
      case '23505':
        return ('That already exists. Use a different value.', false);
      case '23503':
        return ("This item is still in use, so it can't be changed.", false);
      case 'PGRST116':
        return ('This item no longer exists. Refresh and try again.', false);
    }
    return (fallback, true);
  }
  if (error is StorageException) {
    // The bucket refused the file itself (wrong type or too large): the
    // person can fix that, so say how. Not a bug to report.
    if (isImageUploadRejection(error)) {
      return (imageUploadRejectedMessage, false);
    }
    return ('Could not upload or load the file. Please try again.', true);
  }
  if (error is AuthException) {
    // Only a rejected token means the session expired; other auth errors
    // (a weak new password, a rate limit) carry their own explanation.
    final code = error.code ?? '';
    if (error.statusCode == '401' ||
        code.contains('session') ||
        code.contains('refresh_token') ||
        code == 'bad_jwt') {
      return ('Your session expired. Please log in again.', false);
    }
    final message = error.message.trim();
    return (
      message.isNotEmpty && message.length < 200 ? message : fallback,
      false,
    );
  }

  final raw = error.toString();
  final lower = raw.toLowerCase();
  if (lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection refused') ||
      lower.contains('connection closed')) {
    return ('Network problem — check your connection and try again.', false);
  }
  if (error is Exception && raw.startsWith('Exception: ')) {
    final message = raw.substring('Exception: '.length).trim();
    if (message.isNotEmpty && message.length < 200) return (message, false);
  }
  return (fallback, true);
}
