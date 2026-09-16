import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/wishlist_item.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/wishlist_repository.dart';

final wishlistRepositoryProvider =
    Provider<WishlistRepository>((ref) => WishlistRepository());

final myWishlistProvider = FutureProvider<List<WishlistItem>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(wishlistRepositoryProvider).fetchMyWishlist();
});

/// Just the favorited product ids — used to drive heart toggles on cards
/// and the product detail screen without loading full product rows.
final wishlistProductIdsProvider = FutureProvider<Set<String>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(wishlistRepositoryProvider).fetchMyWishlistProductIds();
});

/// Toggles a product's wishlist membership and refreshes the dependent
/// providers. Callers (product card / detail) are expected to have already
/// confirmed the user is logged in — guests are prompted to log in instead.
class WishlistController {
  final Ref ref;
  const WishlistController(this.ref);

  Future<void> toggle(String productId, bool currentlyFavorited) async {
    final repo = ref.read(wishlistRepositoryProvider);
    if (currentlyFavorited) {
      await repo.remove(productId);
    } else {
      await repo.add(productId);
    }
    ref.invalidate(wishlistProductIdsProvider);
    ref.invalidate(myWishlistProvider);
  }
}

final wishlistControllerProvider =
    Provider<WishlistController>((ref) => WishlistController(ref));
