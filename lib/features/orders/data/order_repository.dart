import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/order.dart';
import '../../../shared/utils/error_message.dart';

class CancellationRefundNeedsAttention implements Exception {
  const CancellationRefundNeedsAttention();
}

class OrderRepository {
  final SupabaseClient _client;
  OrderRepository({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  /// Dashboard totals counted on the server (`admin_order_summary`,
  /// migration 0074): every order, whatever the Orders tab filter shows.
  Future<AdminOrderSummary> fetchAdminOrderSummary() async {
    final rows = await _client.rpc('admin_order_summary') as List;
    final row = rows.single as Map<String, dynamic>;
    return AdminOrderSummary(
      openOrders: (row['open_orders'] as num).toInt(),
      totalRevenue: (row['total_revenue'] as num).toDouble(),
      weekRevenue: (row['week_revenue'] as num).toDouble(),
    );
  }

  /// Payments pane headline (`admin_payments_summary`, migration 0078).
  /// Null when the database does not have the function yet, so the caller
  /// can fall back to adding up the orders it already loaded.
  Future<AdminPaymentsSummary?> fetchAdminPaymentsSummary() async {
    final dynamic result;
    try {
      result = await _client.rpc('admin_payments_summary');
    } catch (error) {
      if (isMissingRpc(error)) return null;
      rethrow;
    }
    final row = (result is List ? result.single : result) as Map;
    return AdminPaymentsSummary(
      transactionCount: (row['transaction_count'] as num).toInt(),
      collected: (row['collected'] as num).toDouble(),
    );
  }

  /// Product sales ranking (`admin_top_products`, migration 0078), most
  /// units first. Null when the database does not have the function yet.
  Future<List<TopProductSales>?> fetchAdminTopProducts({
    required int limit,
  }) async {
    final dynamic result;
    try {
      result = await _client.rpc(
        'admin_top_products',
        params: {'p_limit': limit},
      );
    } catch (error) {
      if (isMissingRpc(error)) return null;
      rethrow;
    }
    return (result as List)
        .map((row) => TopProductSales.fromMap((row as Map).cast()))
        .toList();
  }

  Future<List<Order>> fetchMyOrders() async {
    final user = SupabaseService.currentUser;
    if (user == null) return [];
    final data = await _client
        .from('orders')
        .select(
          '*, items:order_items(*), parcels:order_parcels(*), order_cancellation_requests(*)',
        )
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => Order.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Admin: a specific customer's full order history — for the "view
  /// customer" screen. Works under the existing "Admins can view all
  /// orders" RLS policy (0001_init.sql), no new migration needed.
  Future<List<Order>> fetchOrdersForUser(String userId) async {
    final data = await _client
        .from('orders')
        .select(
          '*, items:order_items(*), parcels:order_parcels(*), order_cancellation_requests(*)',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => Order.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Admin: all orders, optionally filtered by status. Unbounded — kept
  /// as the fallback path for when a search query is active (see
  /// [fetchAllOrdersPage] for the normal paged path); admin order counts
  /// aren't yet large enough for full-table search to be a real problem,
  /// only for scrolling the default unfiltered list to be.
  Future<List<Order>> fetchAllOrders({OrderStatus? status}) async {
    var query = _client
        .from('orders')
        .select(
          '*, items:order_items(*), parcels:order_parcels(*), order_cancellation_requests(*)',
        );
    if (status != null) {
      query = query.eq('status', status.name);
    }
    final data = await query.order('created_at', ascending: false);
    return (data as List)
        .map((e) => Order.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Outstanding deliveries have their own query, independent of browse filters.
  Future<List<Order>> fetchFulfillmentOrders() async {
    const pageSize = 200;
    final orders = <Order>[];
    for (var offset = 0; ; offset += pageSize) {
      final data = await _client
          .from('orders')
          .select(
            '*, items:order_items(*), parcels:order_parcels(*), order_cancellation_requests(*)',
          )
          .inFilter('status', ['paid', 'packing', 'shipped'])
          .order('created_at')
          .order('id')
          .range(offset, offset + pageSize - 1);
      orders.addAll(data.map(Order.fromMap));
      if (data.length < pageSize) return orders;
    }
  }

  /// Admin: one page of orders (`[offset, offset+limit)`), optionally
  /// filtered by status — see PagedNotifier (shared/providers/
  /// paged_notifier.dart). Same stable `created_at desc` order as
  /// [fetchAllOrders] so pages don't overlap/skip.
  Future<List<Order>> fetchAllOrdersPage({
    OrderStatus? status,
    required int offset,
    required int limit,
  }) async {
    var query = _client
        .from('orders')
        .select(
          '*, items:order_items(*), parcels:order_parcels(*), order_cancellation_requests(*)',
        );
    if (status != null) {
      query = query.eq('status', status.name);
    }
    final data = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List)
        .map((e) => Order.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> confirmShopDelivery(String orderId) async {
    final confirmed = await _client.rpc(
      'confirm_shop_delivery',
      params: {'order_id': orderId},
    );
    if (confirmed != true) {
      throw StateError(
        'Order changed. Refresh before confirming shop delivery.',
      );
    }
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    if (status == OrderStatus.cancelled) {
      await cancelMyOrder(orderId);
      return;
    }
    await _client
        .from('orders')
        .update({'status': status.name})
        .eq('id', orderId);
    _notifyStatus(orderId, status);
  }

  /// Best-effort push notification to the customer (see
  /// send-order-notification for the full explanation) — fire-and-forget
  /// so a notification hiccup never blocks or fails the admin's status
  /// update, which already succeeded above by the time this runs. Only
  /// customer-meaningful transitions are worth a push; refunded is
  /// internal/rare enough to skip (the function itself would also just
  /// skip an unrecognised status, this just avoids the network call).
  void _notifyStatus(String orderId, OrderStatus status) {
    const notifiable = {
      OrderStatus.paid,
      OrderStatus.packing,
      OrderStatus.shipped,
      OrderStatus.delivered,
      OrderStatus.cancelled,
    };
    if (!notifiable.contains(status)) return;
    unawaited(_invokeNotify(orderId, status));
  }

  Future<void> _invokeNotify(String orderId, OrderStatus status) async {
    try {
      await _client.functions.invoke(
        'send-order-notification',
        body: {'order_id': orderId, 'status': status.name},
      );
    } catch (_) {
      // Best-effort — see _notifyStatus doc above.
    }
  }

  /// Admin-only refund request/status refresh. Only the backend may mark
  /// the order refunded, after Stripe confirms that the refund succeeded.
  Future<void> refundOrder(
    String orderId, {
    String? reason,
    bool refreshOnly = false,
  }) async {
    try {
      await _client.functions.invoke(
        'stripe-refund',
        body: {
          'order_id': orderId,
          'reason': ?reason,
          'refresh_only': refreshOnly,
        },
      );
    } on FunctionException catch (e) {
      // invoke() throws on every non-2xx response; the function's `error`
      // field is fixed copy written for staff.
      throw ServerMessageException.fromFunction(
        e,
        fallback: 'Could not process the refund. Check Stripe and try again.',
      );
    }
  }

  /// The backend owns eligibility, fulfillment holds and Stripe verification.
  Future<void> manageCancellation(
    String orderId,
    String action, {
    String? reason,
  }) async {
    final FunctionResponse response;
    try {
      response = await _client.functions
          .invoke(
            'order-cancellation',
            body: {'order_id': orderId, 'action': action, 'reason': ?reason},
          )
          .timeout(const Duration(seconds: 45));
    } on FunctionException catch (e) {
      throw ServerMessageException.fromFunction(
        e,
        fallback:
            'Cancellation could not be confirmed. Refresh the order or contact support.',
      );
    }
    final data = response.data;
    final request = data is Map ? data['request'] : null;
    final expected = switch (action) {
      'request' => const {'requested', 'approved'},
      'reject' => const {'rejected'},
      _ => const {'approved'},
    };
    if (request is! Map ||
        request['order_id'] != orderId ||
        !expected.contains(request['status'])) {
      throw StateError(
        'The cancellation decision was not confirmed. Refresh the order.',
      );
    }
    if (data is Map && data['refund_error'] != null) {
      throw const CancellationRefundNeedsAttention();
    }
  }

  /// Customer/admin cancellation is verified by the payment backend before
  /// pending stock can be released. Paid orders require the refund endpoint.
  Future<void> cancelMyOrder(String orderId) async {
    try {
      await _client.functions.invoke('cancel-order', body: {'order_id': orderId});
    } on FunctionException catch (e) {
      throw ServerMessageException.fromFunction(
        e,
        fallback:
            'Cancellation was not confirmed. Refresh the order or contact the shop.',
      );
    }
  }

  /// Fetches a single order by id (RLS restricts this to the owning user,
  /// or admins). Used as a fallback when an order's data wasn't already
  /// passed in via router `extra` (e.g. a deep link into `/orders/:id`).
  Future<Order?> fetchOrderById(String id) async {
    final data = await _client
        .from('orders')
        .select(
          '*, items:order_items(*), parcels:order_parcels(*), order_cancellation_requests(*), status_history:order_status_history(to_status,changed_at)',
        )
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return Order.fromMap(data);
  }
}

/// True when PostgREST could not find the function that was called: the
/// migration that adds it has not been applied to this database yet.
/// Anything else (permission, network, a failing function) is a real error.
bool isMissingRpc(Object error) =>
    error is PostgrestException &&
    const {'PGRST202', '42883', '404'}.contains(error.code);

/// Payments made through Stripe: how many orders, and what was collected
/// from them after refunds.
class AdminPaymentsSummary {
  final int transactionCount;
  final double collected;

  const AdminPaymentsSummary({
    required this.transactionCount,
    required this.collected,
  });
}

/// One row of the Top Products ranking.
class TopProductSales {
  final String name;

  /// Null once the product has been deleted.
  final String? productId;
  final int units;

  /// Quantity x unit price of the lines sold, before any order-level promo
  /// discount, delivery or refund.
  final double revenue;

  const TopProductSales({
    required this.name,
    this.productId,
    required this.units,
    this.revenue = 0,
  });

  factory TopProductSales.fromMap(Map<String, dynamic> map) => TopProductSales(
    name: map['product_name'] as String? ?? '',
    productId: map['product_id'] as String?,
    units: (map['units'] as num?)?.toInt() ?? 0,
    revenue: (map['revenue'] as num?)?.toDouble() ?? 0,
  );
}

/// The app's copy of `admin_top_products`, used until migration 0078 is
/// applied: units per product name over every order that is not cancelled,
/// most units first, ties by name. [orders] must be newest first.
List<TopProductSales> rankTopProductSales(List<Order> orders) {
  final units = <String, int>{};
  final revenue = <String, double>{};
  final productIds = <String, String>{};
  for (final order in orders) {
    if (order.status == OrderStatus.cancelled) continue;
    for (final item in order.items) {
      final name = item.productName;
      units[name] = (units[name] ?? 0) + item.quantity;
      revenue[name] = (revenue[name] ?? 0) + item.subtotal;
      if (item.productId.isNotEmpty) productIds.putIfAbsent(name, () => item.productId);
    }
  }
  return [
    for (final entry in units.entries)
      TopProductSales(
        name: entry.key,
        productId: productIds[entry.key],
        units: entry.value,
        revenue: revenue[entry.key] ?? 0,
      ),
  ]..sort((a, b) {
    final byUnits = b.units.compareTo(a.units);
    return byUnits != 0 ? byUnits : a.name.compareTo(b.name);
  });
}

/// Orders waiting to be paid or packed, and revenue: paid orders and later
/// stages, less verified refunds. "Week" is the last 7 days.
class AdminOrderSummary {
  final int openOrders;
  final double totalRevenue;
  final double weekRevenue;

  const AdminOrderSummary({
    required this.openOrders,
    required this.totalRevenue,
    required this.weekRevenue,
  });
}
