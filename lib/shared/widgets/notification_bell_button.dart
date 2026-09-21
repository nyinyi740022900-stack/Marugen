import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../features/notifications/presentation/notification_providers.dart';

/// Bell icon + unread-count badge for an AppBar `actions` list — used by
/// both the customer (ShopScreen) and admin (AdminDashboardScreen) app
/// bars rather than a 5th bottom-nav destination, since neither side has
/// enough notification volume to earn permanent nav real estate (see the
/// admin nav's own "merge into tabs, don't sprawl" pattern for
/// Delivery/Payments). Re-fetches the unread count each time it rebuilds
/// (e.g. returning from NotificationsScreen re-triggers a provider watch
/// via invalidate there), not live/realtime.
class NotificationBellButton extends ConsumerWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_none_outlined),
          onPressed: () => context.push('/notifications'),
        ),
        if (unread > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: AppColors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
