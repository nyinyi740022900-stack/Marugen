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
class ProductVariant {
  final String id;
  final String productId;
  final String label;
  final double price;
  final int stockQuantity;
  final String? sku;
  final int sortOrder;

  const ProductVariant({
    required this.id,
    required this.productId,
    required this.label,
    required this.price,
    this.stockQuantity = 0,
    this.sku,
    this.sortOrder = 0,
  });

  factory ProductVariant.fromMap(Map<String, dynamic> map) {
    return ProductVariant(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      label: map['label'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      stockQuantity: map['stock_quantity'] as int? ?? 0,
      sku: map['sku'] as String?,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }
}

class Product {
  final String id;
  final String name;
  final String? description;
  final ProductCategory category;
  final double? price; // null when admin has hidden the price
  final bool showPrice;
  final int stockQuantity; // live fish: 0 or 1
  final List<String> imageUrls;
  final String? videoUrl;
  final FishDetails? fishDetails;
  final bool isSold;
  final List<ProductVariant> variants;

  const Product({
    required this.id,
    required this.name,
    this.description,
    required this.category,
    this.price,
    this.showPrice = true,
    this.stockQuantity = 0,
    this.imageUrls = const [],
    this.videoUrl,
    this.fishDetails,
    this.isSold = false,
    this.variants = const [],
  });

  bool get isLiveFish =>
      category == ProductCategory.koi || category == ProductCategory.arowana;

  /// Only ever meaningful for restockable goods (fish_food/accessories) —
  /// live-fish products never get a variant UI path even if bad data
  /// somehow attaches variants to one.
  bool get hasVariants => !isLiveFish && variants.isNotEmpty;

  /// Whether the shop is willing to sell this at a shown price. False for
  /// "Contact us for price" items (hidden price, or no price and no
  /// variants to pick a price from).
  bool get isPurchasable => showPrice && (hasVariants || price != null);

  /// Total units the customer can still buy — the sum across variants for
  /// variant products, otherwise the base stock. Live fish are 0 or 1.
  int get availableStock {
    if (isSold) return 0;
    if (hasVariants) {
      return variants.fold<int>(
          0, (sum, v) => sum + (v.stockQuantity > 0 ? v.stockQuantity : 0));
    }
    return stockQuantity > 0 ? stockQuantity : 0;
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

  factory Product.fromMap(Map<String, dynamic> map) {
    final variants = (map['variants'] as List?)
            ?.map((e) => ProductVariant.fromMap(e as Map<String, dynamic>))
            .toList() ??
        <ProductVariant>[];
    variants.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return Product(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      description: map['description'] as String?,
      category: categoryFromString(map['category'] as String? ?? 'koi'),
      price: (map['price'] as num?)?.toDouble(),
      showPrice: map['show_price'] as bool? ?? true,
      stockQuantity: map['stock_quantity'] as int? ?? 0,
      imageUrls: (map['image_urls'] as List?)?.cast<String>() ?? const [],
      videoUrl: map['video_url'] as String?,
      fishDetails: map['fish_details'] != null
          ? FishDetails.fromMap(map['fish_details'] as Map<String, dynamic>)
          : null,
      isSold: map['is_sold'] as bool? ?? false,
      variants: variants,
    );
  }

  Product copyWithVariants(List<ProductVariant> variants) {
    return Product(
      id: id,
      name: name,
      description: description,
      category: category,
      price: price,
      showPrice: showPrice,
      stockQuantity: stockQuantity,
      imageUrls: imageUrls,
      videoUrl: videoUrl,
      fishDetails: fishDetails,
      isSold: isSold,
      variants: variants,
    );
  }
}
