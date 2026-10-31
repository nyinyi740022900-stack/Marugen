import '../../orders/presentation/purchase_intent.dart'
    show authRouteWithRedirect;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/review.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/reviewer_identity.dart';
import '../../auth/presentation/auth_providers.dart';
import 'review_providers.dart';

/// "REVIEWS" section on the product detail screen: average rating + count,
/// the current user's write/edit affordance, and the list of everyone
/// else's reviews.
class ReviewsSection extends ConsumerWidget {
  final String productId;
  const ReviewsSection({super.key, required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(productReviewsProvider(productId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'REVIEWS',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.8,
            color: AppPalette.of(context).textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _MyReviewCard(productId: productId),
        const SizedBox(height: AppSpacing.md),
        reviewsAsync.when(
          data: (reviews) {
            if (reviews.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppPalette.of(context).surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: AppShadows.card,
                ),
                child: Text(
                  'No reviews yet.',
                  style: TextStyle(
                    color: AppPalette.of(context).textMuted,
                    fontSize: 13.5,
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final review in reviews)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _ReviewTile(review: review),
                  ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => InlineErrorState(
            message:
                "We couldn't load reviews. Check your connection and retry.",
            onRetry: () => ref.invalidate(productReviewsProvider(productId)),
          ),
        ),
      ],
    );
  }
}

/// Average rating + count — placed near the price by [ProductDetailScreen].
class ReviewSummary extends ConsumerWidget {
  final String productId;
  const ReviewSummary({super.key, required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(productReviewsProvider(productId));
    return reviewsAsync.maybeWhen(
      data: (reviews) {
        if (reviews.isEmpty) return const SizedBox.shrink();
        final avg =
            reviews.map((r) => r.rating).reduce((a, b) => a + b) /
            reviews.length;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(Icons.star, size: 16, color: AppPalette.of(context).warning),
              const SizedBox(width: 4),
              Text(
                avg.toStringAsFixed(1),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${reviews.length} review${reviews.length == 1 ? '' : 's'})',
                style: TextStyle(
                  color: AppPalette.of(context).textMuted,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _MyReviewCard extends ConsumerWidget {
  final String productId;
  const _MyReviewCard({required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(isLoggedInProvider);

    if (!isLoggedIn) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppPalette.of(context).surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Log in to write a review.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppPalette.of(context).textMuted,
                ),
              ),
            ),
            TextButton(
              onPressed: () => context.push(
                authRouteWithRedirect('/login', '/product/$productId'),
              ),
              child: const Text('Log In'),
            ),
          ],
        ),
      );
    }

    final myReviewAsync = ref.watch(myReviewForProductProvider(productId));
    final canReviewAsync = ref.watch(canReviewProductProvider(productId));
    return myReviewAsync.when(
      data: (myReview) {
        if (myReview == null) {
          // Verified-purchase gate: only customers with a delivered order
          // containing this product get the form. The database enforces
          // the same rule (0075_reviews_after_delivery.sql); this just
          // explains it instead of letting the insert fail.
          final canReview = canReviewAsync.valueOrNull;
          if (canReview == null) {
            return const SizedBox(
              height: 44,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          if (!canReview) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppPalette.of(context).surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: AppShadows.card,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.verified_outlined,
                    size: 18,
                    color: AppPalette.of(context).textMuted,
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'You can review this item once your order with it has been delivered.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppPalette.of(context).textMuted,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  openReviewForm(context, ref, productId, existing: null),
              icon: const Icon(Icons.star_border, size: 18),
              label: const Text('Write a Review'),
            ),
          );
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppPalette.of(context).surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Your review',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => openReviewForm(
                      context,
                      ref,
                      productId,
                      existing: myReview,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: AppPalette.of(context).error,
                    ),
                    onPressed: () async {
                      final confirmed = await confirmDestructiveAction(
                        context,
                        title: 'Delete review?',
                        message: 'This cannot be undone.',
                      );
                      if (confirmed) {
                        await ref
                            .read(reviewControllerProvider)
                            .delete(productId, myReview.id);
                      }
                    },
                  ),
                ],
              ),
              _StarRow(rating: myReview.rating),
              if (myReview.comment != null && myReview.comment!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  myReview.comment!,
                  style: const TextStyle(fontSize: 13.5, height: 1.4),
                ),
              ],
            ],
          ),
        );
      },
      loading: () => const SizedBox(
        height: 44,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}

/// Opens the write/edit-review bottom sheet for [productId] — the only
/// context it needs is the product id itself (rating/comment are entered
/// fresh, or pre-filled from [existing]), so this is reusable from
/// anywhere a "write a review" affordance makes sense: the product detail
/// page (via [_MyReviewCard] above) and, per delivered order items, the
/// order detail screen (order_detail_screen.dart) — a customer can leave
/// a review right from their order history without navigating back to
/// find the product page again.
void openReviewForm(
  BuildContext context,
  WidgetRef ref,
  String productId, {
  ProductReview? existing,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ReviewForm(productId: productId, existing: existing),
  );
}

class _ReviewForm extends ConsumerStatefulWidget {
  final String productId;
  final ProductReview? existing;
  const _ReviewForm({required this.productId, this.existing});

  @override
  ConsumerState<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends ConsumerState<_ReviewForm> {
  late int _rating = widget.existing?.rating ?? 5;
  late final _commentCtrl = TextEditingController(
    text: widget.existing?.comment,
  );
  bool _saving = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(reviewControllerProvider)
          .submit(
            widget.productId,
            _rating,
            _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Your review was not saved. Check your connection and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null ? 'Write a Review' : 'Edit Your Review',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: () => setState(() => _rating = i),
                    icon: Icon(
                      i <= _rating ? Icons.star : Icons.star_border,
                      color: AppPalette.of(context).warning,
                      size: 32,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _commentCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Comment (optional)',
              hintText: 'Tell others what you thought…',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.white,
                    ),
                  )
                : const Text('Save Review'),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final ProductReview review;
  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppPalette.of(context).surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReviewerAvatar(
                fullName: review.authorName,
                avatarUrl: review.authorAvatarUrl,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      maskedReviewerName(review.authorName),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _StarRow(rating: review.rating),
                        const SizedBox(width: AppSpacing.sm),
                        const _VerifiedBadge(),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                DateFormat.yMMMd().format(review.createdAt),
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppPalette.of(context).textMuted,
                ),
              ),
            ],
          ),
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.comment!,
              style: const TextStyle(fontSize: 13.5, height: 1.4),
            ),
          ],
          if (review.shopReply != null && review.shopReply!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppPalette.of(context).background,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border(
                  left: BorderSide(
                    color: AppPalette.of(context).accent.withValues(alpha: 0.4),
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reply from Marugen Fish Farm',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    review.shopReply!,
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Verified Purchase" pill. Every review is verified by construction
/// (the insert policy requires a paid order), so this is purely the trust
/// signal shoppers expect to see next to a rating.
class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppPalette.of(context).success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: 11, color: AppPalette.of(context).success),
          SizedBox(width: 3),
          Text(
            'Verified Purchase',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppPalette.of(context).success,
            ),
          ),
        ],
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  final int rating;
  const _StarRow({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating ? Icons.star : Icons.star_border,
            size: 16,
            color: AppPalette.of(context).warning,
          ),
      ],
    );
  }
}
