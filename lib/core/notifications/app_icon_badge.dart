import 'dart:developer' as developer;

import 'package:app_badge_plus/app_badge_plus.dart';

/// Home screen app icon badge (the red "1" over the icon, like Facebook/
/// Mail) — separate from the in-app bell badge in NotificationBellButton.
/// Kept in sync with the unread notification count so the badge is visible
/// without opening the app.
///
/// Best-effort everywhere: badge support is OS/launcher-dependent (not
/// every Android launcher implements it) and the plugin can throw on
/// devices/emulators without an implementation — never worth crashing or
/// even logging loudly over.
class AppIconBadge {
  AppIconBadge._();

  static Future<void> set(int count) async {
    try {
      if (!await AppBadgePlus.isSupported()) return;
      await AppBadgePlus.updateBadge(count);
    } catch (e) {
      developer.log('Could not update app icon badge: $e', name: 'AppIconBadge');
    }
  }

  static Future<void> clear() => set(0);
}
