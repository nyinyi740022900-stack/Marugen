import '../../../shared/models/product.dart';

class CartItem {
  final Product product;
  final int quantity;
  final ProductVariant? selectedVariant;

  const CartItem({required this.product, this.quantity = 1, this.selectedVariant});

  /// Unit price — the selected variant's price when present, else the
  /// product's base price (unchanged behavior for non-variant products).
  double get unitPrice => selectedVariant?.price ?? product.price ?? 0;

  double get subtotal => unitPrice * quantity;

  /// Identifies a cart line for merge/increment purposes: same product
  /// AND same variant (including "no variant"). Two entries for the same
  /// product but different variants are separate line items.
  String get lineKey => '${product.id}::${selectedVariant?.id ?? ''}';

  CartItem copyWith({int? quantity}) => CartItem(
        product: product,
        quantity: quantity ?? this.quantity,
        selectedVariant: selectedVariant,
      );
}
