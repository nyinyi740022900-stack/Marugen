import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/review.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/review_repository.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) => ReviewRepository());

/// Other customers' reviews for a product — left as invalidate-and-
/// refetch (not optimistic) after a submit/delete. A new review needs a
/// server-assigned id/timestamp and a `profiles.full_name` join for the
/// reviewer's display name/avatar (see reviewer_identity.dart) that the
/// client doesn't have cached, so fabricating a placeholder row here
/// risks a duplicate-looking entry until the real fetch lands — this is
/// a background list, not a heart/badge toggle, so the round-trip delay
/// is much less noticeable than it would be there.
final productReviewsProvider =
    FutureProvider.family<List<ProductReview>, String>((ref, productId) {
  return ref.watch(reviewRepositoryProvider).fetchReviewsForProduct(productId);
});

/// The logged-in user's own review on a product, if any — drives whether
/// the product detail screen shows "Write a review" or "Edit your review".
///
/// A hand-rolled `FamilyNotifier` (same optimistic pattern as
/// `WishlistIdsNotifier`/`NotificationsNotifier`): submitting or deleting
/// updates this cached slot immediately instead of waiting on
/// `ref.invalidate` + a full refetch, since this is exactly the "did my
/// tap register" feedback a user watches for after tapping Save/Delete.
class MyReviewNotifier extends FamilyNotifier<AsyncValue<ProductReview?>, String> {
  late final String productId = arg;

  @override
  AsyncValue<ProductReview?> build(String arg) {
    ref.watch(authStateProvider);
    _load();
    return const AsyncLoading();
  }

  Future<void> _load() async {
    try {
      final review = await ref.read(reviewRepositoryProvider).fetchMyReview(productId);
      state = AsyncData(review);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> submit(int rating, String? comment) async {
    final previous = state.valueOrNull;
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');

    // Placeholder id/createdAt until the confirmed row comes back below —
    // good enough for immediate rating/comment display; nothing reads
    // this fake id except this notifier's own follow-up reconciliation.
    state = AsyncData(ProductReview(
      id: previous?.id ?? 'pending',
      productId: productId,
      userId: userId,
      rating: rating,
      comment: comment,
      createdAt: previous?.createdAt ?? DateTime.now(),
      authorName: previous?.authorName,
      isHidden: previous?.isHidden ?? false,
      shopReply: previous?.shopReply,
      shopReplyAt: previous?.shopReplyAt,
    ));

    try {
      final repo = ref.read(reviewRepositoryProvider);
      await repo.upsertMyReview(productId: productId, rating: rating, comment: comment);
      // Reconcile with the real row (server-assigned id/timestamp) rather
      // than leaving the 'pending' placeholder in place indefinitely.
      final confirmed = await repo.fetchMyReview(productId);
      state = AsyncData(confirmed);
    } catch (e) {
      state = AsyncData(previous);
      rethrow;
    } finally {
      ref.invalidate(productReviewsProvider(productId));
    }
  }

  Future<void> delete(String reviewId) async {
    final previous = state.valueOrNull;
    state = const AsyncData(null);
    try {
      await ref.read(reviewRepositoryProvider).deleteMyReview(reviewId);
    } catch (e) {
      state = AsyncData(previous);
      rethrow;
    } finally {
      ref.invalidate(productReviewsProvider(productId));
    }
  }
}

final myReviewForProductProvider =
    NotifierProvider.family<MyReviewNotifier, AsyncValue<ProductReview?>, String>(
        MyReviewNotifier.new);

/// Whether the logged-in user is allowed to review this product, i.e. has
/// a paid-or-later order containing it. Guests are never eligible.
final canReviewProductProvider =
    FutureProvider.family<bool, String>((ref, productId) {
  ref.watch(authStateProvider);
  return ref.watch(reviewRepositoryProvider).hasPurchasedProduct(productId);
});

/// Thin wrapper so callers (reviews_section.dart) don't need to reach
/// into `myReviewForProductProvider(productId).notifier` directly.
class ReviewController {
  final Ref ref;
  const ReviewController(this.ref);

  Future<void> submit(String productId, int rating, String? comment) {
    return ref.read(myReviewForProductProvider(productId).notifier).submit(rating, comment);
  }

  Future<void> delete(String productId, String reviewId) {
    return ref.read(myReviewForProductProvider(productId).notifier).delete(reviewId);
  }
}

final reviewControllerProvider = Provider<ReviewController>((ref) => ReviewController(ref));
