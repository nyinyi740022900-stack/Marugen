import 'product.dart';

/// A saved (favorited) product in the customer's wishlist.
/// See `supabase/migrations/0004_wishlist.sql`.
class WishlistItem {
  final String id;
  final String userId;
  final String productId;
  final DateTime createdAt;
  final Product? product;

  const WishlistItem({
    required this.id,
    required this.userId,
    required this.productId,
    required this.createdAt,
    this.product,
  });

  factory WishlistItem.fromMap(Map<String, dynamic> map) {
    return WishlistItem(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      productId: map['product_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      product: map['product'] != null
          ? Product.fromMap(map['product'] as Map<String, dynamic>)
          : null,
    );
  }
}
