import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/wishlist_item.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/product_card.dart';
import '../../../shared/widgets/skeleton.dart';
import 'wishlist_providers.dart';

/// The customer's saved products — reachable from [ProfileScreen]'s
/// "Wishlist" tile. Reuses [ProductCard] (with the heart toggle hidden,
/// since a dedicated remove button does that job here).
///
/// Keeps its own local copy of the list (seeded from [myWishlistProvider])
/// so removing an item can drop it from the grid immediately instead of
/// waiting for [myWishlistProvider] to refetch over the network —
/// `wishlistProductIdsProvider` (the heart-toggle source of truth
/// elsewhere) is already optimistic; this mirrors that for the grid view.
class WishlistScreen extends ConsumerStatefulWidget {
  const WishlistScreen({super.key});

  @override
  ConsumerState<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends ConsumerState<WishlistScreen> {
  List<WishlistItem>? _localItems;

  Future<void> _remove(WishlistItem item) async {
    final previous = _localItems;
    setState(() => _localItems?.removeWhere((i) => i.id == item.id));
    try {
      await ref.read(wishlistControllerProvider).toggle(item.productId, true);
    } catch (e) {
      // Revert and let the user know — the network call is the source of
      // truth, the optimistic removal was only a guess.
      if (mounted) {
        setState(() => _localItems = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove from wishlist: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wishlistAsync = ref.watch(myWishlistProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(title: const Text('Wishlist')),
      body: wishlistAsync.when(
        data: (fetched) {
          // Seed local state once from the first successful fetch, then
          // never overwrite it from a later background refetch — a
          // slower-arriving fetch (e.g. still in flight when the user
          // taps remove) would otherwise silently re-add an item the
          // user just removed locally.
          _localItems ??= List.of(fetched);

          final items = _localItems!;
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
                    child: Tooltip(
                      message: 'Remove from wishlist',
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _remove(item),
                          // 10px padding + 16px icon = 36px tap target
                          // (was 6px padding = 28px) — a full 44px circle
                          // would visually overwhelm this small grid-card
                          // corner badge, so this is a practical middle
                          // ground rather than strict compliance.
                          child: Container(
                            padding: const EdgeInsets.all(10),
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
                  ),
                ],
              );
            },
          );
        },
        loading: () => const ProductGridSkeleton(),
        error: (e, _) => ErrorState(onRetry: () => ref.invalidate(myWishlistProvider)),
      ),
    );
  }
}
