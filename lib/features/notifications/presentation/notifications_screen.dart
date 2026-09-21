import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/app_notification.dart';
import '../../../shared/widgets/empty_state.dart';
import 'notification_providers.dart';

/// Shared between the customer and admin apps — each only ever sees their
/// own rows (RLS), so the same screen works for both: a customer's
/// order-status updates, or an admin's out-for-delivery alerts.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(myNotificationsProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: const Text('NOTIFICATIONS'),
        actions: [
          notificationsAsync.maybeWhen(
            data: (items) => items.any((n) => !n.read)
                ? TextButton(
                    onPressed: () => ref.read(myNotificationsProvider.notifier).markAllRead(),
                    child: const Text('Mark all read'),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.red,
        onRefresh: () async => ref.invalidate(myNotificationsProvider),
        child: notificationsAsync.when(
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.notifications_none_outlined,
                    title: 'No notifications yet',
                    subtitle: 'Order updates will show up here.',
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) =>
                  _NotificationTile(notification: items[i]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.red)),
          error: (e, _) => ErrorState(onRetry: () => ref.invalidate(myNotificationsProvider)),
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final AppNotification notification;
  const _NotificationTile({required this.notification});

  IconData get _icon {
    switch (notification.type) {
      case 'admin_alert':
        return Icons.local_shipping_outlined;
      default:
        switch (notification.title) {
          case 'Order cancelled':
            return Icons.cancel_outlined;
          case 'Order delivered':
            return Icons.home_outlined;
          case 'Order shipped':
            return Icons.local_shipping_outlined;
          default:
            return Icons.receipt_long_outlined;
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = !notification.read;
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (unread) {
            ref.read(myNotificationsProvider.notifier).markRead(notification.id);
          }
          if (notification.orderId != null && context.mounted) {
            context.push('/orders/${notification.orderId}');
          }
        },
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(boxShadow: AppShadows.card),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: unread ? AppColors.redSoft : AppColors.offWhite,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  _icon,
                  size: 18,
                  color: unread ? AppColors.red : AppColors.grey,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: TextStyle(
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notification.body,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat.yMMMd().add_jm().format(
                        notification.createdAt,
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.greySoft,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(
                    color: AppColors.red,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
