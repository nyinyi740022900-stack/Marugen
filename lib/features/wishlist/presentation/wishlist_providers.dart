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
///
/// A hand-rolled `Notifier` (same pattern as `CartNotifier` in
/// cart_providers.dart) rather than a plain `FutureProvider`: toggling a
/// heart used to `ref.invalidate` this and wait for a full network
/// refetch before the icon visually updated, which read as laggy/
/// unresponsive on a tap that should feel instant. `toggle()` below
/// flips the cached set immediately and only talks to the network in the
/// background, reverting on failure.
class WishlistIdsNotifier extends Notifier<AsyncValue<Set<String>>> {
  @override
  AsyncValue<Set<String>> build() {
    ref.watch(authStateProvider);
    _load();
    return const AsyncLoading();
  }

  Future<void> _load() async {
    try {
      final ids = await ref.read(wishlistRepositoryProvider).fetchMyWishlistProductIds();
      state = AsyncData(ids);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> toggle(String productId, bool currentlyFavorited) async {
    final current = state.valueOrNull ?? {};
    final optimistic = {...current};
    if (currentlyFavorited) {
      optimistic.remove(productId);
    } else {
      optimistic.add(productId);
    }
    state = AsyncData(optimistic);

    try {
      final repo = ref.read(wishlistRepositoryProvider);
      if (currentlyFavorited) {
        await repo.remove(productId);
      } else {
        await repo.add(productId);
      }
    } catch (_) {
      // Revert to the pre-toggle set on failure — the network call is the
      // source of truth, the optimistic flip was only a guess.
      state = AsyncData(current);
      rethrow;
    }
  }
}

final wishlistProductIdsProvider =
    NotifierProvider<WishlistIdsNotifier, AsyncValue<Set<String>>>(
        WishlistIdsNotifier.new);

/// Toggles a product's wishlist membership. Callers (product card /
/// detail) are expected to have already confirmed the user is logged in
/// — guests are prompted to log in instead.
class WishlistController {
  final Ref ref;
  const WishlistController(this.ref);

  Future<void> toggle(String productId, bool currentlyFavorited) async {
    await ref
        .read(wishlistProductIdsProvider.notifier)
        .toggle(productId, currentlyFavorited);
    // myWishlistProvider (full item list, used only by WishlistScreen's
    // grid) still refetches — WishlistScreen itself removes the tapped
    // card from local state immediately, so this lagging behind by a
    // network round-trip doesn't show up as jank there.
    ref.invalidate(myWishlistProvider);
  }
}

final wishlistControllerProvider =
    Provider<WishlistController>((ref) => WishlistController(ref));
