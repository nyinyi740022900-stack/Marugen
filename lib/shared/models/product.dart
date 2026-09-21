enum ProductCategory { koi, arowana, fishFood, accessories }

ProductCategory categoryFromString(String value) {
  switch (value) {
    case 'arowana':
      return ProductCategory.arowana;
    case 'fish_food':
      return ProductCategory.fishFood;
    case 'accessories':
      return ProductCategory.accessories;
    default:
      return ProductCategory.koi;
  }
}

String categoryLabel(ProductCategory c) {
  switch (c) {
    case ProductCategory.koi:
      return 'Koi';
    case ProductCategory.arowana:
      return 'Arowana';
    case ProductCategory.fishFood:
      return 'Fish Food';
    case ProductCategory.accessories:
      return 'Accessories';
  }
}

/// Extra biological details that only apply to live fish (koi/arowana),
/// since each fish is a unique, single-stock item.
class FishDetails {
  final String? variety; // e.g. Kohaku, Showa, Super Red
  final double? sizeCm;
  final String? gender;
  final String? breeder;
  final bool hasCertificate;

  const FishDetails({
    this.variety,
    this.sizeCm,
    this.gender,
    this.breeder,
    this.hasCertificate = false,
  });

  /// Whether there's anything real to show under a "DETAILS" section —
  /// guards against rendering an empty header when every field is null.
  bool get hasAnyDetail =>
      variety != null ||
      sizeCm != null ||
      gender != null ||
      breeder != null ||
      hasCertificate;

  factory FishDetails.fromMap(Map<String, dynamic> map) {
    return FishDetails(
      variety: map['variety'] as String?,
      sizeCm: (map['size_cm'] as num?)?.toDouble(),
      gender: map['gender'] as String?,
      breeder: map['breeder'] as String?,
      hasCertificate: map['has_certificate'] as bool? ?? false,
    );
  }
}

/// A single purchasable option under a restockable product — e.g. "500g"
/// or "1kg" of fish food. Only ever attached to `fish_food`/`accessories`
/// products; live fish (koi/arowana) are unique single-stock items and
/// never carry variants (see [Product.hasVariants]).
///
/// When the parent product has [Product.sizeOptions], inventory lives in
/// [sizeStocks] (one qty per pellet size) and [stockQuantity] is ignored
/// for availability. Price still comes from this weight row.
class ProductVariant {
  final String id;
  final String productId;
  final String label;
  final double price;
  final int stockQuantity;
  final String? sku;
  final int sortOrder;

  /// Size label → stock for this weight. Empty when the product has no
  /// size options (legacy weight-only stock via [stockQuantity]).
  final Map<String, int> sizeStocks;

  const ProductVariant({
    required this.id,
    required this.productId,
    required this.label,
    required this.price,
    this.stockQuantity = 0,
    this.sku,
    this.sortOrder = 0,
    this.sizeStocks = const {},
  });

  bool get usesSizeStocks => sizeStocks.isNotEmpty;

  /// Units available for a size pick, or the weight-level stock when the
  /// size matrix is unused.
  int stockForSize(String? size) {
    if (!usesSizeStocks) return stockQuantity;
    if (size == null) return effectiveStock;
    return sizeStocks[size] ?? 0;
  }

  /// Total sellable units on this weight row.
  int get effectiveStock {
    if (!usesSizeStocks) return stockQuantity > 0 ? stockQuantity : 0;
    return sizeStocks.values.fold<int>(0, (sum, q) => sum + (q > 0 ? q : 0));
  }

