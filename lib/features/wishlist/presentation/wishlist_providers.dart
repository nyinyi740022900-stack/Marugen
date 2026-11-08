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
  final _desired = <String, bool>{};
  bool isUpdating(String productId) => _pendingIds.contains(productId);

  @override
  AsyncValue<Set<String>> build() {
    ref.watch(currentUserIdProvider);
    _generation++;
    _pendingIds.clear();
    _desired.clear();
    ref.onDispose(() {
      _generation++;
      _pendingIds.clear();
      _desired.clear();
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

  /// Flips the heart immediately and syncs in the background.
  ///
  /// Interruptible: tapping again while a request is still in flight is
  /// not ignored — the icon flips back at once, and only the customer's
  /// final choice is sent once the current request finishes.
  Future<void> toggle(String productId, bool currentlyFavorited) async {
    final current = state.valueOrNull;
    if (current == null) throw StateError('Wishlist is not loaded yet');
    final wanted = !currentlyFavorited;
    state = AsyncData(_with(current, productId, wanted));
    if (_pendingIds.contains(productId)) {
      _desired[productId] = wanted;
      return;
    }

    final generation = _generation;
    _pendingIds.add(productId);
    // What the server holds; starts as what the customer saw before tapping.
    var saved = currentlyFavorited;
    var target = wanted;
    try {
      final repo = ref.read(wishlistRepositoryProvider);
      while (true) {
        if (target != saved) {
          if (target) {
            await repo.add(productId);
          } else {
            await repo.remove(productId);
          }
          saved = target;
        }
        if (generation != _generation) return;
        final next = _desired.remove(productId);
        if (next == null || next == saved) break;
        target = next;
      }
    } catch (_) {
      // Revert only this product to what the server holds; unrelated
      // successful updates stay intact.
      if (generation == _generation) {
        _desired.remove(productId);
        state = AsyncData(_with({...?state.valueOrNull}, productId, saved));
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

  static Set<String> _with(Set<String> ids, String productId, bool present) {
    final next = {...ids};
    if (present) {
      next.add(productId);
    } else {
      next.remove(productId);
    }
    return next;
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
