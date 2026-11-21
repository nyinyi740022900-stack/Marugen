import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/shared/models/order.dart';

/// The server's copy of the order: the test changes [status] the way an
/// admin action or a webhook would.
class LiveOrders implements OrderRepository {
  OrderStatus status = OrderStatus.paid;
  int detailFetches = 0;

  @override
  Future<Order?> fetchOrderById(String id) async {
    detailFetches++;
    return Order(
      id: id,
      userId: 'customer',
      status: status,
      total: 20,
      createdAt: DateTime(2026, 11, 1),
    );
  }

  @override
  Future<List<Order>> fetchAllOrdersPage({
    OrderStatus? status,
    required int offset,
    required int limit,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> session(LiveOrders orders, {UserRole role = UserRole.customer}) =>
    [
      authStateProvider.overrideWith((ref) => const Stream.empty()),
      currentUserIdProvider.overrideWithValue('viewer'),
      currentAppUserProvider.overrideWith(
        (ref) async => AppUser(id: 'viewer', role: role),
      ),
      orderRepositoryProvider.overrideWithValue(orders),
    ];

void main() {
  test('reopening an order fetches it again instead of reusing the first '
      'visit', () async {
    final orders = LiveOrders();
    final container = ProviderContainer(
      overrides: session(orders, role: UserRole.owner),
    );
    addTearDown(container.dispose);

    // First visit to the order screen.
    final firstVisit = container.listen(orderByIdProvider('o1'), (_, _) {});
    expect(
      (await container.read(orderByIdProvider('o1').future))?.status,
      OrderStatus.paid,
    );
    firstVisit.close();
    await Future<void>.delayed(Duration.zero);

    // Staff ship it; the customer taps the "shipped" push.
    orders.status = OrderStatus.shipped;
    final fetchedBefore = orders.detailFetches;
    final secondVisit = container.listen(orderByIdProvider('o1'), (_, _) {});
    addTearDown(secondVisit.close);
    expect(
      (await container.read(orderByIdProvider('o1').future))?.status,
      OrderStatus.shipped,
    );
    expect(orders.detailFetches, greaterThan(fetchedBefore));
  });

  testWidgets('an admin status change refreshes an order detail that is '
      'already open', (tester) async {
    final orders = LiveOrders();
    await tester.pumpWidget(
      ProviderScope(
        overrides: session(orders, role: UserRole.owner),
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              final order = ref.watch(orderByIdProvider('o1')).valueOrNull;
              return Column(
                children: [
                  Text('status ${order?.status.name}'),
                  TextButton(
                    onPressed: () => refreshAdminOrders(ref),
                    child: const Text('after status change'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('status paid'), findsOneWidget);

    orders.status = OrderStatus.packing;
    await tester.tap(find.text('after status change'));
    await tester.pumpAndSettle();
    expect(find.text('status packing'), findsOneWidget);
  });
}
