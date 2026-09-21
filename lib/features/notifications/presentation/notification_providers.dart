import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/app_notification.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(),
);

/// Full inbox (customer and admin both just see their own rows via RLS —
/// see NotificationRepository's doc comment).
///
/// A hand-rolled `Notifier` (same pattern as `CartNotifier` in
/// cart_providers.dart / `WishlistIdsNotifier` in wishlist_providers.dart)
/// rather than a plain `FutureProvider`: marking a notification read used
/// to `ref.invalidate` this and wait for a full network refetch before
/// the bold/dot visually cleared, which read as laggy on a tap that
/// should feel instant. `markRead`/`markAllRead` below flip the cached
/// list immediately and only talk to the network in the background.
class NotificationsNotifier extends Notifier<AsyncValue<List<AppNotification>>> {
  RealtimeChannel? _channel;

  @override
  AsyncValue<List<AppNotification>> build() {
    // Rebuild (and re-subscribe below) whenever the signed-in user
    // actually changes — same pattern as CartNotifier in
    // cart_providers.dart — so switching accounts on one device doesn't
    // keep the previous user's inbox/subscription around.
    ref.watch(currentUserIdProvider);
    _load();
    _subscribeToChanges();
    ref.onDispose(() {
      final channel = _channel;
      if (channel != null) SupabaseService.client.removeChannel(channel);
    });
    return const AsyncLoading();
  }

  /// Previously the inbox/bell badge only updated on manual pull-to-refresh
  /// or reopening the screen — a shipped/packed notification written
  /// server-side (send-order-notification) wouldn't appear while the app
  /// was already open in the foreground. Supabase Realtime pushes new rows
  /// the moment they're inserted instead.
  void _subscribeToChanges() {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    _channel = SupabaseService.client
        .channel('notifications:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            final notification = AppNotification.fromMap(payload.newRecord);
            final current = state.valueOrNull;
            if (current == null) return;
            // _load() may have already fetched this row (race between the
            // initial select and the subscription coming up) — don't
            // double-add it.
            if (current.any((n) => n.id == notification.id)) return;
            state = AsyncData([notification, ...current]);
          },
        )
        .subscribe();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(notificationRepositoryProvider).fetchMine();
      state = AsyncData(items);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> markRead(String id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final n in current)
        if (n.id == id) n.copyWith(read: true) else n,
    ]);
    try {
      await ref.read(notificationRepositoryProvider).markRead(id);
    } catch (_) {
      state = AsyncData(current);
    }
  }

  Future<void> markAllRead() async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([for (final n in current) n.copyWith(read: true)]);
    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
    } catch (_) {
      state = AsyncData(current);
    }
  }
}

final myNotificationsProvider =
    NotifierProvider<NotificationsNotifier, AsyncValue<List<AppNotification>>>(
        NotificationsNotifier.new);

/// Drives the bell-icon badge in both the customer (ShopScreen) and admin
/// (AdminDashboardScreen) app bars. Derived from [myNotificationsProvider]
/// instead of its own separate fetch — same pattern as `cartCountProvider`
/// deriving from `cartProvider` — so the badge updates in the same frame
/// as the list instead of one network round-trip behind it, and one fewer
/// query fires on every app-bar build.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final items = ref.watch(myNotificationsProvider).valueOrNull;
  if (items == null) return 0;
  return items.where((n) => !n.read).length;
});
