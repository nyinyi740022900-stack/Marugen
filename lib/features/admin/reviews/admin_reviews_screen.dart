import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/review.dart';
import '../../reviews/data/review_repository.dart';
import '../../reviews/presentation/review_providers.dart';

final adminReviewsProvider = FutureProvider<List<ProductReview>>((ref) {
  return ref.watch(reviewRepositoryProvider).fetchAllReviewsForAdmin();
});

/// Moderate customer reviews — hide abusive ones from the public shop.
class AdminReviewsScreen extends ConsumerWidget {
  const AdminReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(adminReviewsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: reviewsAsync.when(
        data: (reviews) {
          if (reviews.isEmpty) {
            return const Center(
              child: Text('No reviews yet.', style: TextStyle(color: AppColors.grey)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: reviews.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final review = reviews[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              review.authorName ?? 'Customer',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (review.isHidden)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.redSoft,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                              ),
                              child: const Text('Hidden',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.redDark)),
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
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () async {
                            await ReviewRepository()
                                .setHidden(review.id, !review.isHidden);
                            ref.invalidate(adminReviewsProvider);
                          },
                          child: Text(review.isHidden ? 'Unhide' : 'Hide'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
