import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/wishlist_item.dart';

/// CRUD for the customer's wishlist / favorites.
/// See `supabase/migrations/0004_wishlist.sql`.
class WishlistRepository {
  final _client = SupabaseService.client;

  Future<List<WishlistItem>> fetchMyWishlist() async {
    final user = SupabaseService.currentUser;
    if (user == null) return [];
    final data = await _client
        .from('wishlist_items')
        .select('*, product:products(*)')
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => WishlistItem.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// The bare set of favorited product ids — cheap to fetch and enough to
  /// drive the heart toggle on product cards/detail without pulling full
  /// product rows.
  Future<Set<String>> fetchMyWishlistProductIds() async {
    final user = SupabaseService.currentUser;
    if (user == null) return {};
    final data = await _client
        .from('wishlist_items')
        .select('product_id')
        .eq('user_id', user.id);
    return (data as List).map((e) => e['product_id'] as String).toSet();
  }

  Future<void> add(String productId) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('Not logged in');
    await _client.from('wishlist_items').upsert(
      {'user_id': user.id, 'product_id': productId},
      onConflict: 'user_id,product_id',
    );
  }

  Future<void> remove(String productId) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('Not logged in');
    await _client
        .from('wishlist_items')
        .delete()
        .eq('user_id', user.id)
        .eq('product_id', productId);
  }
}
