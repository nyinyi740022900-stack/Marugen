import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Wires uncaught Flutter/Dart errors to Firebase Crashlytics.
///
/// Safe to call even without a real Firebase project configured — mirrors
/// how `PushNotificationService` degrades: errors are caught and logged
/// locally instead of crashing app startup.
class CrashReporting {
  CrashReporting._();

  static bool _initialized = false;

  /// True once Crashlytics is actually wired up on this device.
  static bool get isAvailable => _initialized;

  /// Initializes Firebase (if not already done by another service) and
  /// routes Flutter framework errors + uncaught async errors to
  /// Crashlytics. Call once, early in `main()`, before `runApp`.
  static Future<void> initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp().timeout(const Duration(seconds: 8));
      }

      // Crash reports from local debug/profile runs are noise, not signal —
      // only collect from real release installs. Timeout guards against
      // this native channel call hanging on some devices/emulators
      // (observed on a fresh Android emulator profile run) — without it,
      // this await never returns and `main()` never reaches `runApp`,
      // leaving the app stuck on the native launch splash forever.
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(kReleaseMode)
          .timeout(const Duration(seconds: 5));

      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      _initialized = true;
    } catch (e, st) {
      // Expected until google-services.json / GoogleService-Info.plist are
      // added — app keeps running with crash reporting simply disabled.
      developer.log(
        'Crashlytics not available (missing Firebase config?): $e',
        name: 'CrashReporting',
        error: e,
        stackTrace: st,
      );
      _initialized = false;
    }
  }

  /// Receives non-fatal reports instead of Crashlytics while set (tests).
  @visibleForTesting
  static void Function(Object error, String? reason)? debugReporter;

  /// Records a non-fatal error, e.g. from a caught exception a caller still
  /// wants visibility into. No-op if Crashlytics isn't initialized.
  static void recordError(Object error, StackTrace stack, {String? reason}) {
    final reporter = debugReporter;
    if (reporter != null) {
      reporter(error, reason);
      return;
    }
    if (!_initialized) return;
    FirebaseCrashlytics.instance.recordError(error, stack, reason: reason);
  }
}