  factory ProductVariant.fromMap(Map<String, dynamic> map) {
    final rawStocks = map['size_stocks'];
    final sizeStocks = <String, int>{};
    if (rawStocks is List) {
      for (final row in rawStocks) {
        if (row is! Map) continue;
        final label = (row['size_label'] as String?)?.trim() ?? '';
        if (label.isEmpty) continue;
        sizeStocks[label] = (row['stock_quantity'] as num?)?.toInt() ?? 0;
      }
    }
    return ProductVariant(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      label: map['label'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      stockQuantity: map['stock_quantity'] as int? ?? 0,
      sku: map['sku'] as String?,
      sortOrder: map['sort_order'] as int? ?? 0,
      sizeStocks: sizeStocks,
    );
  }
}

class Product {
  final String id;
  final String name;
  final String? description;
  final ProductCategory category;
  final double? price; // null when admin has hidden the price
  final double? salePrice; // set + < price when this item is discounted
  final bool showPrice;
  final int stockQuantity; // live fish: 0 or 1
  final List<String> imageUrls;
  final String? videoUrl;
  final FishDetails? fishDetails;
  final bool isSold;
  final List<ProductVariant> variants;

  /// Pellet/size labels the shopper picks independently of weight
  /// variants (e.g. Small / Medium / Large). Price stays on the weight
  /// variant; stock is per weight×size in [ProductVariant.sizeStocks].
  final List<String> sizeOptions;

  /// Units sold across all paid+ orders. Populated from
  /// `get_product_stats()` when the repository requests stats; 0 otherwise
  /// (e.g. the product-detail fetch, which doesn't need it).
  final int soldCount;

  /// Average of visible (non-hidden) review ratings, or null if there are
  /// none yet. Same stats-request caveat as [soldCount].
  final double? avgRating;
  final int reviewCount;

  const Product({
    required this.id,
    required this.name,
    this.description,
    required this.category,
    this.price,
    this.salePrice,
    this.showPrice = true,
    this.stockQuantity = 0,
    this.imageUrls = const [],
    this.videoUrl,
    this.fishDetails,
    this.isSold = false,
    this.variants = const [],
    this.sizeOptions = const [],
    this.soldCount = 0,
    this.avgRating,
    this.reviewCount = 0,
  });

  /// Only ever applies to the simple (non-variant) price — variant
  /// products price per weight/size already, so a single sale price
  /// wouldn't map cleanly onto them.
  bool get hasActiveSale =>
      !hasVariants && price != null && salePrice != null && salePrice! < price!;

  /// The price actually charged — the sale price when one is active,
  /// otherwise the regular price.
  double? get effectivePrice => hasActiveSale ? salePrice : price;

  /// Whole-number "-N%" for the sale badge.
  int get discountPercent =>
      hasActiveSale ? (100 - (salePrice! / price! * 100)).round() : 0;

  /// The price to sort/compare by — for a variant product this is the
  /// lowest variant price (what the card actually shows as "From $X"),
  /// not the legacy `price` field, which variant products don't keep in
  /// sync. Null only when there's truly no price to show (contact-for-price
  /// with no variants).
  double? get sortPrice {
    if (hasVariants) {
      final prices = variants.map((v) => v.price);
      return prices.isEmpty ? null : prices.reduce((a, b) => a < b ? a : b);
    }
    return effectivePrice;
  }

  bool get isLiveFish =>
      category == ProductCategory.koi || category == ProductCategory.arowana;

  /// True for both restockable goods (weight options) and a live-fish
  /// listing photographed as a batch (e.g. "Japan Imported Koi Selection")
  /// where each option is a specific fish/variety pick.
  bool get hasVariants => variants.isNotEmpty;

  /// Restockable goods only — a live fish option is a specific animal, not
  /// a pellet-size pick, so size chips never apply to koi/arowana.
  bool get hasSizeOptions => !isLiveFish && sizeOptions.isNotEmpty;

  /// Whether the shop is willing to sell this at a shown price. False for
  /// "Contact us for price" items (hidden price, or no price and no
  /// variants to pick a price from).
  bool get isPurchasable => showPrice && (hasVariants || price != null);

