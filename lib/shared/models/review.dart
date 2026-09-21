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
  final String? authorAvatarUrl;
  final bool isHidden;

  /// The shop's public reply to this review, if any — see
  /// 0031_review_shop_reply.sql. One reply per review (single-vendor app,
  /// no threading), same pattern as Amazon/Shopee/Lazada seller replies.
  final String? shopReply;
  final DateTime? shopReplyAt;

  const ProductReview({
    required this.id,
    required this.productId,
    required this.userId,
    required this.rating,
    this.comment,
    required this.createdAt,
    this.authorName,
    this.authorAvatarUrl,
    this.isHidden = false,
    this.shopReply,
    this.shopReplyAt,
  });

  factory ProductReview.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    final replyAt = map['admin_reply_at'] as String?;
    return ProductReview(
      id: map['id'] as String,
      productId: map['product_id'] as String,
      userId: map['user_id'] as String,
      rating: map['rating'] as int? ?? 0,
      comment: map['comment'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      authorName: profile?['full_name'] as String?,
      authorAvatarUrl: profile?['avatar_url'] as String?,
      isHidden: map['is_hidden'] as bool? ?? false,
      shopReply: map['admin_reply'] as String?,
      shopReplyAt: replyAt == null ? null : DateTime.parse(replyAt),
    );
  }
}
