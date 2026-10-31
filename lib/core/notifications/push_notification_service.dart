import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  static Future<void> initialize() => _initFuture ??= _initialize();

  static Future<void>? _initFuture;
  static bool _permissionRequested = false;

  static Future<void> _initialize() async {
    try {
      // Hard timeouts on every native call below: without a real Firebase
      // project configured, these have been observed to hang waiting on a
      // native callback (e.g. APNs device-token registration) that never
      // arrives, rather than throwing — a timeout turns that into the same
      // "not available yet" outcome as a normal failure.
      //
      // Firebase may already be initialized by `CrashReporting.initialize()`
      // earlier in `main()` — re-initializing the same default app throws a
      // duplicate-app exception, so only do it if nothing has claimed it yet.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp().timeout(const Duration(seconds: 8));
      }
      _initialized = true;

      final messaging = FirebaseMessaging.instance;

      // Foreground display: FCM does not show a system banner while the
      // app is open, so surface it ourselves.
      FirebaseMessaging.onMessage.listen(_showForegroundMessage);
      // A tapped banner opens its order, whether the app was in the
      // background or (getInitialMessage) not running at all.
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => openPushData(message.data),
      );
      final launch = await messaging.getInitialMessage().timeout(
        const Duration(seconds: 8),
      );
      if (launch != null) openPushData(launch.data);

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

  /// Shows the OS notification-permission prompt once per app session.
  /// Deliberately not part of [initialize]: on first launch the iOS prompt
  /// would otherwise appear on top of the promo popup. Shells call this
  /// once their own launch dialogs are dismissed. Safe to call repeatedly.
  static Future<void> requestPermission() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    await initialize();
    if (!_initialized) return;
    try {
      final settings = await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true)
          .timeout(const Duration(seconds: 8));
      developer.log(
        'Push permission status: ${settings.authorizationStatus}',
        name: 'PushNotificationService',
      );
      await registerTokenForCurrentUser();
    } catch (e) {
      developer.log(
        'Could not request push permission: $e',
        name: 'PushNotificationService',
      );
    }
  }

  static void _showForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title ?? 'Marugen Fish Farm';
    final body = message.notification?.body ?? '';
    final context = messengerKey.currentState;
    if (context == null) return;
    context.showSnackBar(
      SnackBar(
        content: Text(body.isEmpty ? title : '$title — $body'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => openPushData(message.data),
        ),
      ),
    );
  }

  /// Where a tapped push lands: its order when it names one, otherwise the
  /// notifications inbox.
  static String locationForPush(Map<String, dynamic> data) {
    final orderId = data['order_id'];
    return orderId is String && _orderId.hasMatch(orderId)
        ? '/orders/$orderId'
        : '/notifications';
  }

  static final _orderId = RegExp(r'^[0-9a-fA-F-]{8,64}$');
  static void Function(String location)? _openHandler;
  static String? _pendingLocation;

  /// Set by the app once its router exists. A push tapped before that (a
  /// cold start from a notification) is handed over as soon as it is set.
  static set openLocation(void Function(String location)? handler) {
    _openHandler = handler;
    final pending = _pendingLocation;
    if (handler != null && pending != null) {
      _pendingLocation = null;
      handler(pending);
    }
  }

  @visibleForTesting
  static void openPushData(Map<String, dynamic> data) {
    final location = locationForPush(data);
    final handler = _openHandler;
    if (handler == null) {
      _pendingLocation = location;
    } else {
      handler(location);
    }
  }

  /// Fetches the device's current FCM token and registers it as one of the
  /// logged-in account's devices (see [saveDeviceToken]) so order updates
  /// reach it. No-op if Firebase isn't initialized or nobody is logged in.
  static Future<void> registerTokenForCurrentUser() async {
    if (!_initialized) return;
    try {
      final token = await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 8),
      );
      if (token != null) await _saveTokenIfLoggedIn(token);
    } catch (e) {
      developer.log(
        'Could not fetch FCM token: $e',
        name: 'PushNotificationService',
      );
    }
  }

  static Future<void> _saveTokenIfLoggedIn(String token) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    _deviceToken = token;
    try {
      await saveDeviceToken(
        SupabaseService.client,
        userId: user.id,
        token: token,
        platform: switch (defaultTargetPlatform) {
          TargetPlatform.iOS => 'ios',
          TargetPlatform.android => 'android',
          _ => null,
        },
      );
    } catch (e) {
      developer.log(
        'Could not save FCM token: $e',
        name: 'PushNotificationService',
      );
    }
  }

  /// The token this device last registered, so sign-out can remove it.
  static String? _deviceToken;

  /// Registers [token] as this account's device (migration 0073), which
  /// also takes it away from any account that used the phone before. Until
  /// that migration is applied the RPC is missing (PGRST202) and the token
  /// goes on the profile as before.
  @visibleForTesting
  static Future<void> saveDeviceToken(
    SupabaseClient client, {
    required String userId,
    required String token,
    String? platform,
  }) async {
    try {
      await client.rpc(
        'register_device_token',
        params: {'p_token': token, 'p_platform': platform},
      );
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202') rethrow;
      await client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', userId);
    }
  }

  /// Removes [token] from this account's devices; see [saveDeviceToken].
  @visibleForTesting
  static Future<void> removeDeviceToken(
    SupabaseClient client, {
    required String userId,
    required String? token,
  }) async {
    if (token != null) {
      try {
        await client.rpc('unregister_device_token', params: {'p_token': token});
        return;
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202') rethrow;
      }
    }
    await client.from('profiles').update({'fcm_token': null}).eq('id', userId);
  }

  /// Removes this device's FCM token from the signed-in account so a
  /// shared/handed-down device stops receiving pushes meant for the account
  /// that just signed out. Must be called with the user still authenticated
  /// (the functions and RLS act on `auth.uid()`), so callers should invoke
  /// this *before* `auth.signOut()`.
  static Future<void> clearTokenForCurrentUser() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      var token = _deviceToken;
      if (token == null && _initialized) {
        token = await FirebaseMessaging.instance.getToken().timeout(
          const Duration(seconds: 5),
        );
      }
      await removeDeviceToken(
        SupabaseService.client,
        userId: user.id,
        token: token,
      );
      _deviceToken = null;
    } catch (e) {
      developer.log(
        'Could not clear FCM token: $e',
        name: 'PushNotificationService',
      );
    }
  }
}
