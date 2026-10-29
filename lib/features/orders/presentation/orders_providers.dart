import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/order.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/providers/paged_notifier.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/order_repository.dart';
import '../../admin/delivery/delivery_repository.dart';
import '../../admin/delivery/easyparcel_providers.dart';

final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => OrderRepository(),
);

/// A read-through carrier refresh, injectable so gestures never depend on a
/// concrete network client in tests. Booking/payment APIs are not used here.
final orderTrackingRefreshProvider = Provider<Future<void> Function(Order)>((
  ref,
) {
  final easyParcel = ref.watch(easyParcelRepositoryProvider);
  return (order) async {
    if (order.hasSampleTracking ||
        const {
          OrderStatus.cancelled,
          OrderStatus.refunded,
          OrderStatus.delivered,
        }.contains(order.status)) {
      return;
    }
    if (order.hasParcelPlan || order.qxpressTrackingNo?.isNotEmpty == true) {
      if (order.trackingProvider == 'easyparcel' || order.hasParcelPlan) {
        await easyParcel.refreshStatus(order.id);
      } else if (order.trackingProvider == 'seventeentrack') {
        await DeliveryRepository().refreshTrackingStatus(order.id);
      }
    }
  };
});

Future<void> refreshCarrierOrders(
  ProviderContainer container,
  List<Order> orders,
) async {
  final refresh = container.read(orderTrackingRefreshProvider);
  Object? failure;
  // Bound simultaneous provider calls; attempt every order even if one fails.
  for (var offset = 0; offset < orders.length; offset += 4) {
    await Future.wait(
      orders.skip(offset).take(4).map((order) async {
        try {
          await refresh(order).timeout(const Duration(seconds: 30));
        } catch (error) {
          failure ??= error;
        }
      }),
    );
  }
  if (failure != null) throw failure!;
}

Future<void> refreshAdminOrdersFromCarrier(ProviderContainer container) async {
  try {
    final orders = await container
        .read(orderRepositoryProvider)
        .fetchFulfillmentOrders();
    await refreshCarrierOrders(container, orders);
  } finally {
    container.invalidate(adminOrdersProvider);
    container.invalidate(fulfillmentOrdersProvider);
    await container.read(adminOrdersPagedProvider.notifier).refresh();
  }
}

Future<void> refreshCustomerOrdersFromCarrier(
  ProviderContainer container,
) async {
  try {
    final orders = await container
        .read(orderRepositoryProvider)
        .fetchMyOrders();
    await refreshCarrierOrders(container, orders);
  } finally {
    container.invalidate(myOrdersProvider);
    await container.read(myOrdersProvider.future);
  }
}

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
      if (o.fulfillmentStatusLabel.toLowerCase().contains(query)) return true;
      return o.items.any(
        (item) => item.productName.toLowerCase().contains(query),
      );
    }).toList();
  });
});

final adminOrderStatusFilterProvider = StateProvider<OrderStatus?>(
  (ref) => null,
);

final adminOrdersProvider = FutureProvider<List<Order>>((ref) {
  final status = ref.watch(adminOrderStatusFilterProvider);
  return ref.watch(orderRepositoryProvider).fetchAllOrders(status: status);
});

/// Never inherits the All-tab status filter: all outstanding deliveries stay visible.
final fulfillmentOrdersProvider = FutureProvider<List<Order>>((ref) {
  return ref.watch(orderRepositoryProvider).fetchFulfillmentOrders();
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
    NotifierProvider<
      AdminOrdersPagedNotifier,
      AsyncValue<PagedListState<Order>>
    >(AdminOrdersPagedNotifier.new);

/// Call this everywhere an admin mutation used to `ref.invalidate
/// (adminOrdersProvider)` — keeps both the legacy unbounded list (still
/// used during search) and the new paged list in sync after a status
/// change/delete, instead of only one of them going stale.
void refreshAdminOrders(WidgetRef ref) {
  ref.invalidate(adminOrdersProvider);
  ref.invalidate(fulfillmentOrdersProvider);
  ref.read(adminOrdersPagedProvider.notifier).refresh();
}

/// Session-scoped authoritative detail; backend RLS remains the access boundary.
final orderByIdProvider = FutureProvider.family<Order?, String>((
  ref,
  id,
) async {
  final userId = ref.watch(currentUserIdProvider);
  final userAsync = ref.watch(currentAppUserProvider);
  if (userId == null) return null;
  final repository = ref.watch(orderRepositoryProvider);
  final userFuture = ref.watch(currentAppUserProvider.future);
  final user = userAsync.isLoading ? await userFuture : userAsync.valueOrNull;
  if (user == null || user.id != userId) return null;
  final order = await repository.fetchOrderById(id);
  if (order == null || order.id != id) return null;
  return user.role.isAdmin || order.userId == userId ? order : null;
});
