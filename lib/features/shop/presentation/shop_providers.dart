import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/product.dart';
import '../../../shared/providers/paged_notifier.dart';
import '../../../shared/providers/settings_providers.dart';
import '../data/product_repository.dart';

final productRepositoryProvider = Provider<ProductRepository>((ref) => ProductRepository());

final selectedCategoryProvider = StateProvider<ProductCategory?>((ref) => null);

/// Free-text search query typed into the shop screen's search bar.
/// Filtered client-side over the already-fetched list (see
/// [visibleProductListProvider]) since the catalog is small.
final searchQueryProvider = StateProvider<String>((ref) => '');

enum ProductSort { newest, priceLowToHigh, priceHighToLow, nameAZ }

String sortLabel(ProductSort s) {
  switch (s) {
    case ProductSort.newest:
      return 'Newest';
    case ProductSort.priceLowToHigh:
      return 'Price: Low to High';
    case ProductSort.priceHighToLow:
      return 'Price: High to Low';
    case ProductSort.nameAZ:
      return 'Name A–Z';
  }
}

final productSortProvider = StateProvider<ProductSort>((ref) => ProductSort.newest);

final productListProvider = FutureProvider<List<Product>>((ref) async {
  final category = ref.watch(selectedCategoryProvider);
  final repo = ref.watch(productRepositoryProvider);
  return repo.fetchProducts(category: category);
});

/// Paged (infinite-scroll) admin Products list — the default no-search
/// view; see PagedNotifier and AdminOrdersPagedNotifier (orders_
/// providers.dart) for the same pattern. `build()` watches
/// [selectedCategoryProvider] (shared with the customer shop's category
/// chips) so switching category resets pagination from page 0. The
/// customer shop screen keeps using the unbounded [productListProvider]
/// unchanged — only the admin Products screen paginates.
class AdminProductsPagedNotifier extends PagedNotifier<Product> {
  @override
  Future<List<Product>> fetchPage(int offset, int limit) {
    final category = ref.watch(selectedCategoryProvider);
    return ref
        .read(productRepositoryProvider)
        .fetchProductsPage(category: category, offset: offset, limit: limit);
  }
}

final adminProductsPagedProvider =
    NotifierProvider<AdminProductsPagedNotifier, AsyncValue<PagedListState<Product>>>(
        AdminProductsPagedNotifier.new);

/// Call this everywhere an admin mutation used to `ref.invalidate
/// (productListProvider)` — keeps both the legacy unbounded list (still
/// used during search, and by the customer shop) and the new paged
/// admin list in sync after an edit/delete/stock-toggle.
void refreshAdminProducts(WidgetRef ref) {
  ref.invalidate(productListProvider);
  ref.read(adminProductsPagedProvider.notifier).refresh();
}

/// [productListProvider] filtered by [searchQueryProvider] (matching name
/// and, for koi/arowana, variety) and ordered by [productSortProvider].
final visibleProductListProvider = Provider<AsyncValue<List<Product>>>((ref) {
  final productsAsync = ref.watch(productListProvider);
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final sort = ref.watch(productSortProvider);

  return productsAsync.whenData((products) {
    var result = products;
    if (query.isNotEmpty) {
      result = result.where((p) {
        if (p.name.toLowerCase().contains(query)) return true;
        final variety = p.fishDetails?.variety;
        return variety != null && variety.toLowerCase().contains(query);
      }).toList();
    } else {
      result = List.of(result);
    }

    switch (sort) {
      case ProductSort.newest:
        // Already ordered by created_at desc from the repository.
        break;
      case ProductSort.priceLowToHigh:
        result.sort((a, b) => (a.sortPrice ?? double.infinity)
            .compareTo(b.sortPrice ?? double.infinity));
        break;
      case ProductSort.priceHighToLow:
        result.sort((a, b) => (b.sortPrice ?? -1).compareTo(a.sortPrice ?? -1));
        break;
      case ProductSort.nameAZ:
        result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
    }
    return result;
  });
});

final productDetailProvider =
    FutureProvider.family<Product?, String>((ref, id) async {
  final repo = ref.watch(productRepositoryProvider);
  return repo.fetchProductById(id);
});

/// Other products in the same category as the current one — the "You may
/// also like" row on the product detail screen. Keyed by a record (id,
/// category) instead of the [Product] itself so Riverpod's family caching
/// uses proper structural equality rather than object identity.
final relatedProductsProvider = FutureProvider.family<List<Product>,
    ({String id, ProductCategory category})>((ref, key) async {
  final repo = ref.watch(productRepositoryProvider);
  return repo.fetchRelatedProducts(productId: key.id, category: key.category);
});

/// Fallback used while [lowStockThresholdProvider] is still loading the
/// admin-configured value from `settings.low_stock_threshold`.
const defaultLowStockThreshold = 5;

/// Quantity at or below which a restockable product (fish food /
/// accessories) counts as low stock — admin-configurable via Settings.
/// Live fish (koi/arowana) are unique single-stock animals, not
/// restockable inventory, so they're excluded regardless of quantity.
final lowStockThresholdProvider = Provider<int>((ref) {
  final settings = ref.watch(shopSettingsProvider).valueOrNull;
  final raw = settings?['low_stock_threshold'];
  return raw is int ? raw : defaultLowStockThreshold;
});

/// Non-live-fish products at or below [lowStockThresholdProvider] — backs
/// the admin dashboard's "Low Stock" card.
final lowStockProductsProvider = Provider<AsyncValue<List<Product>>>((ref) {
  final productsAsync = ref.watch(productListProvider);
  final threshold = ref.watch(lowStockThresholdProvider);
  return productsAsync.whenData((products) => products
      .where((p) => !p.isLiveFish && p.availableStock <= threshold)
      .toList()
    ..sort((a, b) => a.availableStock.compareTo(b.availableStock)));
});
