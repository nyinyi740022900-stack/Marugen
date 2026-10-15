import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/shared/models/order.dart';

final identity = StateProvider<String?>((ref) => 'first');
final role = StateProvider<UserRole>((ref) => UserRole.customer);

class DetailRepository implements OrderRepository {
  @override
  Future<Order?> fetchOrderById(String id) async => Order(
    id: id,
    userId: id == 'retained' ? null : 'first',
    status: OrderStatus.shipped,
    total: 20,
    createdAt: DateTime(2026),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer session() => ProviderContainer(
  overrides: [
    authStateProvider.overrideWith((ref) => const Stream.empty()),
    currentUserIdProvider.overrideWith((ref) => ref.watch(identity)),
    currentAppUserProvider.overrideWith((ref) async {
      final id = ref.watch(identity);
      final activeRole = ref.watch(role);
      return id == null ? null : AppUser(id: id, role: activeRole);
    }),
    orderRepositoryProvider.overrideWithValue(DetailRepository()),
  ],
);
void main() {
  test(
    'order detail is refetched and hidden when active identity changes',
    () async {
      final container = session();
      addTearDown(container.dispose);
      final subscription = container.listen(
        orderByIdProvider('order-12345'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      expect(
        await container.read(orderByIdProvider('order-12345').future),
        isNotNull,
      );
      container.read(identity.notifier).state = 'second';
      expect(
        await container.read(orderByIdProvider('order-12345').future),
        isNull,
      );
      container.read(identity.notifier).state = null;
      expect(
        await container.read(orderByIdProvider('order-12345').future),
        isNull,
      );
    },
  );
  test('retained admin detail disappears when role becomes customer', () async {
    final container = session();
    addTearDown(container.dispose);
    container.read(role.notifier).state = UserRole.owner;
    final subscription = container.listen(
      orderByIdProvider('retained'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    expect(
      await container.read(orderByIdProvider('retained').future),
      isNotNull,
    );
    container.read(role.notifier).state = UserRole.customer;
    expect(await container.read(orderByIdProvider('retained').future), isNull);
  });
}
