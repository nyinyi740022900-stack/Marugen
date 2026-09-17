import 'dart:typed_data';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/product.dart';

class ProductRepository {
  final _client = SupabaseService.client;

  /// Embeds each product's variants (`product_variants` FK) so grid cards
  /// know whether a product needs a size picked before it can be added to
  /// the cart, and can total stock across variants.
  static const _withVariants = '*, variants:product_variants(*)';

  Future<List<Product>> fetchProducts({ProductCategory? category}) async {
    var query = _client.from('products').select(_withVariants);
    if (category != null) {
      query = query.eq('category', category.name == 'fishFood' ? 'fish_food' : category.name);
    }
    final data = await query.order('created_at', ascending: false);
    final products = (data as List)
        .map((e) => Product.fromMap(e as Map<String, dynamic>))
        .toList();
    return _withStats(products);
  }

  /// Attaches sold-count and review-aggregate stats (via the
  /// `get_product_stats()` RPC — see migration 0013) to each product for
  /// the shop grid's "N sold" / star-rating badges. Best-effort: if the
  /// function isn't deployed yet, products just show with zero stats
  /// instead of failing the whole list.
  Future<List<Product>> _withStats(List<Product> products) async {
    if (products.isEmpty) return products;
    try {
      final stats = await _client.rpc('get_product_stats') as List;
      final byId = {for (final s in stats) s['product_id'] as String: s};
      return products.map((p) {
        final s = byId[p.id];
        if (s == null) return p;
        return p.withStats(
          soldCount: s['sold_count'] as int? ?? 0,
          avgRating: (s['avg_rating'] as num?)?.toDouble(),
          reviewCount: s['review_count'] as int? ?? 0,
        );
      }).toList();
    } catch (_) {
      return products;
    }
  }

  Future<Product?> fetchProductById(String id) async {
    final data =
        await _client.from('products').select().eq('id', id).maybeSingle();
    if (data == null) return null;
    var product = Product.fromMap(data);
    // Variants only ever apply to restockable goods (fish_food/
    // accessories) — skip the extra query for live fish (koi/arowana).
    if (!product.isLiveFish) {
      final variants = await fetchVariantsForProduct(id);
      product = product.copyWithVariants(variants);
    }
    return product;
  }

  /// Variant options (size/weight) for a restockable product, ordered for
  /// display. The table may not exist yet if migration 0008 hasn't been
  /// applied — treat any error as "no variants" rather than crashing.
  Future<List<ProductVariant>> fetchVariantsForProduct(String productId) async {
    try {
      final data = await _client
          .from('product_variants')
          .select()
          .eq('product_id', productId)
          .order('sort_order', ascending: true);
      return (data as List)
          .map((e) => ProductVariant.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<ProductVariant> createVariant(Map<String, dynamic> payload) async {
    final row =
        await _client.from('product_variants').insert(payload).select().single();
    return ProductVariant.fromMap(row);
  }

  Future<void> updateVariant(String id, Map<String, dynamic> payload) async {
    await _client.from('product_variants').update(payload).eq('id', id);
  }

  Future<void> deleteVariant(String id) async {
    await _client.from('product_variants').delete().eq('id', id);
  }

  /// Other products in the same category as [productId] (excluding it) —
  /// backs the "You may also like" row on the product detail screen.
  Future<List<Product>> fetchRelatedProducts({
    required String productId,
    required ProductCategory category,
    int limit = 6,
  }) async {
    final categoryValue = category.name == 'fishFood' ? 'fish_food' : category.name;
    final data = await _client
        .from('products')
        .select(_withVariants)
        .eq('category', categoryValue)
        .neq('id', productId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List)
        .map((e) => Product.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Inserts a new product and returns its generated id.
  Future<String> createProduct(Map<String, dynamic> payload) async {
    final row = await _client.from('products').insert(payload).select().single();
    return row['id'] as String;
  }

  Future<void> updateProduct(String id, Map<String, dynamic> payload) async {
    await _client.from('products').update(payload).eq('id', id);
  }

  Future<void> deleteProduct(String id) async {
    await _client.from('products').delete().eq('id', id);
  }

  Future<String> uploadProductImage(
      String productId, Uint8List bytes, String ext) async {
    final path =
        'products/$productId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('product-images').uploadBinary(path, bytes);
    return _client.storage.from('product-images').getPublicUrl(path);
  }
}