  /// Total units the customer can still buy — the sum across variants for
  /// variant products (or across the weight×size matrix when sizes exist),
  /// otherwise the base stock. Live fish are 0 or 1.
  int get availableStock {
    if (isSold) return 0;
    if (hasVariants) {
      if (hasSizeOptions) {
        // Size list means inventory is the matrix only — missing cells are 0,
        // never fall back to the weight row's stock_quantity.
        return variants.fold<int>(0, (sum, v) {
          return sum +
              sizeOptions.fold<int>(0, (inner, size) {
                final q = v.sizeStocks[size] ?? 0;
                return inner + (q > 0 ? q : 0);
              });
        });
      }
      return variants.fold<int>(0, (sum, v) => sum + v.effectiveStock);
    }
    return stockQuantity > 0 ? stockQuantity : 0;
  }

  /// Stock for a specific weight (+ optional size) pick.
  int stockFor({required String variantId, String? size}) {
    final match = variants.where((v) => v.id == variantId);
    if (match.isEmpty) return 0;
    final variant = match.first;
    if (hasSizeOptions) {
      if (size == null) return 0;
      return variant.sizeStocks[size] ?? 0;
    }
    return variant.stockQuantity > 0 ? variant.stockQuantity : 0;
  }

  /// One flag for every "you can't buy this right now" case: the fish was
  /// sold, every variant is at 0, or the base stock is at 0.
  bool get isOutOfStock => availableStock <= 0;

  /// Label for the unavailable state — a unique animal is "Sold", a bag of
  /// food is merely "Out of Stock" (it will come back).
  String get unavailableLabel => isLiveFish ? 'Sold' : 'Out of Stock';

  /// A restockable, priced product with no size options — the only kind a
  /// grid card can add straight to the cart without asking anything.
  bool get supportsQuickAdd =>
      !isLiveFish && isPurchasable && !hasVariants && !isOutOfStock;

  /// Options a shopper picks from, for the "N options" grid label —
  /// only meaningful when [hasVariants] is true.
  int get variantCount => variants.length;

  Product withStats({required int soldCount, double? avgRating, required int reviewCount}) {
    return Product(
      id: id,
      name: name,
      description: description,
      category: category,
      price: price,
      salePrice: salePrice,
      showPrice: showPrice,
      stockQuantity: stockQuantity,
      imageUrls: imageUrls,
      videoUrl: videoUrl,
      fishDetails: fishDetails,
      isSold: isSold,
      variants: variants,
      sizeOptions: sizeOptions,
      soldCount: soldCount,
      avgRating: avgRating,
      reviewCount: reviewCount,
    );
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    final variants = (map['variants'] as List?)
            ?.map((e) => ProductVariant.fromMap(e as Map<String, dynamic>))
            .toList() ??
        <ProductVariant>[];
    variants.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final rawSizes = map['size_options'];
    final sizeOptions = rawSizes is List
        ? rawSizes
            .map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList()
        : <String>[];
    return Product(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      description: map['description'] as String?,
      category: categoryFromString(map['category'] as String? ?? 'koi'),
      price: (map['price'] as num?)?.toDouble(),
      salePrice: (map['sale_price'] as num?)?.toDouble(),
      showPrice: map['show_price'] as bool? ?? true,
      stockQuantity: map['stock_quantity'] as int? ?? 0,
      imageUrls: (map['image_urls'] as List?)?.cast<String>() ?? const [],
      videoUrl: map['video_url'] as String?,
      fishDetails: map['fish_details'] != null
          ? FishDetails.fromMap(map['fish_details'] as Map<String, dynamic>)
          : null,
      isSold: map['is_sold'] as bool? ?? false,
      variants: variants,
      sizeOptions: sizeOptions,
    );
  }

  Product copyWithVariants(List<ProductVariant> variants) {
    return Product(
      id: id,
      name: name,
      description: description,
      category: category,
      price: price,
      salePrice: salePrice,
      showPrice: showPrice,
      stockQuantity: stockQuantity,
      imageUrls: imageUrls,
      videoUrl: videoUrl,
      fishDetails: fishDetails,
      isSold: isSold,
      variants: variants,
      sizeOptions: sizeOptions,
      soldCount: soldCount,
      avgRating: avgRating,
      reviewCount: reviewCount,
    );
  }
}
