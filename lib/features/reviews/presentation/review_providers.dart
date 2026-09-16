import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/review.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/review_repository.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) => ReviewRepository());

final productReviewsProvider =
    FutureProvider.family<List<ProductReview>, String>((ref, productId) {
  return ref.watch(reviewRepositoryProvider).fetchReviewsForProduct(productId);
});

/// The logged-in user's own review on a product, if any — drives whether
/// the product detail screen shows "Write a review" or "Edit your review".
final myReviewForProductProvider =
    FutureProvider.family<ProductReview?, String>((ref, productId) {
  ref.watch(authStateProvider);
  return ref.watch(reviewRepositoryProvider).fetchMyReview(productId);
});

/// Whether the logged-in user is allowed to review this product, i.e. has
/// a paid-or-later order containing it. Guests are never eligible.
final canReviewProductProvider =
    FutureProvider.family<bool, String>((ref, productId) {
  ref.watch(authStateProvider);
  return ref.watch(reviewRepositoryProvider).hasPurchasedProduct(productId);
});

class ReviewController {
  final Ref ref;
  const ReviewController(this.ref);

  Future<void> submit(String productId, int rating, String? comment) async {
    await ref.read(reviewRepositoryProvider).upsertMyReview(
          productId: productId,
          rating: rating,
          comment: comment,
        );
    ref.invalidate(productReviewsProvider(productId));
    ref.invalidate(myReviewForProductProvider(productId));
  }

  Future<void> delete(String productId, String reviewId) async {
    await ref.read(reviewRepositoryProvider).deleteMyReview(reviewId);
    ref.invalidate(productReviewsProvider(productId));
    ref.invalidate(myReviewForProductProvider(productId));
  }
}

final reviewControllerProvider = Provider<ReviewController>((ref) => ReviewController(ref));
