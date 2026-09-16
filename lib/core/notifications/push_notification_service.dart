import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../supabase/supabase_client.dart';

/// Push notification wiring (Firebase Cloud Messaging).
///
/// IMPORTANT — this needs real Firebase config to actually deliver
/// notifications. Until then, [initialize] fails fast inside its own
/// try/catch and the app keeps running normally (mirrors how `main.dart`
/// treats a missing `.env`). See the two-file checklist below.
///
/// To go live:
///   1. Create a Firebase project at https://console.firebase.google.com
///   2. Add an iOS app with bundle id `com.marugen.marugenApp` (see
///      `ios/Runner.xcodeproj`), download `GoogleService-Info.plist`,
///      and place it at `ios/Runner/GoogleService-Info.plist` (added to
///      the Runner target in Xcode).
///   3. Add an Android app with package name `com.marugen.marugen_app`
///      (see `android/app/build.gradle.kts`), download
///      `google-services.json`, and place it at
///      `android/app/google-services.json`.
///   4. Apply the Google Services Gradle plugin: add
///      `id("com.google.gms.google-services")` to `android/app/build.gradle.kts`
///      and the classpath to `android/settings.gradle.kts` /
///      `android/build.gradle.kts` (see Firebase's Flutter setup docs —
///      omitted here since the plugin fails the build without the json
///      file present).
///   5. Re-run `flutter pub get` and rebuild. [initialize] will then
///      succeed, request notification permission, and register a real
///      FCM token.
class PushNotificationService {
  PushNotificationService._();

  /// Attached to `MaterialApp.router` in `main.dart` so foreground
  /// messages can show a SnackBar from anywhere.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static bool _initialized = false;

  /// True once Firebase actually initialized successfully on this device.
  static bool get isAvailable => _initialized;

  /// Initializes Firebase + FCM. Safe to call even when no Firebase config
  /// files are present — catches and logs instead of throwing, so app
  /// startup never crashes because push notifications aren't set up yet.
  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      _initialized = true;

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      developer.log(
        'Push permission status: ${settings.authorizationStatus}',
        name: 'PushNotificationService',
      );

      // Foreground display: FCM does not show a system banner while the
      // app is open, so surface it ourselves.
      FirebaseMessaging.onMessage.listen(_showForegroundMessage);

      // Keep the stored token fresh (e.g. after app reinstall/token
      // rotation) and re-register whenever the token refreshes.
      messaging.onTokenRefresh.listen((token) {
        developer.log('FCM token refreshed', name: 'PushNotificationService');
        _saveTokenIfLoggedIn(token);
      });

      await registerTokenForCurrentUser();
    } catch (e, st) {
      // Expected until google-services.json / GoogleService-Info.plist are
      // added — see the class doc above for the exact setup steps.
      developer.log(
        'Firebase/FCM not available (missing config?): $e',
        name: 'PushNotificationService',
        error: e,
        stackTrace: st,
      );
      _initialized = false;
    }
  }

  static void _showForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title ?? 'Marugen Koi Farm';
    final body = message.notification?.body ?? '';
    final context = messengerKey.currentState;
    if (context == null) return;
    context.showSnackBar(
      SnackBar(
        content: Text(body.isEmpty ? title : '$title — $body'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Fetches the device's current FCM token and stores it on the logged-in
  /// user's `profiles` row (column `fcm_token`, see
  /// `supabase/migrations/0003_fcm_token.sql`) so a future server-side
  /// "notify this user" flow has something to target. No-op if Firebase
  /// isn't initialized or nobody is logged in.
  static Future<void> registerTokenForCurrentUser() async {
    if (!_initialized) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveTokenIfLoggedIn(token);
    } catch (e) {
      developer.log('Could not fetch FCM token: $e', name: 'PushNotificationService');
    }
  }

  static Future<void> _saveTokenIfLoggedIn(String token) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.client
          .from('profiles')
          .update({'fcm_token': token}).eq('id', user.id);
    } catch (e) {
      developer.log('Could not save FCM token: $e', name: 'PushNotificationService');
    }
  }
}
