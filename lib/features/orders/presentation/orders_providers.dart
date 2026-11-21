import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/order.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/providers/paged_notifier.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../cart/domain/cart_item.dart';
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
    container.invalidate(adminPaymentsSummaryProvider);
    container.invalidate(adminRecentOrdersProvider);
    container.invalidate(adminStuckPendingOrdersProvider);
    container.invalidate(fulfillmentOrdersProvider);
    container.invalidate(orderByIdProvider);
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
    container.invalidate(orderByIdProvider);
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

/// My Orders tabs, the way Shopee and Lazada group a customer's orders.
enum OrderListTab {
  all('All', null),
  toPay('To pay', {OrderStatus.pending}),
  toShip('To ship', {OrderStatus.paid, OrderStatus.packing}),
  toReceive('To receive', {OrderStatus.shipped}),
  completed('Completed', {OrderStatus.delivered});

  const OrderListTab(this.label, this.statuses);
  final String label;
  final Set<OrderStatus>? statuses;

  bool includes(Order order) => statuses?.contains(order.status) ?? true;
}

final myOrdersTabProvider = StateProvider<OrderListTab>(
  (ref) => OrderListTab.all,
);

/// Whether My Orders lists checkouts that were cancelled before payment
/// (see [Order.isCancelledUnpaid]). Off by default; a search always does.
final showCancelledUnpaidOrdersProvider = StateProvider<bool>((ref) => false);

/// [myOrdersProvider] filtered by [myOrdersSearchQueryProvider].
final visibleMyOrdersProvider = Provider<AsyncValue<List<Order>>>((ref) {
  final ordersAsync = ref.watch(myOrdersProvider);
  final query = ref.watch(myOrdersSearchQueryProvider).trim().toLowerCase();
  final showUnpaid = ref.watch(showCancelledUnpaidOrdersProvider);
  final tab = ref.watch(myOrdersTabProvider);

  return ordersAsync.whenData((orders) {
    if (query.isEmpty) {
      return orders
          .where((o) => tab.includes(o) && (showUnpaid || !o.isCancelledUnpaid))
          .toList();
    }
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

/// Every order regardless of the Orders › All status chip. Unbounded, so it
/// is read only by the payments summary and the top-products ranking on a
/// database without their server functions (before migration 0078); no
/// screen watches it directly.
final adminAllOrdersProvider = FutureProvider<List<Order>>((ref) {
  return ref.watch(orderRepositoryProvider).fetchAllOrders();
});

/// Order the Fulfillment tab should surface first — set by "Manage
/// delivery" on an Orders › All card so staff land on the order they were
/// looking at instead of the top of the queue.
final focusFulfillmentOrderProvider = StateProvider<String?>((ref) => null);

/// Asks the Orders hub to switch to a tab (0 All, 1 Fulfillment) the next
/// time it is shown — set by the Home queue counters.
final requestedOrdersTabProvider = StateProvider<int?>((ref) => null);

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
final adminOrderSummaryProvider = FutureProvider<AdminOrderSummary>((ref) {
  return ref.watch(orderRepositoryProvider).fetchAdminOrderSummary();
});

/// The dashboard's "collected through Stripe" card: the server's figures.
/// Until migration 0078 is applied they are added up here from
/// [adminAllOrdersProvider], which is watched only in that case, so a
/// database that has the function never downloads every order for it.
final adminPaymentsSummaryProvider = FutureProvider<AdminPaymentsSummary>((
  ref,
) async {
  final summary = await ref
      .watch(orderRepositoryProvider)
      .fetchAdminPaymentsSummary();
  if (summary != null) return summary;
  final orders = await ref.watch(adminAllOrdersProvider.future);
  return AdminPaymentsSummary.fromOrders(orders);
});

/// How many orders the dashboard's "Recent orders" card shows.
const int kRecentOrdersLimit = 5;

/// The newest orders for the dashboard: one small page, never every order.
final adminRecentOrdersProvider = FutureProvider<List<Order>>((ref) {
  return ref
      .watch(orderRepositoryProvider)
      .fetchAllOrdersPage(offset: 0, limit: kRecentOrdersLimit);
});

/// Orders still `pending` after [kStuckPendingAge], for the dashboard.
final adminStuckPendingOrdersProvider = FutureProvider<StuckPendingOrders>((
  ref,
) {
  return ref
      .watch(orderRepositoryProvider)
      .fetchStuckPendingOrders(
        createdBefore: DateTime.now().subtract(kStuckPendingAge),
      );
});

/// Most rows the Top Products ranking asks for (the function's own cap).
const int kTopProductsLimit = 1000;

/// The one ranking behind both the dashboard's Top Products card and the
/// full screen, so they can never disagree. Ranked on the server; until
/// migration 0078 is applied it is ranked here from
/// [adminAllOrdersProvider], as before.
final adminTopProductsProvider = FutureProvider<List<TopProductSales>>((
  ref,
) async {
  final ranked = await ref
      .watch(orderRepositoryProvider)
      .fetchAdminTopProducts(limit: kTopProductsLimit);
  if (ranked != null) return ranked;
  final orders = await ref.watch(adminAllOrdersProvider.future);
  return rankTopProductSales(orders).take(kTopProductsLimit).toList();
});

void refreshAdminOrders(WidgetRef ref) {
  ref.invalidate(adminOrdersProvider);
  ref.invalidate(adminAllOrdersProvider);
  ref.invalidate(adminOrderSummaryProvider);
  ref.invalidate(adminPaymentsSummaryProvider);
  ref.invalidate(adminTopProductsProvider);
  ref.invalidate(adminRecentOrdersProvider);
  ref.invalidate(adminStuckPendingOrdersProvider);
  ref.invalidate(fulfillmentOrdersProvider);
  // Every open order detail (the whole family): a status change made from a
  // list card must not leave the detail screen showing the old status.
  ref.invalidate(orderByIdProvider);
  ref.read(adminOrdersPagedProvider.notifier).refresh();
}

/// "The payment sheet just reported success for this order, but the server
/// has not recorded it yet" — set by checkout / Complete payment, read by the
/// order screen, which shows a confirming state and keeps re-checking (see
/// `_PaymentConfirmationPoller`). It is a display hint only: nothing here
/// marks an order paid, the order's status still comes from the server.
///
/// Held in memory so a deep link or a restart can never claim a payment was
/// received, and dropped when the signed-in account changes.
class PaymentAwaitingConfirmation {
  final String orderId;
  final String ownerId;

  /// The cart lines this payment bought — removed from the cart once the
  /// server confirms. Empty for Buy Now, which never used the cart.
  final List<CartItem> cartLines;

  const PaymentAwaitingConfirmation({
    required this.orderId,
    required this.ownerId,
    this.cartLines = const [],
  });
}

final paymentAwaitingConfirmationProvider =
    StateProvider<PaymentAwaitingConfirmation?>((ref) {
      ref.watch(currentUserIdProvider);
      return null;
    });

/// Session-scoped authoritative detail; backend RLS remains the access boundary.
///
/// Auto-disposed so every visit to an order (including one opened from a
/// push notification about a status change) fetches its current state rather
/// than whatever was cached the first time it was opened this session.
final orderByIdProvider = FutureProvider.autoDispose.family<Order?, String>((
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
