import 'dart:async';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/order.dart';

class OrderRepository {
  final _client = SupabaseService.client;

  Future<List<Order>> fetchMyOrders() async {
    final user = SupabaseService.currentUser;
    if (user == null) return [];
    final data = await _client
        .from('orders')
        .select('*, items:order_items(*)')
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
        .select('*, items:order_items(*)')
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
    var query = _client.from('orders').select('*, items:order_items(*)');
    if (status != null) {
      query = query.eq('status', status.name);
    }
    final data = await query.order('created_at', ascending: false);
    return (data as List)
        .map((e) => Order.fromMap(e as Map<String, dynamic>))
        .toList();
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
    var query = _client.from('orders').select('*, items:order_items(*)');
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

  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
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

  /// Customer-initiated cancellation. RLS (0007_customer_order_cancel.sql)
  /// only allows this when the order is still `pending`/`paid` and only
  /// lets the update land on `status = 'cancelled'` — nothing else.
  Future<void> cancelMyOrder(String orderId) async {
    await _client
        .from('orders')
        .update({'status': 'cancelled'})
        .eq('id', orderId);
  }

  /// Fetches a single order by id (RLS restricts this to the owning user,
  /// or admins). Used as a fallback when an order's data wasn't already
  /// passed in via router `extra` (e.g. a deep link into `/orders/:id`).
  Future<Order?> fetchOrderById(String id) async {
    final data = await _client
        .from('orders')
        .select('*, items:order_items(*)')
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return Order.fromMap(data);
  }
}
