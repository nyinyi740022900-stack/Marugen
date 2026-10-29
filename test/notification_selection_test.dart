import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/notifications/data/notification_repository.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/features/notifications/presentation/notifications_screen.dart';
import 'package:marugen_app/shared/models/app_notification.dart';

final account = StateProvider<String?>((ref) => 'A');
AppNotification note(String id) => AppNotification(
  id: id,
  title: 'Order $id',
  body: 'Your order has been shipped.',
  type: 'order_status',
  read: false,
  createdAt: DateTime(2026),
);
Future<void> flush() => Future<void>.delayed(Duration.zero);

class InboxRepository implements NotificationRepository {
  List<AppNotification> items = [note('one'), note('two')];
  Completer<Set<String>>? deleting;
  Completer<void>? reading;
  Completer<Set<String>>? restoring;
  Completer<List<AppNotification>>? loading;
  final dismissals = <({String owner, Set<String> ids, String stamp})>[];
  final restorations = <({String owner, Set<String> ids, String stamp})>[];
  @override
  Future<void> markRead(String id) async {
    await reading?.future;
  }

  @override
  Future<List<AppNotification>> fetchMine() async =>
      loading == null ? items : loading!.future;
  @override
  Future<Set<String>> dismiss(
    Set<String> ids, {
    required String owner,
    required String dismissedAt,
  }) async {
    dismissals.add((owner: owner, ids: ids, stamp: dismissedAt));
    return deleting == null ? ids : deleting!.future;
  }

