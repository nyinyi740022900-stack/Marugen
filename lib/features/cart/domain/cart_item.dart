import '../../../shared/models/product.dart';

class CartItem {
  final Product product;
  final int quantity;
  final ProductVariant? selectedVariant;

  /// Pellet/size label when [Product.hasSizeOptions] — informational only
  /// (does not change [unitPrice] or stock). Null when the product has no
  /// size list.
  final String? selectedSize;

  const CartItem({
    required this.product,
    this.quantity = 1,
    this.selectedVariant,
    this.selectedSize,
  });

  /// Unit price — the selected variant's price when present, else the
  /// product's sale price when one is active, else its regular price.
  double get unitPrice => selectedVariant?.price ?? product.effectivePrice ?? 0;

  double get subtotal => unitPrice * quantity;

  /// Identifies a cart line for merge/increment purposes: same product,
  /// same weight variant, AND same size (including "no size"). Two
  /// entries for the same 5kg bag but different pellet sizes stay separate.
  String get lineKey =>
      '${product.id}::${selectedVariant?.id ?? ''}::${selectedSize ?? ''}';

  /// Customer-facing weight · size caption for cart / checkout rows.
  String? get optionLabel {
    final parts = <String>[
      if (selectedVariant != null && selectedVariant!.label.isNotEmpty)
        selectedVariant!.label,
      if (selectedSize != null && selectedSize!.isNotEmpty) selectedSize!,
    ];
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  CartItem copyWith({int? quantity}) => CartItem(
        product: product,
        quantity: quantity ?? this.quantity,
        selectedVariant: selectedVariant,
        selectedSize: selectedSize,
      );
}
