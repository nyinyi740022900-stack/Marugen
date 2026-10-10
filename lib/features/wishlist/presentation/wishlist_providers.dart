import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/wishlist_item.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/wishlist_repository.dart';

final wishlistRepositoryProvider = Provider<WishlistRepository>(
  (ref) => WishlistRepository(),
);

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
  int _generation = 0;
  final _pendingIds = <String>{};
  bool isUpdating(String productId) => _pendingIds.contains(productId);

  @override
  AsyncValue<Set<String>> build() {
    ref.watch(currentUserIdProvider);
    _generation++;
    _pendingIds.clear();
    ref.onDispose(() {
      _generation++;
      _pendingIds.clear();
    });
    _load();
    return const AsyncLoading();
  }

  Future<void> _load() async {
    final generation = _generation;
    try {
      final ids = await ref
          .read(wishlistRepositoryProvider)
          .fetchMyWishlistProductIds();
      if (generation == _generation) state = AsyncData(ids);
    } catch (e, st) {
      if (generation == _generation) state = AsyncError(e, st);
    }
  }

  Future<void> toggle(String productId, bool currentlyFavorited) async {
    if (_pendingIds.contains(productId)) return;
    final current = state.valueOrNull;
    if (current == null) throw StateError('Wishlist is not loaded yet');
    final generation = _generation;
    _pendingIds.add(productId);
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
      // Revert only this product; unrelated successful updates stay intact.
      if (generation == _generation) {
        final restored = {...?state.valueOrNull};
        if (currentlyFavorited) {
          restored.add(productId);
        } else {
          restored.remove(productId);
        }
        state = AsyncData(restored);
      }
      rethrow;
    } finally {
      if (generation == _generation) {
        _pendingIds.remove(productId);
        final latest = state.valueOrNull;
        if (latest != null) state = AsyncData(Set.of(latest));
      }
    }
  }
}

final wishlistProductIdsProvider =
    NotifierProvider<WishlistIdsNotifier, AsyncValue<Set<String>>>(
      WishlistIdsNotifier.new,
    );

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

final wishlistControllerProvider = Provider<WishlistController>(
  (ref) => WishlistController(ref),
);
