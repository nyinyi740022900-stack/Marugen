import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/order.dart';
import '../../../shared/providers/paged_notifier.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/order_repository.dart';

final orderRepositoryProvider = Provider<OrderRepository>((ref) => OrderRepository());

/// Watches [authStateProvider] (same pattern as [currentAppUserProvider]) so
/// this re-fetches once sign-in/session-restore actually completes. Without
/// it, this FutureProvider reads `SupabaseService.currentUser` once at
/// whatever instant Riverpod first builds the Orders tab — which happens
/// immediately on app start inside CustomerShell's IndexedStack, often
/// before the session has finished restoring — and permanently caches an
/// empty list for the rest of the session since nothing else invalidates it.
final myOrdersProvider = FutureProvider<List<Order>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(orderRepositoryProvider).fetchMyOrders();
});

/// Free-text query for the customer Orders screen's search bar — matches
/// order number, status label, or any item's product name.
final myOrdersSearchQueryProvider = StateProvider<String>((ref) => '');

/// [myOrdersProvider] filtered by [myOrdersSearchQueryProvider].
final visibleMyOrdersProvider = Provider<AsyncValue<List<Order>>>((ref) {
  final ordersAsync = ref.watch(myOrdersProvider);
  final query = ref.watch(myOrdersSearchQueryProvider).trim().toLowerCase();

  return ordersAsync.whenData((orders) {
    if (query.isEmpty) return orders;
    return orders.where((o) {
      if (o.displayNumber.toLowerCase().contains(query)) return true;
      if (orderStatusLabel(o.status).toLowerCase().contains(query)) return true;
      return o.items.any((item) => item.productName.toLowerCase().contains(query));
    }).toList();
  });
});

final adminOrderStatusFilterProvider = StateProvider<OrderStatus?>((ref) => null);

final adminOrdersProvider = FutureProvider<List<Order>>((ref) {
  final status = ref.watch(adminOrderStatusFilterProvider);
  return ref.watch(orderRepositoryProvider).fetchAllOrders(status: status);
});

/// Paged (infinite-scroll) admin order list — the default no-search view.
/// `build()` watches [adminOrderStatusFilterProvider] so switching the
/// status filter tab tears this down and restarts pagination from page 0
/// automatically, the same way changing any other Riverpod dependency
/// does. See PagedNotifier for why this exists alongside the still-used
/// unbounded [adminOrdersProvider] (kept as the fallback whenever a
/// search query is active).
class AdminOrdersPagedNotifier extends PagedNotifier<Order> {
  @override
  Future<List<Order>> fetchPage(int offset, int limit) {
    final status = ref.watch(adminOrderStatusFilterProvider);
    return ref
        .read(orderRepositoryProvider)
        .fetchAllOrdersPage(status: status, offset: offset, limit: limit);
  }
}

final adminOrdersPagedProvider =
    NotifierProvider<AdminOrdersPagedNotifier, AsyncValue<PagedListState<Order>>>(
        AdminOrdersPagedNotifier.new);

/// Call this everywhere an admin mutation used to `ref.invalidate
/// (adminOrdersProvider)` — keeps both the legacy unbounded list (still
/// used during search) and the new paged list in sync after a status
/// change/delete, instead of only one of them going stale.
void refreshAdminOrders(WidgetRef ref) {
  ref.invalidate(adminOrdersProvider);
  ref.read(adminOrdersPagedProvider.notifier).refresh();
}

/// Fallback fetch for `/orders/:id` when the [Order] wasn't already passed
/// via router `extra` (e.g. a deep link).
final orderByIdProvider = FutureProvider.family<Order?, String>((ref, id) {
  return ref.watch(orderRepositoryProvider).fetchOrderById(id);
});
