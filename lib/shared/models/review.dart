/// A single customer's rating + optional comment on a product.
/// `product_reviews` has a `unique(product_id, user_id)` constraint, so a
/// user can only ever have one review per product — update/delete instead
/// of a second insert.
class ProductReview {
  final String id;
  final String productId;
  final String userId;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  final String? authorName;
  final bool isHidden;

  const ProductReview({
    required this.id,
    required this.productId,
    required this.userId,
    required this.rating,
    this.comment,
    required this.createdAt,
    this.authorName,
    this.isHidden = false,
  });

  factory ProductReview.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    return ProductReview(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      userId: map['user_id'] as String,
      rating: map['rating'] as int? ?? 0,
      comment: map['comment'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      authorName: profile?['full_name'] as String?,
      isHidden: map['is_hidden'] as bool? ?? false,
    );
  }
}
