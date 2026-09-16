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
    return (data as List).map((e) => Order.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Admin: all orders, optionally filtered by status.
  Future<List<Order>> fetchAllOrders({OrderStatus? status}) async {
    var query = _client.from('orders').select('*, items:order_items(*)');
    if (status != null) {
      query = query.eq('status', status.name);
    }
    final data = await query.order('created_at', ascending: false);
    return (data as List).map((e) => Order.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    await _client.from('orders').update({'status': status.name}).eq('id', orderId);
  }

  /// Customer-initiated cancellation. RLS (0007_customer_order_cancel.sql)
  /// only allows this when the order is still `pending`/`paid` and only
  /// lets the update land on `status = 'cancelled'` — nothing else.
  Future<void> cancelMyOrder(String orderId) async {
    await _client.from('orders').update({'status': 'cancelled'}).eq('id', orderId);
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
