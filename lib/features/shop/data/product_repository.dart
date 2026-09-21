import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/product.dart';

/// True only for errors that mean "the schema/table/relationship isn't
/// there yet" (e.g. migration 0008/0020 not applied) — the one case this
/// fallback is meant for. Anything else (network error, RLS denial,
/// transient timeout) should surface as a real error instead of silently
/// showing zero variants/stock, which previously masked genuine failures
/// as "no variants".
bool _isMissingSchemaError(Object e) {
  if (e is! PostgrestException) return false;
  final code = e.code;
  final message = e.message.toLowerCase();
  return code == '42P01' || // undefined_table
      code == 'PGRST200' || // PostgREST: could not find relationship
      code == 'PGRST205' || // PostgREST: could not find table in schema cache
      message.contains('does not exist') ||
      message.contains('schema cache');
}

class ProductRepository {
  final _client = SupabaseService.client;

  /// Embeds each product's variants and per-size stocks so grid cards and
  /// the PDP can total / gate inventory across the weight×size matrix.
  static const _withVariants =
      '*, variants:product_variants(*, size_stocks:product_variant_size_stocks(*))';

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

  /// Admin: one page of products (`[offset, offset+limit)`) — see
  /// PagedNotifier (shared/providers/paged_notifier.dart). Used for the
  /// default (no search query) admin Products list; a search falls back
  /// to [fetchProducts]' unbounded fetch + client-side filter, same as
  /// today, since paginating would otherwise only search within whatever
  /// page happened to be loaded.
  Future<List<Product>> fetchProductsPage({
    ProductCategory? category,
    required int offset,
    required int limit,
  }) async {
    var query = _client.from('products').select(_withVariants);
    if (category != null) {
      query = query.eq('category', category.name == 'fishFood' ? 'fish_food' : category.name);
    }
    final data = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
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
    final variants = await fetchVariantsForProduct(id);
    product = product.copyWithVariants(variants);
    return product;
  }

  /// Variant options (size/weight) for a restockable product, ordered for
  /// display. The table may not exist yet if migration 0008 hasn't been
  /// applied — treat any error as "no variants" rather than crashing.
  Future<List<ProductVariant>> fetchVariantsForProduct(String productId) async {
    try {
      final data = await _client
          .from('product_variants')
          .select('*, size_stocks:product_variant_size_stocks(*)')
          .eq('product_id', productId)
          .order('sort_order', ascending: true);
      return (data as List)
          .map((e) => ProductVariant.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (!_isMissingSchemaError(e)) rethrow;
      // Fallback if size-stocks embed isn't available yet (migration pending).
      final data = await _client
          .from('product_variants')
          .select()
          .eq('product_id', productId)
          .order('sort_order', ascending: true);
      return (data as List)
          .map((e) => ProductVariant.fromMap(e as Map<String, dynamic>))
          .toList();
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

  /// Upserts one weight×size stock cell. Creates the row when missing.
  Future<void> upsertVariantSizeStock({
    required String variantId,
    required String sizeLabel,
    required int stockQuantity,
  }) async {
    await _client.from('product_variant_size_stocks').upsert(
      {
        'variant_id': variantId,
        'size_label': sizeLabel,
        'stock_quantity': stockQuantity < 0 ? 0 : stockQuantity,
      },
      onConflict: 'variant_id,size_label',
    );
  }

  /// Drops size-stock rows whose label is no longer in the product's size list.
  Future<void> deleteOrphanSizeStocks({
    required String productId,
    required List<String> keepSizes,
  }) async {
    final variants = await fetchVariantsForProduct(productId);
    for (final v in variants) {
      for (final size in v.sizeStocks.keys) {
        if (!keepSizes.contains(size)) {
          await _client
              .from('product_variant_size_stocks')
              .delete()
              .eq('variant_id', v.id)
              .eq('size_label', size);
        }
      }
    }
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
