import '../../auth/presentation/auth_providers.dart';
import '../../../shared/widgets/guest_account_state.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/app_notification.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/undo_snack_bar.dart';
import 'notification_providers.dart';

/// Shared between the customer and admin apps — each only ever sees their
/// own rows (RLS), so the same screen works for both: a customer's
/// order-status updates, or an admin's out-for-delivery alerts.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _selecting = false;
  bool _busy = false;
  final _selected = <String>{};

  void _cancelSelection() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  void _toggle(String id) {
    if (_busy) return;
    setState(() {
      _selecting = true;
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  Future<void> _delete() async {
    if (_busy || _selected.isEmpty) return;
    final owner = ref.read(currentUserIdProvider);
    final requested = Set<String>.of(_selected);
    setState(() => _busy = true);
    try {
      final batch = await ref
          .read(myNotificationsProvider.notifier)
          .dismissSelected(requested);
      if (!mounted ||
          ref.read(currentUserIdProvider) != owner ||
          batch == null) {
        return;
      }
      setState(() {
        _selected.removeAll(batch.ids);
        if (_selected.isEmpty) _selecting = false;
      });
      _showUndo(batch, partial: batch.ids.length < requested.length);
    } catch (_) {
      if (mounted && ref.read(currentUserIdProvider) == owner) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't delete notifications. Your selection is kept. Try again.",
            ),
          ),
        );
      }
    } finally {
      if (mounted && ref.read(currentUserIdProvider) == owner) {
        setState(() => _busy = false);
      }
    }
  }

  void _showUndo(NotificationDismissal batch, {bool partial = false}) {
    // The app messenger outlives this route. Its actions must use the durable
    // notifier rather than this screen's WidgetRef after the screen is popped.
    final notifier = ref.read(myNotificationsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    Future<void> undo() async {
      if (!notifier.isCurrentDismissal(batch)) return;
      try {
        final restored = await notifier.undoDismissal(batch);
        if (!messenger.mounted || !notifier.isCurrentDismissal(batch)) return;
        if (!restored) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Some notifications could not be restored. Refresh your inbox.',
              ),
            ),
          );
        }
      } catch (_) {
        if (!messenger.mounted || !notifier.isCurrentDismissal(batch)) return;
        showUndoSnackBar(
          messenger,
          message: "Couldn't restore notifications. Try again.",
          actionLabel: 'Retry',
          onAction: undo,
        );
      }
    }

    final count = batch.items.length;
    showUndoSnackBar(
      messenger,
      message: partial
          ? '$count deleted. Remaining notifications are still selected.'
          : '$count notification${count == 1 ? '' : 's'} deleted',
      onAction: undo,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserIdProvider, (previous, next) {
      if (previous == next) return;
      setState(() {
        _selecting = false;
        _selected.clear();
        _busy = false;
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    });
    if (!ref.watch(isLoggedInProvider)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: const GuestAccountState(
          icon: Icons.notifications_none_outlined,
          subtitle: 'View notifications and order updates.',
          returnTo: '/notifications',
        ),
      );
    }
    final notificationsAsync = ref.watch(myNotificationsProvider);
    final items = notificationsAsync.valueOrNull ?? <AppNotification>[];
    final selected = _selected.intersection(items.map((n) => n.id).toSet());
    final allSelected =
        items.isNotEmpty && items.every((n) => selected.contains(n.id));

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selecting) _cancelSelection();
      },
      child: Scaffold(
        backgroundColor: AppPalette.of(context).background,
        appBar: AppBar(
          leading: _selecting
              ? IconButton(
                  tooltip: 'Cancel selection',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(Icons.close),
                  onPressed: _cancelSelection,
                )
              : null,
          title: Text(
            _selecting ? '${selected.length} selected' : 'Notifications',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (_selecting)
              IconButton(
                tooltip: _busy ? 'Deleting notifications' : 'Delete selected',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
                onPressed: _busy || selected.isEmpty ? null : _delete,
              )
            else ...[
              if (items.any((n) => !n.read))
                IconButton(
                  tooltip: 'Mark all read',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(Icons.done_all),
                  onPressed: () =>
                      ref.read(myNotificationsProvider.notifier).markAllRead(),
                ),
              if (items.isNotEmpty)
                IconButton(
                  tooltip: 'Select notifications',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(Icons.checklist_outlined),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _selecting = true),
                ),
            ],
          ],
        ),
        body: Column(
          children: [
            if (_selecting)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _selected.clear();
                            if (!allSelected) {
                              _selected.addAll(items.map((n) => n.id));
                            }
                          }),
                    child: Text(allSelected ? 'Deselect all' : 'Select all'),
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                color: AppPalette.of(context).accent,
                onRefresh: () async {
                  try {
                    await ref.read(myNotificationsProvider.notifier).refresh();
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Couldn't refresh notifications. Try again.",
                          ),
                        ),
                      );
                    }
                  }
                },
                child: notificationsAsync.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
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
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) => _NotificationTile(
                        key: ValueKey(items[i].id),
                        notification: items[i],
                        selecting: _selecting,
                        selected: selected.contains(items[i].id),
                        onSelect: _busy ? null : () => _toggle(items[i].id),
                      ),
                    );
                  },
                  loading: () => Center(
                    child: CircularProgressIndicator(
                      color: AppPalette.of(context).accent,
                    ),
                  ),
                  error: (e, _) => ErrorState(
                    onRetry: () => ref.invalidate(myNotificationsProvider),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final AppNotification notification;
  final bool selecting;
  final bool selected;
  final VoidCallback? onSelect;
  const _NotificationTile({
    super.key,
    required this.notification,
    required this.selecting,
    required this.selected,
    required this.onSelect,
  });

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
      color: AppPalette.of(context).surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        selected: selecting ? selected : null,
        child: InkWell(
          onLongPress: onSelect,
          onTap: selecting
              ? onSelect
              : () async {
                  if (unread) {
                    ref
                        .read(myNotificationsProvider.notifier)
                        .markRead(notification.id);
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
                if (selecting)
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Checkbox(
                      value: selected,
                      onChanged: onSelect == null ? null : (_) => onSelect!(),
                      semanticLabel: 'Select ${notification.title}',
                    ),
                  )
                else
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: unread
                          ? AppPalette.of(context).accentSoft
                          : AppPalette.of(context).background,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _icon,
                      size: 18,
                      color: unread
                          ? AppPalette.of(context).accent
                          : AppPalette.of(context).textMuted,
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
                          fontWeight: unread
                              ? FontWeight.w700
                              : FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        notification.body,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppPalette.of(context).textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat.yMMMd().add_jm().format(
                          notification.createdAt,
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppPalette.of(context).textMuted,
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
                    decoration: BoxDecoration(
                      color: AppPalette.of(context).accent,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
