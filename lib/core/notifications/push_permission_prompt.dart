import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'push_notification_service.dart';

/// Asks a customer for notification permission at a moment it makes sense:
/// right after their first order is placed, or the first time they open
/// their notifications — never on first launch. The OS prompt is preceded
/// by one line saying what it is for, and the whole thing happens at most
/// once per device, whatever the answer.
///
/// People who already allowed notifications are never shown anything:
/// their token is registered at startup by
/// [PushNotificationService.initialize].
class PushPermissionPrompt {
  PushPermissionPrompt._();

  static const reason = 'Get a message when your order ships.';

  /// Device-wide: the OS permission belongs to the device, not the account.
  static const askedPrefsKey = 'push_permission_asked';

  /// Whether the OS would still show its prompt. Replaceable in tests.
  @visibleForTesting
  static Future<bool> Function() canAsk =
      PushNotificationService.canAskPermission;

  /// Shows the OS prompt. Replaceable in tests.
  @visibleForTesting
  static Future<void> Function() requestPermission =
      PushNotificationService.requestPermission;

  static bool _asking = false;

  static Future<void> maybeAsk(BuildContext context) async {
    if (_asking) return;
    _asking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(askedPrefsKey) ?? false) return;
      if (!await canAsk()) return;
      if (!context.mounted) return;
      // Recorded before the dialog is answered: dismissing it counts as an
      // answer, and nobody is asked a second time.
      await prefs.setBool(askedPrefsKey, true);
      if (!context.mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          // Scrolls rather than clips on a small phone at 200% text.
          scrollable: true,
          title: const Text('Order updates'),
          content: const Text(reason),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Turn on notifications'),
            ),
          ],
        ),
      );
      if (accepted == true) await requestPermission();
    } catch (e) {
      // Never let a permission nicety break the screen underneath it.
      developer.log(
        'Could not ask for push permission: $e',
        name: 'PushPermissionPrompt',
      );
    } finally {
      _asking = false;
    }
  }
}

/// Calls [PushPermissionPrompt.maybeAsk] once [child] is on screen.
class AskPushPermissionOnce extends StatefulWidget {
  final Widget child;
  const AskPushPermissionOnce({super.key, required this.child});

  @override
  State<AskPushPermissionOnce> createState() => _AskPushPermissionOnceState();
}

class _AskPushPermissionOnceState extends State<AskPushPermissionOnce> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(PushPermissionPrompt.maybeAsk(context));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
