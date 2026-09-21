import '../../../core/supabase/supabase_client.dart';

/// One product-view event, with the product name already joined in (null
/// if the product was since deleted).
class ProductViewRow {
  final String? productId;
  final String? productName;
  final DateTime viewedAt;

  const ProductViewRow({this.productId, this.productName, required this.viewedAt});
}

class AnalyticsRepository {
  final _client = SupabaseService.client;

  /// Raw product-view events in the last [days] days, newest first.
  /// Admin-only per RLS.
  Future<List<ProductViewRow>> fetchProductViews({int days = 90}) async {
    final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    final data = await _client
        .from('product_views')
        .select('product_id, viewed_at, products(name)')
        .gte('viewed_at', since)
        .order('viewed_at', ascending: false);
    return (data as List).map((e) {
      final map = e as Map<String, dynamic>;
      final product = map['products'] as Map<String, dynamic>?;
      return ProductViewRow(
        productId: map['product_id'] as String?,
        productName: product?['name'] as String?,
        viewedAt: DateTime.parse(map['viewed_at'] as String),
      );
    }).toList();
  }

  /// Raw app-visit timestamps in the last [days] days. Admin-only per RLS.
  Future<List<DateTime>> fetchAppVisits({int days = 90}) async {
    final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    final data = await _client
        .from('app_visits')
        .select('visited_at')
        .gte('visited_at', since)
        .order('visited_at', ascending: false);
    return (data as List)
        .map((e) => DateTime.parse((e as Map<String, dynamic>)['visited_at'] as String))
        .toList();
  }
}
