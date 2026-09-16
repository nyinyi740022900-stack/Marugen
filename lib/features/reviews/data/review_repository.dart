import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/review.dart';

class ReviewRepository {
  final _client = SupabaseService.client;

  Future<List<ProductReview>> fetchReviewsForProduct(String productId) async {
    final data = await _client
        .from('product_reviews')
        .select()
        .eq('product_id', productId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => ProductReview.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// The current user's own review on [productId], if any — RLS lets
  /// anyone read all reviews, so this just filters client-side by user id.
  Future<ProductReview?> fetchMyReview(String productId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return null;
    final data = await _client
        .from('product_reviews')
        .select()
        .eq('product_id', productId)
        .eq('user_id', user.id)
        .maybeSingle();
    if (data == null) return null;
    return ProductReview.fromMap(data);
  }

  /// Statuses that count as "this customer really bought it". Pending
  /// (unpaid) and cancelled/refunded orders don't qualify. Mirrors the RLS
  /// policy in `0009_verified_reviews.sql` — the database is the real
  /// gate; this only decides what the UI shows.
  static const purchasedStatuses = ['paid', 'packing', 'shipped', 'delivered'];

  /// Whether the current user has a qualifying order containing
  /// [productId]. Uses an inner join so orders in other statuses filter
  /// the order_items rows out entirely.
  Future<bool> hasPurchasedProduct(String productId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return false;
    final data = await _client
        .from('order_items')
        .select('id, orders!inner(user_id, status)')
        .eq('product_id', productId)
        .eq('orders.user_id', user.id)
        .inFilter('orders.status', purchasedStatuses)
        .limit(1);
    return (data as List).isNotEmpty;
  }

  Future<void> upsertMyReview({
    required String productId,
    required int rating,
    String? comment,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('Not logged in');
    await _client.from('product_reviews').upsert(
      {
        'product_id': productId,
        'user_id': user.id,
        'rating': rating,
        'comment': comment,
      },
      onConflict: 'product_id,user_id',
    );
  }

  Future<void> deleteMyReview(String reviewId) async {
    await _client.from('product_reviews').delete().eq('id', reviewId);
  }
}
