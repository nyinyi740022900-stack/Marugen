import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'push_notification_service.dart';

export 'push_notification_service.dart' show PushPermission;

/// The phone's notification permission, as the Profile switch needs it:
/// read it, ask for it, and open the phone's Settings when only the phone
/// can change it. A thin seam over [PushNotificationService] so screens can
/// be tested without Firebase.
class PushPermissionController {
  const PushPermissionController();

  Future<PushPermission> current() => PushNotificationService.permission();

  /// Shows the OS prompt (where the OS still allows one) and returns the
  /// permission afterwards.
  Future<PushPermission> request() async {
    await PushNotificationService.requestPermission(force: true);
    return current();
  }

  /// Whether [openSettings] can do anything on this platform. Android needs
  /// an intent the app has no plugin for yet, so the hint there is text only.
  bool get canOpenSettings =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Opens this app's page in the iOS Settings app.
  Future<bool> openSettings() async {
    try {
      return await launchUrl(Uri.parse('app-settings:'));
    } catch (_) {
      return false;
    }
  }
}

final pushPermissionControllerProvider = Provider<PushPermissionController>(
  (ref) => const PushPermissionController(),
);
