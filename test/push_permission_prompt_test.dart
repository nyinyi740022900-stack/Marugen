import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/notifications/push_notification_service.dart';
import 'package:marugen_app/core/notifications/push_permission_prompt.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/notifications/data/notification_repository.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/features/notifications/presentation/notifications_screen.dart';
import 'package:marugen_app/shared/models/app_notification.dart';
import 'package:marugen_app/features/orders/presentation/order_detail_screen.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmptyInbox implements NotificationRepository {
  @override
  Future<List<AppNotification>> fetchMine() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  /// Whether the OS would still show its prompt.
  late bool osCanAsk;
  late int osPrompts;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    osCanAsk = true;
    osPrompts = 0;
    PushPermissionPrompt.canAsk = () async => osCanAsk;
    PushPermissionPrompt.requestPermission = () async {
      osPrompts++;
      osCanAsk = false;
    };
    addTearDown(() {
      PushPermissionPrompt.canAsk = PushNotificationService.canAskPermission;
      PushPermissionPrompt.requestPermission =
          PushNotificationService.requestPermission;
    });
  });

  /// A screen that asks when it appears, like the order-placed banner.
  Future<void> showMoment(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(
          body: AskPushPermissionOnce(child: Text('Thank you — order placed!')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the reason comes first, and the OS prompt only after the '
      'customer agrees', (tester) async {
    await showMoment(tester);
    expect(find.text('Get a message when your order ships.'), findsOneWidget);
    expect(osPrompts, 0);
    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();
    expect(osPrompts, 1);
    expect(find.text('Get a message when your order ships.'), findsNothing);
  });

  testWidgets('"Not now" is an answer: no OS prompt, and no second ask on '
      'the next order', (tester) async {
    await showMoment(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(osPrompts, 0);

    await showMoment(tester);
    expect(find.text('Get a message when your order ships.'), findsNothing);
    expect(osPrompts, 0);
  });

  testWidgets('nobody is asked twice, even if the OS could still prompt', (
    tester,
  ) async {
    await showMoment(tester);
    await tester.tap(find.text('Turn on notifications'));
    await tester.pumpAndSettle();
    osCanAsk = true;
    await showMoment(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(osPrompts, 1);
  });

  testWidgets('someone who already allowed notifications sees nothing, and '
      'that does not use up the one ask', (tester) async {
    osCanAsk = false;
    await showMoment(tester);
    expect(find.byType(AlertDialog), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PushPermissionPrompt.askedPrefsKey), isNull);
  });

  testWidgets('the reason fits a small phone at 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showMoment(tester, textScale: 2);
    expect(find.text('Turn on notifications'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Not now'));
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
  });

  group('order screen', () {
    Future<void> showOrder(
      WidgetTester tester, {
      required bool justPlaced,
    }) async {
      final order = Order(
        id: 'order-12345',
        userId: 'a',
        status: OrderStatus.paid,
        total: 20,
        createdAt: DateTime(2026, 11, 1),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => const Stream.empty()),
            currentUserIdProvider.overrideWithValue('a'),
            orderByIdProvider(order.id).overrideWith((ref) async => order),
            currentAppUserProvider.overrideWith(
              (ref) async => const AppUser(id: 'a'),
            ),
          ],
          child: MaterialApp(
            home: OrderDetailScreen(
              orderId: order.id,
              order: order,
              justPlaced: justPlaced,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the first order placed is the moment the customer is '
        'asked', (tester) async {
      await showOrder(tester, justPlaced: true);
      expect(find.text('Thank you — order placed!'), findsOneWidget);
      expect(find.text('Get a message when your order ships.'), findsOneWidget);
      await tester.tap(find.text('Turn on notifications'));
      await tester.pumpAndSettle();
      expect(osPrompts, 1);
    });

    testWidgets('just looking at an order does not ask', (tester) async {
      await showOrder(tester, justPlaced: false);
      expect(find.byType(AlertDialog), findsNothing);
      expect(osPrompts, 0);
    });
  });

  group('notifications screen', () {
    Future<void> showInbox(WidgetTester tester, UserRole role) async {
      final events = StreamController<AppNotification>();
      addTearDown(events.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('a'),
            isLoggedInProvider.overrideWithValue(true),
            currentAppUserProvider.overrideWith(
              (ref) async => AppUser(id: 'a', role: role),
            ),
            notificationRepositoryProvider.overrideWithValue(EmptyInbox()),
            notificationInsertsProvider.overrideWith(
              (ref, owner) => events.stream,
            ),
            notificationBadgeWriterProvider.overrideWithValue((_) async {}),
          ],
          child: const MaterialApp(home: NotificationsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a customer opening notifications for the first time is '
        'asked there', (tester) async {
      await showInbox(tester, UserRole.customer);
      expect(find.text('Get a message when your order ships.'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
    });

    testWidgets('staff are not shown the customer reason', (tester) async {
      await showInbox(tester, UserRole.staff);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  test('without push set up at startup the OS is never consulted', () async {
    // What a test run, or a build without Firebase config, looks like.
    expect(await PushNotificationService.canAskPermission(), isFalse);
  });
}
