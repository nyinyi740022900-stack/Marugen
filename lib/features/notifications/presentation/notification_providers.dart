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

/// Recovery capability tied to the account, provider generation and exact rows.
class NotificationDismissal {
  final String owner;
  final int generation;
  final String dismissedAt;
  final List<AppNotification> items;
  NotificationDismissal._(
    this.owner,
    this.generation,
    this.dismissedAt,
    List<AppNotification> items,
  ) : items = List.unmodifiable(items);
  Set<String> get ids => items.map((n) => n.id).toSet();
}

/// An account-scoped inbox with immediate read feedback. Generations protect
/// responses and realtime events that arrive after logout or an account switch.
class NotificationsNotifier
    extends Notifier<AsyncValue<List<AppNotification>>> {
  int _generation = 0;
  String? _owner;
  final _reads = <String, _PendingRead>{};
  final _dismissed = <String, String>{};
  final _dismissedItems = <String, AppNotification>{};
  final _pendingDismissals = <String>{};
  int _loadVersion = 0;
  int _lastDismissalMicros = 0;
  Future<void> _badgeWork = Future.value();

  @override
  AsyncValue<List<AppNotification>> build() {
    final owner = ref.watch(currentUserIdProvider);
    _owner = owner;
    final generation = ++_generation;
    _reads.clear();
    _dismissed.clear();
    _dismissedItems.clear();
    _pendingDismissals.clear();
    ref.onDispose(() => _generation++);
    _queueBadge(0, owner, generation);
    if (owner == null) return const AsyncData([]);
    ref.listen(notificationInsertsProvider(owner), (_, next) {
      final notification = next.valueOrNull;
      if (notification == null ||
          notification.dismissedAt != null ||
          _dismissed.containsKey(notification.id) ||
          !_isCurrent(owner, generation)) {
        return;
      }
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
    final version = ++_loadVersion;
    try {
      final items = await ref.read(notificationRepositoryProvider).fetchMine();
      if (_isCurrent(owner, generation) && version == _loadVersion) {
        _setData(items);
      }
    } catch (e, st) {
      if (_isCurrent(owner, generation) && version == _loadVersion) {
        if (state.valueOrNull == null) {
          state = AsyncError(e, st);
        } else {
          rethrow;
        }
      }
    }
  }

  Future<void> refresh() async {
    final owner = _owner;
    if (owner != null && _isCurrent(owner, _generation)) {
      await _load(owner, _generation);
    }
  }

  Future<NotificationDismissal?> dismissSelected(Set<String> ids) async {
    final owner = _owner;
    final generation = _generation;
    if (owner == null || !_isCurrent(owner, generation)) return null;
    final targets = (state.valueOrNull ?? <AppNotification>[])
        .where((n) => ids.contains(n.id) && !_pendingDismissals.contains(n.id))
        .toList();
    if (targets.isEmpty) return null;
    final targetIds = targets.map((n) => n.id).toSet();
    _pendingDismissals.addAll(targetIds);
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    _lastDismissalMicros = now > _lastDismissalMicros
        ? now
        : _lastDismissalMicros + 1;
    final stamp = DateTime.fromMicrosecondsSinceEpoch(
      _lastDismissalMicros,
      isUtc: true,
    ).toIso8601String();
    try {
      final changed = await ref
          .read(notificationRepositoryProvider)
          .dismiss(targetIds, owner: owner, dismissedAt: stamp);
      if (!_isCurrent(owner, generation)) return null;
      final confirmed = targets.where((n) => changed.contains(n.id)).toList();
      if (confirmed.isEmpty) throw StateError('No notifications deleted');
      // Earlier fetches describe the inbox before this mutation.
      _loadVersion++;
      for (final n in confirmed) {
        _dismissed[n.id] = stamp;
      }
      // Snapshot the latest read values, including reads completed while saving.
      final latest = {
        for (final n in state.valueOrNull ?? <AppNotification>[]) n.id: n,
      };
      final batch = NotificationDismissal._(owner, generation, stamp, [
        for (final n in confirmed) latest[n.id] ?? n,
      ]);
      for (final n in batch.items) {
        _dismissedItems[n.id] = n;
      }
      _setData(state.valueOrNull ?? []);
      return batch;
    } finally {
      if (_isCurrent(owner, generation)) {
        _pendingDismissals.removeAll(targetIds);
      }
    }
  }

  /// Safe for recovery actions retained by the app messenger after route pop.
  bool isCurrentDismissal(NotificationDismissal batch) =>
      _isCurrent(batch.owner, batch.generation);

  Future<bool> undoDismissal(NotificationDismissal batch) async {
    if (!isCurrentDismissal(batch)) return false;
    final ids = batch.ids
        .where((id) => _dismissed[id] == batch.dismissedAt)
        .toSet();
    if (ids.isEmpty) return false;
    final restored = await ref
        .read(notificationRepositoryProvider)
        .restore(ids, owner: batch.owner, dismissedAt: batch.dismissedAt);
    if (!_isCurrent(batch.owner, batch.generation)) return false;
    final confirmed = ids
        .where(
          (id) => restored.contains(id) && _dismissed[id] == batch.dismissedAt,
        )
        .toSet();
    if (confirmed.isEmpty) throw StateError('No notifications restored');
    _loadVersion++;
    final recovered = [
      for (final n in batch.items)
        if (confirmed.contains(n.id)) _dismissedItems[n.id] ?? n,
    ];
    for (final id in confirmed) {
      _dismissed.remove(id);
      _dismissedItems.remove(id);
    }
    final current = state.valueOrNull ?? <AppNotification>[];
    final existing = current.map((n) => n.id).toSet();
    _setData(
      [...current, ...recovered.where((n) => !existing.contains(n.id))]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
    return confirmed.length == ids.length;
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
    for (final entry in readValues.entries) {
      final hidden = _dismissedItems[entry.key];
      if (hidden != null) {
        _dismissedItems[entry.key] = hidden.copyWith(read: entry.value);
      }
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
    final visible = items
        .where((n) => n.dismissedAt == null && !_dismissed.containsKey(n.id))
        .toList();
    state = AsyncData(visible);
    _queueBadge(visible.where((n) => !n.read).length, _owner, _generation);
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
