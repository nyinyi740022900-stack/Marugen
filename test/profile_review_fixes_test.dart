// Page review 22 Nov 2026, profile: the notifications switch follows the
// phone's permission, and deleting an account with an order in progress is
// warned about but never refused. Plus the terms and FAQ copy.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marugen_app/core/notifications/push_permission_controller.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/data/auth_repository.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/auth/presentation/profile_screen.dart';
import 'package:marugen_app/features/legal/terms_screen.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/support/faq_screen.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:marugen_app/shared/utils/error_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;

class _Auth implements AuthRepository {
  final notificationWrites = <bool>[];
  int deletions = 0;
  Object? deleteError;

  @override
  Future<void> updateNotificationsEnabled(bool enabled) async =>
      notificationWrites.add(enabled);

  @override
  Future<void> deleteAccount() async {
    deletions++;
    if (deleteError != null) throw deleteError!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Phone implements PushPermissionController {
  _Phone(this.permission, {this.afterRequest, this.canOpenSettings = true});
  PushPermission permission;

  /// What the OS answers when asked; null leaves [permission] as it is.
  final PushPermission? afterRequest;
  int requests = 0;
  int settingsOpened = 0;

  @override
  final bool canOpenSettings;

  @override
  Future<PushPermission> current() async => permission;

  @override
  Future<PushPermission> request() async {
    requests++;
    return permission = afterRequest ?? permission;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

class _Orders implements OrderRepository {
  _Orders(this.orders, {this.fails = false});
  final List<Order> orders;
  final bool fails;

  final askedFor = <String>[];

  /// What the server's bounded query answers: the newest order that is
  /// paid, packing or shipped.
  @override
  Future<OrderInProgress?> fetchNewestOrderInProgress(String userId) async {
    askedFor.add(userId);
    if (fails) throw Exception('offline');
    for (final order in orders) {
      if (OrderInProgress.statuses.contains(order.status)) {
        return OrderInProgress(
          id: order.id,
          orderNumber: order.orderNumber,
          status: order.status,
        );
      }
    }
    return null;
  }

  // The whole order history is never downloaded for this.
  @override
  Future<List<Order>> fetchMyOrders() async =>
      throw StateError('fetchMyOrders must not be used to delete an account');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Order _order(OrderStatus status, String number) => Order(
  id: 'order-$number',
  userId: 'customer',
  orderNumber: number,
  status: status,
  total: 20,
  createdAt: DateTime(2026, 11, 1),
);

Future<void> _showProfile(
  WidgetTester tester, {
  required _Auth auth,
  required _Phone phone,
  bool accountEnabled = true,
  _Orders? orders,
}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isLoggedInProvider.overrideWithValue(true),
        currentUserIdProvider.overrideWithValue('customer'),
        currentAppUserProvider.overrideWith(
          (ref) async => AppUser(
            id: 'customer',
            email: 'alex@example.com',
            notificationsEnabled: accountEnabled,
          ),
        ),
        authRepositoryProvider.overrideWithValue(auth),
        pushPermissionControllerProvider.overrideWithValue(phone),
        orderRepositoryProvider.overrideWithValue(orders ?? _Orders(const [])),
        shopSettingsProvider.overrideWith(
          (ref) async => {'shop_phone': '+65 9123 4567'},
        ),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

SwitchListTile _switch(WidgetTester tester) =>
    tester.widget<SwitchListTile>(find.byType(SwitchListTile));

void main() {
  group('notifications switch', () {
    testWidgets('permission never granted: off, and says so, whatever the '
        'account setting', (tester) async {
      final auth = _Auth();
      await _showProfile(
        tester,
        auth: auth,
        phone: _Phone(PushPermission.canAsk),
      );
      expect(_switch(tester).value, isFalse);
      expect(find.text('Notifications are off on this phone'), findsOneWidget);
      expect(find.text('Push alerts for order updates are on'), findsNothing);
    });

    testWidgets('allowed on the phone and on in the account: on', (
      tester,
    ) async {
      await _showProfile(
        tester,
        auth: _Auth(),
        phone: _Phone(PushPermission.authorized),
      );
      expect(_switch(tester).value, isTrue);
      expect(find.text('Push alerts for order updates are on'), findsOneWidget);
    });

    testWidgets('a build without push keeps showing the account setting', (
      tester,
    ) async {
      await _showProfile(
        tester,
        auth: _Auth(),
        phone: _Phone(PushPermission.unknown),
      );
      expect(_switch(tester).value, isTrue);
      expect(find.text('Notifications are off on this phone'), findsNothing);
    });

    testWidgets('turning it on asks the phone, and a yes turns it on', (
      tester,
    ) async {
      final auth = _Auth();
      final phone = _Phone(
        PushPermission.canAsk,
        afterRequest: PushPermission.authorized,
      );
      await _showProfile(tester, auth: auth, phone: phone);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(phone.requests, 1);
      expect(_switch(tester).value, isTrue);
      expect(auth.notificationWrites, [true]);
      expect(find.text('Push alerts for order updates are on'), findsOneWidget);
    });

    testWidgets('a no leaves it off and points at Settings', (tester) async {
      final auth = _Auth();
      final phone = _Phone(
        PushPermission.canAsk,
        afterRequest: PushPermission.blocked,
      );
      await _showProfile(tester, auth: auth, phone: phone);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(_switch(tester).value, isFalse);
      expect(auth.notificationWrites, isEmpty);
      expect(
        find.text('Turn on notifications for Marugen in Settings'),
        findsOneWidget,
      );
      expect(find.text('Open Settings'), findsOneWidget);
    });

    testWidgets('already denied on iOS: no second prompt, Settings instead', (
      tester,
    ) async {
      final auth = _Auth();
      final phone = _Phone(PushPermission.blocked);
      await _showProfile(tester, auth: auth, phone: phone);
      expect(_switch(tester).value, isFalse);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(phone.requests, 0);
      expect(
        find.text('Turn on notifications for Marugen in Settings'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      expect(phone.settingsOpened, 1);
      expect(auth.notificationWrites, isEmpty);
    });

    testWidgets('no Open Settings action where the app cannot open them', (
      tester,
    ) async {
      final phone = _Phone(PushPermission.blocked, canOpenSettings: false);
      await _showProfile(tester, auth: _Auth(), phone: phone);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(
        find.text('Turn on notifications for Marugen in Settings'),
        findsOneWidget,
      );
      expect(find.text('Open Settings'), findsNothing);
    });

    testWidgets('coming back from Settings re-reads the phone', (tester) async {
      final phone = _Phone(PushPermission.blocked);
      await _showProfile(tester, auth: _Auth(), phone: phone);
      expect(_switch(tester).value, isFalse);

      phone.permission = PushPermission.authorized;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(_switch(tester).value, isTrue);
    });

    testWidgets('turning it off still only writes the account setting', (
      tester,
    ) async {
      final auth = _Auth();
      final phone = _Phone(PushPermission.authorized);
      await _showProfile(tester, auth: auth, phone: phone);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(auth.notificationWrites, [false]);
      expect(phone.requests, 0);
      expect(_switch(tester).value, isFalse);
      expect(
        find.text('Push alerts are off — order status still shows in-app'),
        findsOneWidget,
      );
    });
  });

  group('deleting the account', () {
    const warning =
        'Order #1234 is still on its way. If you delete your account now '
        "you won't be able to track it or request a cancellation in the "
        'app. The order itself is not cancelled.';

    for (final status in [
      OrderStatus.paid,
      OrderStatus.packing,
      OrderStatus.shipped,
    ]) {
      testWidgets('an order that is ${status.name} warns, and Keep my account '
          'deletes nothing', (tester) async {
        final auth = _Auth();
        final orders = _Orders([
          _order(OrderStatus.delivered, '1111'),
          _order(status, '1234'),
        ]);
        await _showProfile(
          tester,
          auth: auth,
          phone: _Phone(PushPermission.authorized),
          orders: orders,
        );
        await tester.tap(find.text('Delete My Account'));
        await tester.pumpAndSettle();

        expect(orders.askedFor, ['customer']);
        expect(find.text('You have an order in progress'), findsOneWidget);
        expect(find.text(warning), findsOneWidget);
        expect(find.text('Keep my account'), findsOneWidget);
        expect(find.text('Contact support'), findsOneWidget);
        expect(find.text('Delete anyway'), findsOneWidget);
        expect(find.text('Delete your account?'), findsNothing);

        await tester.tap(find.text('Keep my account'));
        await tester.pumpAndSettle();
        expect(find.text('Delete your account?'), findsNothing);
        expect(auth.deletions, 0);
      });
    }

    testWidgets('Delete anyway goes on to the usual confirmation, and only '
        'that deletes', (tester) async {
      final auth = _Auth();
      await _showProfile(
        tester,
        auth: auth,
        phone: _Phone(PushPermission.authorized),
        orders: _Orders([_order(OrderStatus.shipped, '1234')]),
      );
      await tester.tap(find.text('Delete My Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete anyway'));
      await tester.pumpAndSettle();

      // Confirmed once more before anything is deleted.
      expect(find.text(warning), findsNothing);
      expect(find.text('Delete your account?'), findsOneWidget);
      expect(auth.deletions, 0);

      await tester.tap(find.text('Delete Account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(auth.deletions, 1);
    });

    testWidgets('Delete anyway, then Cancel, deletes nothing', (tester) async {
      final auth = _Auth();
      await _showProfile(
        tester,
        auth: auth,
        phone: _Phone(PushPermission.authorized),
        orders: _Orders([_order(OrderStatus.paid, '1234')]),
      );
      await tester.tap(find.text('Delete My Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete anyway'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(auth.deletions, 0);
    });

    testWidgets('an unpaid pending order is an abandoned checkout: no '
        'warning at all', (tester) async {
      final auth = _Auth();
      await _showProfile(
        tester,
        auth: auth,
        phone: _Phone(PushPermission.authorized),
        orders: _Orders([_order(OrderStatus.pending, '1234')]),
      );
      await tester.tap(find.text('Delete My Account'));
      await tester.pumpAndSettle();
      expect(find.text('You have an order in progress'), findsNothing);
      expect(find.text('Delete your account?'), findsOneWidget);
    });

    testWidgets('Contact support opens the contact picker', (tester) async {
      final auth = _Auth();
      await _showProfile(
        tester,
        auth: auth,
        phone: _Phone(PushPermission.authorized),
        orders: _Orders([_order(OrderStatus.paid, '1234')]),
      );
      await tester.tap(find.text('Delete My Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contact support'));
      await tester.pumpAndSettle();
      expect(find.text('Contact Support'), findsOneWidget);
      expect(find.text('Delete your account?'), findsNothing);
      expect(auth.deletions, 0);
    });

    testWidgets('only finished orders: the ordinary confirmation, then '
        'deletion', (tester) async {
      final auth = _Auth();
      await _showProfile(
        tester,
        auth: auth,
        phone: _Phone(PushPermission.authorized),
        orders: _Orders([
          _order(OrderStatus.delivered, '1111'),
          _order(OrderStatus.cancelled, '2222'),
          _order(OrderStatus.refunded, '3333'),
        ]),
      );
      await tester.tap(find.text('Delete My Account'));
      await tester.pumpAndSettle();
      expect(find.text('Delete your account?'), findsOneWidget);
      expect(find.textContaining('order in progress'), findsNothing);
      await tester.tap(find.text('Delete Account'));
      // The spinner keeps running until the router takes over.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(auth.deletions, 1);
    });

    testWidgets('orders that cannot be checked do not block deletion', (
      tester,
    ) async {
      final auth = _Auth();
      await _showProfile(
        tester,
        auth: auth,
        phone: _Phone(PushPermission.authorized),
        orders: _Orders(const [], fails: true),
      );
      await tester.tap(find.text('Delete My Account'));
      await tester.pumpAndSettle();
      expect(find.text('Delete your account?'), findsOneWidget);
    });

    testWidgets('a refused deletion shows what the server said', (
      tester,
    ) async {
      const reason = 'Your account has an unpaid balance. Contact support.';
      final auth = _Auth()..deleteError = const ServerMessageException(reason, status: 409);
      await _showProfile(
        tester,
        auth: auth,
        phone: _Phone(PushPermission.authorized),
      );
      await tester.tap(find.text('Delete My Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      expect(auth.deletions, 1);
      expect(find.text(reason), findsOneWidget);
    });

    testWidgets('an unexpected failure keeps the plain fallback, never raw '
        'text', (tester) async {
      final auth = _Auth()..deleteError = StateError('boom at line 42');
      await _showProfile(
        tester,
        auth: auth,
        phone: _Phone(PushPermission.authorized),
      );
      await tester.tap(find.text('Delete My Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Your account was not deleted. Check your connection and try '
          'again, or contact support.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('boom'), findsNothing);
    });
  });

  test('the in-progress check asks the server for one row, three columns, '
      'three statuses', () async {
    final requests = <http.Request>[];
    var rows = <Map<String, dynamic>>[
      {'id': 'order-abcdef12', 'order_number': '1234', 'status': 'packing'},
    ];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(rows),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    final repo = OrderRepository(client: client);

    final found = await repo.fetchNewestOrderInProgress('customer');
    expect(found!.id, 'order-abcdef12');
    expect(found.displayNumber, '1234');
    expect(found.status, OrderStatus.packing);

    final query = requests.single.url.queryParameters;
    expect(requests.single.url.path, '/rest/v1/orders');
    expect(query['select'], 'id,order_number,status');
    expect(query['user_id'], 'eq.customer');
    // Paid for and still on its way: never an unpaid pending order.
    expect(query['status'], 'in.("paid","packing","shipped")');
    expect(query['order'], startsWith('created_at.desc'));
    expect(query['limit'], '1');

    rows = [];
    expect(await repo.fetchNewestOrderInProgress('customer'), isNull);
    // A row outside the three statuses is not reported either.
    rows = [
      {'id': 'order-abcdef12', 'order_number': '1234', 'status': 'pending'},
    ];
    expect(await repo.fetchNewestOrderInProgress('customer'), isNull);
    // Without an order number the id stands in, as on the order page.
    expect(
      const OrderInProgress(id: 'abcdef1234', status: OrderStatus.paid)
          .displayNumber,
      'ABCDEF12',
    );
  });

  group('terms and FAQ copy', () {
    Future<void> showPage(WidgetTester tester, Widget page) async {
      tester.view.physicalSize = const Size(390, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(theme: AppTheme.light, home: page),
        ),
      );
      await tester.pumpAndSettle();
    }

    String body(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');

    testWidgets('terms describe the cancellation the app really offers', (
      tester,
    ) async {
      await showPage(tester, const TermsScreen());
      final text = body(tester);

      // The promise the app does not keep is gone.
      expect(text, isNot(contains('before they enter packing')));
      expect(text, contains('6. Cancellations & Refunds'));
      expect(
        text,
        contains(
          'An order that has not been paid for can be cancelled by the '
          'customer',
        ),
      );
      expect(text, contains('the shop reviews each request'));
      expect(
        text,
        contains('does not by itself cancel the order or issue a refund'),
      );
      expect(text, contains('made to the original payment method'));
    });

    testWidgets('terms have the live-fish clause and a contact route that '
        'exists', (tester) async {
      await showPage(tester, const TermsScreen());
      final text = body(tester);
      expect(text, contains('Live Fish'));
      expect(text, contains('within 24 hours of delivery'));
      expect(text, contains('arrives unwell'));
      expect(text, contains('Profile › FAQ & Support › Contact Support'));
      expect(text, isNot(contains('"Contact us" option')));
      // Sections stay numbered in order after the insertion.
      for (var i = 1; i <= 11; i++) {
        expect('\n$text', contains('\n$i. '), reason: 'section $i');
      }
    });

    testWidgets('FAQ answers the live-fish question and no longer says the '
        'button messages on WhatsApp', (tester) async {
      await showPage(tester, const FaqScreen());
      expect(find.text('What if a live fish arrives unwell?'), findsOneWidget);
      await tester.tap(find.text('What if a live fish arrives unwell?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('within 24 hours of delivery'), findsOneWidget);

      await tester.tap(
        find.textContaining('A product says "Contact us for price"'),
      );
      await tester.pumpAndSettle();
      final text = body(tester);
      expect(text, isNot(contains('message us on WhatsApp')));
      expect(text, contains('choose who to contact'));
    });
  });
}
