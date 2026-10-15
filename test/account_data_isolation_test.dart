import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/profile/data/address_repository.dart';
import 'package:marugen_app/features/profile/presentation/address_book_screen.dart';
import 'package:marugen_app/features/profile/presentation/address_providers.dart';
import 'package:marugen_app/features/notifications/data/notification_repository.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/shared/models/address.dart';
import 'package:marugen_app/shared/models/app_notification.dart';

final account = StateProvider<String?>((ref) => 'A');
const addressA = Address(
  id: 'address-A',
  userId: 'A',
  recipientName: 'Alice',
  phone: '123',
  line1: 'Private Street',
  postalCode: '123456',
);
const addressB = Address(
  id: 'address-B',
  userId: 'B',
  recipientName: 'Bob',
  phone: '456',
  line1: 'Other Street',
  postalCode: '654321',
);

class Addresses implements AddressRepository {
  List<Address> items = [addressA];
  int mutations = 0;
  @override
  Future<List<Address>> fetchMyAddresses() async => items;
  @override
  Future<Address> createAddress(Address address) async {
    mutations++;
    return address;
  }

  @override
  Future<void> updateAddress(Address address) async {
    mutations++;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Notifications implements NotificationRepository {
  final loads = <Completer<List<AppNotification>>>[];
  final reads = <Completer<void>>[];
  @override
  Future<List<AppNotification>> fetchMine() {
    final c = Completer<List<AppNotification>>();
    loads.add(c);
    return c.future;
  }

  @override
  Future<void> markRead(String id) {
    final c = Completer<void>();
    reads.add(c);
    return c.future;
  }

  @override
  Future<void> markAllRead() {
    final c = Completer<void>();
    reads.add(c);
    return c.future;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

AppNotification note(String id) => AppNotification(
  id: id,
  title: id,
  body: id,
  type: 'order_status',
  read: false,
  createdAt: DateTime(2026),
);
Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('addresses refetch for a new account and clear on logout', () async {
    final repo = Addresses();
    final c = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith((ref) => ref.watch(account)),
        addressRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(c.dispose);
    expect(await c.read(myAddressesProvider.future), [addressA]);
    repo.items = [addressB];
    c.read(account.notifier).state = 'B';
    expect(await c.read(myAddressesProvider.future), [addressB]);
    c.read(account.notifier).state = null;
    expect(await c.read(myAddressesProvider.future), isEmpty);
  });
  test('late inbox load cannot overwrite the next account inbox', () async {
    final repo = Notifications();
    final c = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith((ref) => ref.watch(account)),
        notificationRepositoryProvider.overrideWithValue(repo),
        notificationInsertsProvider.overrideWith(
          (ref, owner) => const Stream.empty(),
        ),
        notificationBadgeWriterProvider.overrideWithValue((_) async {}),
      ],
    );
    addTearDown(c.dispose);
    c.read(myNotificationsProvider);
    c.read(account.notifier).state = 'B';
    c.read(myNotificationsProvider);
    repo.loads[1].complete([note('B')]);
    await flush();
    repo.loads[0].complete([note('A')]);
    await flush();
    expect(c.read(myNotificationsProvider).requireValue.single.id, 'B');
    expect(c.read(unreadNotificationCountProvider), 1);
  });
  test(
    'read failure from prior account cannot replace the next inbox',
    () async {
      final repo = Notifications();
      final c = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWith((ref) => ref.watch(account)),
          notificationRepositoryProvider.overrideWithValue(repo),
          notificationInsertsProvider.overrideWith(
            (ref, owner) => const Stream.empty(),
          ),
          notificationBadgeWriterProvider.overrideWithValue((_) async {}),
        ],
      );
      addTearDown(c.dispose);
      c.read(myNotificationsProvider);
      repo.loads[0].complete([note('A')]);
      await flush();
      final read = c.read(myNotificationsProvider.notifier).markRead('A');
      c.read(account.notifier).state = 'B';
      c.read(myNotificationsProvider);
      repo.loads[1].complete([note('B')]);
      await flush();
      repo.reads[0].completeError(Exception('failed'));
      await read;
      expect(c.read(myNotificationsProvider).requireValue.single.id, 'B');
    },
  );
  test('failed read rolls back only its notification', () async {
    final repo = Notifications();
    final c = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith((ref) => ref.watch(account)),
        notificationRepositoryProvider.overrideWithValue(repo),
        notificationInsertsProvider.overrideWith(
          (ref, owner) => const Stream.empty(),
        ),
        notificationBadgeWriterProvider.overrideWithValue((_) async {}),
      ],
    );
    addTearDown(c.dispose);
    c.read(myNotificationsProvider);
    repo.loads[0].complete([note('first'), note('second')]);
    await flush();
    final notifier = c.read(myNotificationsProvider.notifier);
    final first = notifier.markRead('first');
    final second = notifier.markRead('second');
    repo.reads[1].complete();
    await second;
    repo.reads[0].completeError(Exception('failed'));
    await first;
    final items = c.read(myNotificationsProvider).requireValue;
    expect(items.first.read, isFalse);
    expect(items.last.read, isTrue);
  });
  test('logout clears the inbox and ignores a pending load failure', () async {
    final repo = Notifications();
    final c = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith((ref) => ref.watch(account)),
        notificationRepositoryProvider.overrideWithValue(repo),
        notificationInsertsProvider.overrideWith(
          (ref, owner) => const Stream.empty(),
        ),
        notificationBadgeWriterProvider.overrideWithValue((_) async {}),
      ],
    );
    addTearDown(c.dispose);
    c.read(myNotificationsProvider);
    c.read(account.notifier).state = null;
    expect(c.read(myNotificationsProvider).requireValue, isEmpty);
    repo.loads[0].completeError(Exception('old account failure'));
    await flush();
    expect(c.read(myNotificationsProvider).requireValue, isEmpty);
    expect(c.read(unreadNotificationCountProvider), 0);
  });
  for (final all in [false, true]) {
    test(
      'failed ${all ? 'all' : 'single'} read preserves realtime inserts and later successful reads',
      () async {
        final repo = Notifications();
        final events = StreamController<AppNotification>();
        addTearDown(events.close);
        final c = ProviderContainer(
          overrides: [
            currentUserIdProvider.overrideWith((ref) => ref.watch(account)),
            notificationRepositoryProvider.overrideWithValue(repo),
            notificationInsertsProvider.overrideWith(
              (ref, owner) => events.stream,
            ),
            notificationBadgeWriterProvider.overrideWithValue((_) async {}),
          ],
        );
        addTearDown(c.dispose);
        c.read(myNotificationsProvider);
        repo.loads[0].complete([note('first')]);
        await flush();
        final notifier = c.read(myNotificationsProvider.notifier);
        final failed = all
            ? notifier.markAllRead()
            : notifier.markRead('first');
        events.add(note('inserted'));
        await flush();
        final success = notifier.markRead('inserted');
        repo.reads[1].complete();
        await success;
        repo.reads[0].completeError(Exception('failed'));
        await failed;
        final items = c.read(myNotificationsProvider).requireValue;
        expect(items.map((n) => n.id), ['inserted', 'first']);
        expect(items.first.read, isTrue);
        expect(items.last.read, isFalse);
        expect(c.read(unreadNotificationCountProvider), 1);
      },
    );
  }
  test(
    'overlapping read failures restore unread while any success keeps read',
    () async {
      final repo = Notifications();
      final c = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWith((ref) => ref.watch(account)),
          notificationRepositoryProvider.overrideWithValue(repo),
          notificationInsertsProvider.overrideWith(
            (ref, owner) => const Stream.empty(),
          ),
          notificationBadgeWriterProvider.overrideWithValue((_) async {}),
        ],
      );
      addTearDown(c.dispose);
      c.read(myNotificationsProvider);
      repo.loads[0].complete([note('first')]);
      await flush();
      final notifier = c.read(myNotificationsProvider.notifier);
      final one = notifier.markRead('first');
      final two = notifier.markAllRead();
      repo.reads[0].completeError(Exception('failed'));
      await one;
      expect(c.read(myNotificationsProvider).requireValue.single.read, isTrue);
      repo.reads[1].completeError(Exception('failed'));
      await two;
      expect(c.read(myNotificationsProvider).requireValue.single.read, isFalse);
      final three = notifier.markRead('first');
      final four = notifier.markAllRead();
      repo.reads[3].complete();
      await four;
      repo.reads[2].completeError(Exception('failed'));
      await three;
      expect(c.read(myNotificationsProvider).requireValue.single.read, isTrue);
    },
  );
  test(
    'new account badge follows an old OS write already in progress',
    () async {
      final repo = Notifications();
      final writes = <int>[];
      final oldWrite = Completer<void>();
      final c = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWith((ref) => ref.watch(account)),
          notificationRepositoryProvider.overrideWithValue(repo),
          notificationInsertsProvider.overrideWith(
            (ref, owner) => const Stream.empty(),
          ),
          notificationBadgeWriterProvider.overrideWithValue((count) async {
            writes.add(count);
            if (writes.length == 2) await oldWrite.future;
          }),
        ],
      );
      addTearDown(c.dispose);
      c.read(myNotificationsProvider);
      await flush();
      repo.loads[0].complete([note('A')]);
      await flush();
      expect(writes, [0, 1]);
      c.read(account.notifier).state = 'B';
      c.read(myNotificationsProvider);
      repo.loads[1].complete([]);
      await flush();
      oldWrite.complete();
      await flush();
      expect(writes.last, 0);
      expect(c.read(unreadNotificationCountProvider), 0);
    },
  );
  testWidgets('guest address page shows sign in without creating addresses', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue(null),
          addressRepositoryProvider.overrideWithValue(Addresses()),
        ],
        child: const MaterialApp(home: AddressBookScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Log in to your account'), findsOneWidget);
    expect(find.text('Add Address'), findsNothing);
    expect(find.text('Alice'), findsNothing);
  });
  for (final existing in [null, addressA]) {
    testWidgets(
      'address ${existing == null ? 'create' : 'edit'} form closes access after switching account',
      (tester) async {
        final repo = Addresses();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUserIdProvider.overrideWith((ref) => ref.watch(account)),
              addressRepositoryProvider.overrideWithValue(repo),
            ],
            child: MaterialApp(
              home: Scaffold(body: AddressForm(existing: existing)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final c = ProviderScope.containerOf(
          tester.element(find.byType(AddressForm)),
        );
        c.read(account.notifier).state = 'B';
        await tester.pumpAndSettle();
        expect(find.text('Save Address'), findsNothing);
        expect(find.text('Alice'), findsNothing);
        expect(repo.mutations, 0);
      },
    );
  }
}