  @override
  Future<Set<String>> restore(
    Set<String> ids, {
    required String owner,
    required String dismissedAt,
  }) async {
    restorations.add((owner: owner, ids: ids, stamp: dismissedAt));
    return restoring == null ? ids : restoring!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer container(
  InboxRepository repo, {
  Stream<AppNotification>? events,
}) => ProviderContainer(
  overrides: [
    currentUserIdProvider.overrideWith((ref) => ref.watch(account)),
    notificationRepositoryProvider.overrideWithValue(repo),
    notificationInsertsProvider.overrideWith(
      (ref, owner) => events ?? const Stream.empty(),
    ),
    notificationBadgeWriterProvider.overrideWithValue((_) async {}),
  ],
);

void main() async {
  if (Platform.environment['NOTIFICATION_CAPTURE'] == '1') {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await File('/System/Library/Fonts/SFNS.ttf').readAsBytes();
    for (final family in ['.SF Pro Text', 'Roboto']) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  }
  test(
    'delete waits for success, restores unread badge on Undo, and scopes batch',
    () async {
      final repo = InboxRepository()..deleting = Completer<Set<String>>();
      final c = container(repo);
      addTearDown(c.dispose);
      c.read(myNotificationsProvider);
      await flush();
      final notifier = c.read(myNotificationsProvider.notifier);
      final deleting = notifier.dismissSelected({'one'});
      expect(c.read(myNotificationsProvider).requireValue.length, 2);
      repo.deleting!.complete({'one'});
      final batch = (await deleting)!;
      expect(c.read(myNotificationsProvider).requireValue.single.id, 'two');
      expect(c.read(unreadNotificationCountProvider), 1);
      expect(await notifier.undoDismissal(batch), isTrue);
      expect(c.read(unreadNotificationCountProvider), 2);
      expect(repo.restorations.single.stamp, repo.dismissals.single.stamp);
      expect(repo.restorations.single.owner, 'A');
      expect(repo.restorations.single.ids, {'one'});
    },
  );
  test('failed deletion preserves rows and unread state for retry', () async {
    final repo = InboxRepository()..deleting = Completer<Set<String>>();
    final c = container(repo);
    addTearDown(c.dispose);
    c.read(myNotificationsProvider);
    await flush();
    final deleting = c.read(myNotificationsProvider.notifier).dismissSelected({
      'one',
    });
    final assertion = expectLater(deleting, throwsStateError);
    repo.deleting!.completeError(StateError('offline'));
    await assertion;
    expect(c.read(myNotificationsProvider).requireValue.length, 2);
    expect(c.read(unreadNotificationCountProvider), 2);
  });
  test(
    'late fetch and realtime insert do not resurrect a dismissed row',
    () async {
      final events = StreamController<AppNotification>();
      addTearDown(events.close);
      final repo = InboxRepository();
      final c = container(repo, events: events.stream);
      addTearDown(c.dispose);
      c.read(myNotificationsProvider);
      await flush();
      final notifier = c.read(myNotificationsProvider.notifier);
      repo.loading = Completer<List<AppNotification>>();
      final loading = notifier.refresh();
      await notifier.dismissSelected({'one'});
      events.add(note('one'));
      await flush();
      repo.loading!.complete([note('one'), note('two')]);
      await loading;
      expect(c.read(myNotificationsProvider).requireValue.map((n) => n.id), [
        'two',
      ]);
    },
  );
  test('late deletion and Undo cannot affect another account', () async {
    final repo = InboxRepository()..deleting = Completer<Set<String>>();
    final c = container(repo);
    addTearDown(c.dispose);
    c.read(myNotificationsProvider);
    await flush();
    final notifier = c.read(myNotificationsProvider.notifier);
    final batch = (await (() async {
      final deleting = notifier.dismissSelected({'one'});
      repo.deleting!.complete({'one'});
      return deleting;
    })())!;
    repo.items = [note('B')];
    c.read(account.notifier).state = 'B';
    c.read(myNotificationsProvider);
    await flush();
    expect(await notifier.undoDismissal(batch), isFalse);
    expect(repo.restorations, isEmpty);
    expect(c.read(myNotificationsProvider).requireValue.single.id, 'B');
    repo.deleting = Completer<Set<String>>();
    final deleting = notifier.dismissSelected({'B'});
    repo.items = [note('C')];
    c.read(account.notifier).state = 'C';
    c.read(myNotificationsProvider);
    await flush();
    repo.deleting!.complete({'B'});
    expect(await deleting, isNull);
    expect(c.read(myNotificationsProvider).requireValue.single.id, 'C');
  });
  test('old Undo cannot reverse a later deletion of the same item', () async {
    final repo = InboxRepository();
    final c = container(repo);
    addTearDown(c.dispose);
    c.read(myNotificationsProvider);
    await flush();
    final notifier = c.read(myNotificationsProvider.notifier);
    final old = (await notifier.dismissSelected({'one'}))!;
    await notifier.undoDismissal(old);
    await notifier.dismissSelected({'one'});
    expect(await notifier.undoDismissal(old), isFalse);
    expect(c.read(myNotificationsProvider).requireValue.single.id, 'two');
    expect(repo.restorations, hasLength(1));
  });
  test('failed Undo keeps dismissal and can retry', () async {
    final repo = InboxRepository();
    final c = container(repo);
    addTearDown(c.dispose);
    c.read(myNotificationsProvider);
    await flush();
    final notifier = c.read(myNotificationsProvider.notifier);
    final batch = (await notifier.dismissSelected({'one'}))!;
    repo.restoring = Completer<Set<String>>();
    final undo = notifier.undoDismissal(batch);
    final assertion = expectLater(undo, throwsStateError);
    repo.restoring!.completeError(StateError('offline'));
    await assertion;
    expect(c.read(myNotificationsProvider).requireValue.single.id, 'two');
    repo.restoring = null;
    expect(await notifier.undoDismissal(batch), isTrue);
  });
  test(
    'a refresh started before Undo cannot hide the restored batch',
    () async {
      final repo = InboxRepository();
      final c = container(repo);
      addTearDown(c.dispose);
      c.read(myNotificationsProvider);
      await flush();
      final notifier = c.read(myNotificationsProvider.notifier);
      final batch = (await notifier.dismissSelected({'one'}))!;
      repo.loading = Completer<List<AppNotification>>();
      final loading = notifier.refresh();
      await notifier.undoDismissal(batch);
      repo.loading!.complete([note('two')]);
      await loading;
      expect(
        c.read(myNotificationsProvider).requireValue.map((n) => n.id).toSet(),
        {'one', 'two'},
      );
    },
  );
  test(
    'Undo keeps a read rollback that finishes while the row is dismissed',
    () async {
      final repo = InboxRepository()..reading = Completer<void>();
      final c = container(repo);
      addTearDown(c.dispose);
      c.read(myNotificationsProvider);
      await flush();
      final notifier = c.read(myNotificationsProvider.notifier);
      final reading = notifier.markRead('one');
      final batch = (await notifier.dismissSelected({'one'}))!;
      repo.reading!.completeError(StateError('offline'));
      await reading;
      await notifier.undoDismissal(batch);
      expect(
        c
            .read(myNotificationsProvider)
            .requireValue
            .firstWhere((n) => n.id == 'one')
            .read,
        isFalse,
      );
      expect(c.read(unreadNotificationCountProvider), 2);
    },
  );
  test(
    'only acknowledged selected rows disappear and enter the Undo batch',
    () async {
      final repo = InboxRepository()..deleting = Completer<Set<String>>();
      final c = container(repo);
      addTearDown(c.dispose);
      c.read(myNotificationsProvider);
      await flush();
      final deleting = c.read(myNotificationsProvider.notifier).dismissSelected(
        {'one', 'two'},
      );
      repo.deleting!.complete({'one', 'unrequested'});
      final batch = (await deleting)!;
      expect(batch.ids, {'one'});
      expect(c.read(myNotificationsProvider).requireValue.single.id, 'two');
    },
  );
  test(
    'late Undo completion cannot add private rows to another account',
    () async {
      final repo = InboxRepository();
      final c = container(repo);
      addTearDown(c.dispose);
      c.read(myNotificationsProvider);
      await flush();
      final notifier = c.read(myNotificationsProvider.notifier);
      final batch = (await notifier.dismissSelected({'one'}))!;
      repo.restoring = Completer<Set<String>>();
      final undo = notifier.undoDismissal(batch);
      repo.items = [note('B')];
      c.read(account.notifier).state = 'B';
      c.read(myNotificationsProvider);
      await flush();
      repo.restoring!.complete({'one'});
      expect(await undo, isFalse);
      expect(c.read(myNotificationsProvider).requireValue.single.id, 'B');
    },
  );
  for (final switchAccount in [false, true]) {
    testWidgets(
      'Undo after notification route pop switchAccount=$switchAccount',
      (tester) async {
        final repo = InboxRepository();
        final c = container(repo);
        addTearDown(c.dispose);
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              navigatorKey: navigator,
              home: const Scaffold(body: Text('Home')),
            ),
          ),
        );
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => ProviderScope(
              overrides: [isLoggedInProvider.overrideWithValue(true)],
              child: const NotificationsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.text('Order one'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Delete selected'));
        await tester.pumpAndSettle();
        expect(c.read(myNotificationsProvider).requireValue.map((n) => n.id), [
          'two',
        ]);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.byType(NotificationsScreen), findsNothing);
        expect(find.text('Undo'), findsOneWidget);
        if (switchAccount) {
          repo.items = [note('B')];
          c.read(account.notifier).state = 'B';
          c.read(myNotificationsProvider);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (switchAccount) {
          expect(repo.restorations, isEmpty);
          expect(c.read(myNotificationsProvider).requireValue.single.id, 'B');
        } else {
          expect(repo.restorations, hasLength(1));
          expect(
            c
                .read(myNotificationsProvider)
                .requireValue
                .map((n) => n.id)
                .toSet(),
            {'one', 'two'},
          );
        }
      },
    );
  }
  for (final brightness in Brightness.values) {
    testWidgets(
      'select, cancel, delete and Undo at 320px 2x ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = InboxRepository()..deleting = Completer<Set<String>>();
        final events = StreamController<AppNotification>();
        addTearDown(events.close);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUserIdProvider.overrideWithValue('A'),
              isLoggedInProvider.overrideWithValue(true),
              notificationRepositoryProvider.overrideWithValue(repo),
              notificationInsertsProvider.overrideWith(
                (ref, owner) => events.stream,
              ),
              notificationBadgeWriterProvider.overrideWithValue((_) async {}),
            ],
            child: RepaintBoundary(
              key: const ValueKey('capture'),
              child: MaterialApp(
                theme: brightness == Brightness.dark
                    ? AppTheme.dark
                    : AppTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(2)),
                  child: child!,
                ),
                home: const NotificationsScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.text('Order one'));
        await tester.pumpAndSettle();
        expect(find.text('1 selected'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('1 selected'), findsNothing);
        await tester.longPress(find.text('Order one'));
        await tester.pumpAndSettle();
        final cancelSize = tester.getSize(find.byTooltip('Cancel selection'));
        expect(cancelSize.width, greaterThanOrEqualTo(48));
        expect(cancelSize.height, greaterThanOrEqualTo(48));
        await tester.tap(find.byTooltip('Cancel selection'));
        await tester.pumpAndSettle();
        expect(find.text('1 selected'), findsNothing);
        await tester.tap(find.byTooltip('Select notifications'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select all'));
        await tester.pumpAndSettle();
        expect(find.text('2 selected'), findsOneWidget);
        if (Platform.environment['NOTIFICATION_CAPTURE'] == '1') {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            await File('/tmp/notification-selection-${brightness.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        events.add(note('new arrival'));
        await tester.pumpAndSettle();
        expect(find.text('2 selected'), findsOneWidget);
        await tester.tap(find.byTooltip('Delete selected'));
        await tester.pump();
        expect(repo.dismissals.single.ids, {'one', 'two'});
        expect(find.text('Order one'), findsOneWidget);
        repo.deleting!.completeError(StateError('offline'));
        await tester.pumpAndSettle();
        expect(find.text('2 selected'), findsOneWidget);
        expect(find.textContaining('Your selection is kept'), findsOneWidget);
        repo.deleting = Completer<Set<String>>();
        await tester.tap(find.byTooltip('Delete selected'));
        await tester.pump();
        repo.deleting!.complete({'one', 'two'});
        await tester.pumpAndSettle();
        expect(find.text('Order one'), findsNothing);
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(find.text('Order one'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
