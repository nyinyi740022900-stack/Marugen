import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/notifications/app_icon_badge.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/app_notification.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(),
);

/// Each subscription is scoped to its owner and closed when no longer used.
final notificationInsertsProvider = StreamProvider.autoDispose
    .family<AppNotification, String>((ref, owner) {
      final events = StreamController<AppNotification>();
      final channel = SupabaseService.client
          .channel('notifications:$owner')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: owner,
            ),
            callback: (payload) {
              if (!events.isClosed && payload.newRecord['user_id'] == owner) {
                events.add(AppNotification.fromMap(payload.newRecord));
              }
            },
          )
          .subscribe();
      ref.onDispose(() {
        unawaited(SupabaseService.client.removeChannel(channel));
        unawaited(events.close());
      });
      return events.stream;
    });

final notificationBadgeWriterProvider = Provider<Future<void> Function(int)>(
  (ref) => AppIconBadge.set,
);

class _PendingRead {
  bool confirmed;
  final pending = <Object>{};
  _PendingRead(this.confirmed);
}

/// An account-scoped inbox with immediate read feedback. Generations protect
/// responses and realtime events that arrive after logout or an account switch.
class NotificationsNotifier
    extends Notifier<AsyncValue<List<AppNotification>>> {
  int _generation = 0;
  String? _owner;
  final _reads = <String, _PendingRead>{};
  Future<void> _badgeWork = Future.value();

  @override
  AsyncValue<List<AppNotification>> build() {
    final owner = ref.watch(currentUserIdProvider);
    _owner = owner;
    final generation = ++_generation;
    _reads.clear();
    ref.onDispose(() => _generation++);
    _queueBadge(0, owner, generation);
    if (owner == null) return const AsyncData([]);
    ref.listen(notificationInsertsProvider(owner), (_, next) {
      final notification = next.valueOrNull;
      if (notification == null || !_isCurrent(owner, generation)) return;
      final current = state.valueOrNull;
      if (current == null || current.any((n) => n.id == notification.id)) {
        return;
      }
      _setData([notification, ...current]);
    });
    unawaited(_load(owner, generation));
    return const AsyncLoading();
  }

  bool _isCurrent(String? owner, int generation) =>
      generation == _generation &&
      owner == _owner &&
      ref.read(currentUserIdProvider) == owner;

  Future<void> _load(String owner, int generation) async {
    try {
      final items = await ref.read(notificationRepositoryProvider).fetchMine();
      if (_isCurrent(owner, generation)) _setData(items);
    } catch (e, st) {
      if (_isCurrent(owner, generation)) state = AsyncError(e, st);
    }
  }

  Future<void> markRead(String id) => _markRead(all: false, id: id);
  Future<void> markAllRead() => _markRead(all: true);

  Future<void> _markRead({required bool all, String? id}) async {
    final owner = _owner;
    final generation = _generation;
    if (owner == null || !_isCurrent(owner, generation)) return;
    final current = state.valueOrNull;
    if (current == null) return;
    final targets = current
        .where(
          (n) => (all || n.id == id) && (!n.read || _reads.containsKey(n.id)),
        )
        .toList();
    if (targets.isEmpty) return;
    final operation = Object();
    for (final n in targets) {
      (_reads[n.id] ??= _PendingRead(n.read)).pending.add(operation);
    }
    _setData([
      for (final n in current)
        if (_reads[n.id]?.pending.contains(operation) ?? false)
          n.copyWith(read: true)
        else
          n,
    ]);
    var succeeded = false;
    try {
      final repo = ref.read(notificationRepositoryProvider);
      if (all) {
        await repo.markAllRead();
      } else {
        await repo.markRead(id!);
      }
      succeeded = true;
    } catch (_) {
      // Restore only this operation's read changes below.
    }
    if (!_isCurrent(owner, generation)) return;
    final readValues = <String, bool>{};
    for (final n in targets) {
      final entry = _reads[n.id];
      if (entry == null) continue;
      entry.pending.remove(operation);
      if (succeeded) entry.confirmed = true;
      readValues[n.id] = entry.confirmed || entry.pending.isNotEmpty;
      if (entry.pending.isEmpty) _reads.remove(n.id);
    }
    _setData([
      for (final n in state.valueOrNull ?? <AppNotification>[])
        if (readValues.containsKey(n.id))
          n.copyWith(read: readValues[n.id])
        else
          n,
    ]);
  }

  void _setData(List<AppNotification> items) {
    state = AsyncData(items);
    _queueBadge(items.where((n) => !n.read).length, _owner, _generation);
  }

  /// Serialize OS writes so an old write already in progress finishes before
  /// the new account's clear/count; discard queued work from old generations.
  void _queueBadge(int count, String? owner, int generation) {
    final write = ref.read(notificationBadgeWriterProvider);
    _badgeWork = _badgeWork
        .then((_) async {
          if (_isCurrent(owner, generation)) await write(count);
        })
        .catchError((Object _) {});
  }
}

final myNotificationsProvider =
    NotifierProvider<NotificationsNotifier, AsyncValue<List<AppNotification>>>(
      NotificationsNotifier.new,
    );

final unreadNotificationCountProvider = Provider<int>((ref) {
  final items = ref.watch(myNotificationsProvider).valueOrNull;
  return items?.where((n) => !n.read).length ?? 0;
});
