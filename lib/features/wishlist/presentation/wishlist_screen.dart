import '../../../shared/widgets/product_grid.dart';

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
/// Filters pending and completed removals from the backend list
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
  final Set<String> _removedIds = {};
  final Set<String> _pendingIds = {};

  Future<void> _remove(WishlistItem item) async {
    if (_removedIds.contains(item.id)) return;
    final ids = ref.read(wishlistProductIdsProvider);
    if (ids.isLoading ||
        ref
            .read(wishlistProductIdsProvider.notifier)
            .isUpdating(item.productId)) {
      return;
    }
    if (ids.hasError) {
      ref.invalidate(wishlistProductIdsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Reloading your wishlist. Please try removing the item again.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _removedIds.add(item.id);
      _pendingIds.add(item.id);
    });
    try {
      await ref.read(wishlistControllerProvider).toggle(item.productId, true);
      if (mounted) setState(() => _pendingIds.remove(item.id));
    } catch (e) {
      // Revert and let the user know — the network call is the source of
      // truth, the optimistic removal was only a guess.
      if (mounted) {
        setState(() {
          _removedIds.remove(item.id);
          _pendingIds.remove(item.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Could not remove this item. Please try again.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wishlistAsync = ref.watch(myWishlistProvider);
    final idsAsync = ref.watch(wishlistProductIdsProvider);

    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: AppBar(title: const Text('Wishlist')),
      body: wishlistAsync.when(
        data: (fetched) {
          final fetchedIds = fetched.map((item) => item.id).toSet();
          _removedIds.removeWhere(
            (id) => !_pendingIds.contains(id) && !fetchedIds.contains(id),
          );
          final items = fetched
              .where((item) => !_removedIds.contains(item.id))
              .toList();
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.favorite_border,
              title: 'Your wishlist is empty',
              subtitle: 'Tap the heart on any product to save it here.',
            );
          }
          return ProductGrid(
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
                      message: 'Remove ${product.name} from wishlist',
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap:
                              idsAsync.isLoading ||
                                  ref
                                      .read(wishlistProductIdsProvider.notifier)
                                      .isUpdating(item.productId)
                              ? null
                              : () => _remove(item),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.black.withValues(alpha: 0.45),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.favorite,
                              size: 16,
                              color: AppPalette.of(context).accent,
                            ),
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
        error: (e, _) =>
            ErrorState(onRetry: () => ref.invalidate(myWishlistProvider)),
      ),
    );
  }
}
