import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/review.dart';

class ReviewRepository {
  final _client = SupabaseService.client;

  Future<List<ProductReview>> fetchReviewsForProduct(String productId) async {
    // RLS hides moderated reviews from the public; authors/admins still see theirs.
    final data = await _client
        .from('product_reviews')
        .select('*, profiles(full_name, avatar_url)')
        .eq('product_id', productId)
        .eq('is_hidden', false)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => ProductReview.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Admin: all reviews, including hidden. Unbounded — kept only as a
  /// simple reference; the admin screen uses [fetchAllReviewsForAdminPage]
  /// for the actual (paged) list.
  Future<List<ProductReview>> fetchAllReviewsForAdmin() async {
    final data = await _client
        .from('product_reviews')
        .select('*, profiles(full_name, avatar_url)')
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => ProductReview.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Admin: one page of reviews (`[offset, offset+limit)`) — see
  /// PagedNotifier (shared/providers/paged_notifier.dart). No search/
  /// filter exists on this screen, so unlike Orders/Products there's no
  /// "fall back to unbounded fetch" case to handle.
  Future<List<ProductReview>> fetchAllReviewsForAdminPage({
    required int offset,
    required int limit,
  }) async {
    final data = await _client
        .from('product_reviews')
        .select('*, profiles(full_name, avatar_url)')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List)
        .map((e) => ProductReview.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setHidden(String reviewId, bool hidden) async {
    await _client
        .from('product_reviews')
        .update({'is_hidden': hidden}).eq('id', reviewId);
  }

  /// Posts/edits the shop's public reply to a review, or clears it when
  /// [reply] is null/empty. Admin-only — enforced by the existing
  /// "Admins can moderate reviews" RLS policy, same as [setHidden].
  Future<void> setShopReply(String reviewId, String? reply) async {
    final trimmed = reply?.trim();
    await _client.from('product_reviews').update({
      'admin_reply': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      'admin_reply_at': (trimmed == null || trimmed.isEmpty) ? null : DateTime.now().toIso8601String(),
    }).eq('id', reviewId);
  }

  /// The current user's own review on [productId], if any — RLS lets
  /// the author read their own even when hidden.
  Future<ProductReview?> fetchMyReview(String productId) async {
    final user = SupabaseService.currentUser;
    if (user == null) return null;
    final data = await _client
        .from('product_reviews')
        .select('*, profiles(full_name, avatar_url)')
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
