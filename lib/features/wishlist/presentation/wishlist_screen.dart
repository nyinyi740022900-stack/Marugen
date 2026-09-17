import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/product_card.dart';
import '../../../shared/widgets/skeleton.dart';
import 'wishlist_providers.dart';

/// The customer's saved products — reachable from [ProfileScreen]'s
/// "Wishlist" tile. Reuses [ProductCard] (with the heart toggle hidden,
/// since a dedicated remove button does that job here).
class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wishlistAsync = ref.watch(myWishlistProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(title: const Text('Wishlist')),
      body: wishlistAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.favorite_border,
              title: 'Your wishlist is empty',
              subtitle: 'Tap the heart on any product to save it here.',
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 0.6,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              final product = item.product;
              if (product == null) return const SizedBox.shrink();
              return Stack(
                children: [
                  ProductCard(
                    product: product,
                    showFavoriteToggle: false,
                    onTap: () => context.push('/product/${product.id}'),
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () async {
                          await ref
                              .read(wishlistControllerProvider)
                              .toggle(product.id, true);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.black.withValues(alpha: 0.45),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.favorite,
                              size: 16, color: AppColors.red),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
        loading: () => const ProductGridSkeleton(),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
