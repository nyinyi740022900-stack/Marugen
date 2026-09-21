import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/paged_notifier.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/reviewer_identity.dart';
import '../../reviews/data/review_repository.dart';
import '../../reviews/presentation/review_providers.dart';
import '../../../shared/models/review.dart';

/// Paged (infinite-scroll) admin reviews list — see PagedNotifier and
/// AdminOrdersPagedNotifier (orders_providers.dart) for the same pattern.
/// No search/filter exists on this screen, so (unlike Orders/Products)
/// there's no unbounded-fallback branch to also maintain.
class AdminReviewsPagedNotifier extends PagedNotifier<ProductReview> {
  @override
  Future<List<ProductReview>> fetchPage(int offset, int limit) {
    return ref.read(reviewRepositoryProvider).fetchAllReviewsForAdminPage(
          offset: offset,
          limit: limit,
        );
  }
}

final adminReviewsPagedProvider =
    NotifierProvider<AdminReviewsPagedNotifier, AsyncValue<PagedListState<ProductReview>>>(
        AdminReviewsPagedNotifier.new);

/// Moderate customer reviews — hide abusive ones from the public shop,
/// and reply publicly to any review (Amazon/Shopee/Lazada/Google Business
/// all let a seller respond once under a review — see 0031_review_shop_
/// reply.sql).
class AdminReviewsScreen extends ConsumerStatefulWidget {
  const AdminReviewsScreen({super.key});

  @override
  ConsumerState<AdminReviewsScreen> createState() => _AdminReviewsScreenState();
}

class _AdminReviewsScreenState extends ConsumerState<AdminReviewsScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.attachPagination(
      () => ref.read(adminReviewsPagedProvider.notifier).loadNextPage(),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reviewsAsync = ref.watch(adminReviewsPagedProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: reviewsAsync.when(
        data: (paged) {
          if (paged.items.isEmpty) {
            return const EmptyState(
              icon: Icons.star_border,
              title: 'No reviews yet',
              subtitle: 'Customer reviews will show up here once orders are delivered.',
            );
          }
          return ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: paged.items.length + (paged.hasMore ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i >= paged.items.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.red, strokeWidth: 2),
                  ),
                );
              }
              return _AdminReviewCard(review: paged.items[i]);
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.red),
        ),
        error: (e, _) => ErrorState(
          onRetry: () => ref.read(adminReviewsPagedProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

class _AdminReviewCard extends ConsumerStatefulWidget {
  final ProductReview review;
  const _AdminReviewCard({required this.review});

  @override
  ConsumerState<_AdminReviewCard> createState() => _AdminReviewCardState();
}

class _AdminReviewCardState extends ConsumerState<_AdminReviewCard> {
  bool _replying = false;
  late final _replyCtrl = TextEditingController(text: widget.review.shopReply);
  bool _saving = false;

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveReply() async {
    setState(() => _saving = true);
    try {
      await ReviewRepository().setShopReply(widget.review.id, _replyCtrl.text);
      ref.read(adminReviewsPagedProvider.notifier).refresh();
      // Was missing entirely — the customer-facing product page watches
      // this family provider, not the admin list, so a reply never
      // showed up there until something else happened to invalidate it.
      ref.invalidate(productReviewsProvider(widget.review.productId));
      if (mounted) setState(() => _replying = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save reply: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final hasReply = review.shopReply != null && review.shopReply!.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReviewerAvatar(
                  fullName: review.authorName,
                  avatarUrl: review.authorAvatarUrl,
                  radius: 15,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    maskedReviewerName(review.authorName),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (review.isHidden)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.redSoft,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: const Text('Hidden',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.redDark)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${'★' * review.rating}${'☆' * (5 - review.rating)}  ·  ${DateFormat.yMMMd().format(review.createdAt)}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
            ),
            if (review.comment != null && review.comment!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(review.comment!, style: const TextStyle(fontSize: 13.5)),
            ],
            if (hasReply && !_replying) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.offWhite,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border(left: BorderSide(color: AppColors.red.withValues(alpha: 0.4), width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your reply',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(review.shopReply!, style: const TextStyle(fontSize: 13, height: 1.35)),
                  ],
                ),
              ),
            ],
            if (_replying) ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _replyCtrl,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Write a public reply…',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                              _replying = false;
                              _replyCtrl.text = review.shopReply ?? '';
                            }),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: _saving ? null : _saveReply,
                    child: _saving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                          )
                        : const Text('Post Reply'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_replying)
                  TextButton(
                    onPressed: () => setState(() => _replying = true),
                    child: Text(hasReply ? 'Edit Reply' : 'Reply'),
                  ),
                TextButton(
                  onPressed: () async {
                    await ReviewRepository().setHidden(review.id, !review.isHidden);
                    ref.read(adminReviewsPagedProvider.notifier).refresh();
                    // Same gap _saveReply had above: the customer-facing
                    // product page watches this family provider, not the
                    // admin list, so hiding/unhiding never showed up there
                    // until something else happened to invalidate it.
                    ref.invalidate(productReviewsProvider(review.productId));
                  },
                  child: Text(review.isHidden ? 'Unhide' : 'Hide'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
