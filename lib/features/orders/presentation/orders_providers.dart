import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/order.dart';
import '../data/order_repository.dart';

final orderRepositoryProvider = Provider<OrderRepository>((ref) => OrderRepository());

final myOrdersProvider = FutureProvider<List<Order>>((ref) {
  return ref.watch(orderRepositoryProvider).fetchMyOrders();
});

final adminOrderStatusFilterProvider = StateProvider<OrderStatus?>((ref) => null);

final adminOrdersProvider = FutureProvider<List<Order>>((ref) {
  final status = ref.watch(adminOrderStatusFilterProvider);
  return ref.watch(orderRepositoryProvider).fetchAllOrders(status: status);
});

/// Fallback fetch for `/orders/:id` when the [Order] wasn't already passed
/// via router `extra` (e.g. a deep link).
final orderByIdProvider = FutureProvider.family<Order?, String>((ref, id) {
  return ref.watch(orderRepositoryProvider).fetchOrderById(id);
});
