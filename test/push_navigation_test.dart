import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/core/notifications/push_notification_service.dart';
import 'package:marugen_app/core/router/app_router.dart';

const orderId = '7f3c2a10-5b1e-4c7d-9a2f-0e8b6d4c1a99';

void main() {
  tearDown(() => PushNotificationService.openLocation = null);

  test('a push opens its order, anything else opens the inbox', () {
    expect(
      PushNotificationService.locationForPush({'order_id': orderId}),
      '/orders/$orderId',
    );
    expect(PushNotificationService.locationForPush({}), '/notifications');
    expect(
      PushNotificationService.locationForPush({'order_id': '../admin'}),
      '/notifications',
    );
  });

  test('a push tapped before the app is ready is opened once it is', () {
    final opened = <String>[];
    PushNotificationService.openPushData({'order_id': orderId});
    PushNotificationService.openLocation = opened.add;
    expect(opened, ['/orders/$orderId']);
    PushNotificationService.openPushData({'status': 'shipped'});
    expect(opened, ['/orders/$orderId', '/notifications']);
  });

  testWidgets('a cold start waits for splash, then opens the order on top of '
      'the shop', (tester) async {
    final router = GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(path: '/splash', builder: (_, _) => const Text('Splash')),
        GoRoute(path: '/', builder: (_, _) => const Text('Shop')),
        GoRoute(
          path: '/orders/:id',
          builder: (_, state) => Text('Order ${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    openFromNotification(router, '/orders/$orderId');
    await tester.pumpAndSettle();
    expect(find.text('Splash'), findsOneWidget);
    router.go('/');
    await tester.pumpAndSettle();
    expect(find.text('Order $orderId'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Shop'), findsOneWidget);
  });
}
