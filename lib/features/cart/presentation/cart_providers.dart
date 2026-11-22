import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/product.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../orders/presentation/payment_awaiting.dart' show PurchasedLine;
import '../../shop/presentation/shop_providers.dart';
import '../domain/cart_item.dart';

/// Local storage key the cart is serialized under (product id + variant id
/// + size + quantity only — full [Product]/[ProductVariant] data is
/// re-fetched on hydration so stock/price stay in sync with the server
/// instead of going stale on disk). Scoped per signed-in user (falling
/// back to a shared 'guest' bucket while logged out) — a single global key
/// meant a device shared between two customers (or a demo/testing device)
/// would show whoever logs in next the previous person's cart, letting
/// them unknowingly buy/pay for someone else's items.
String _cartPrefsKey(String? userId) => 'cart_items_v1::${userId ?? 'guest'}';

/// Outcome of [CartNotifier.add] — lets the UI word its snackbar.
enum CartAddResult { added, stockLimit, alreadyInCart, outOfStock }

/// Customer-facing wording for each [CartAddResult], shared by the
/// product card quick-add and the detail screen's Add/Buy buttons.
String cartAddMessage(CartAddResult result) {
  switch (result) {
    case CartAddResult.added:
      return 'Added to cart';
    case CartAddResult.stockLimit:
      return 'Only limited stock left — cart adjusted to what\'s available';
    case CartAddResult.alreadyInCart:
      return 'This fish is already in your cart';
    case CartAddResult.outOfStock:
      return 'Sorry, this item is out of stock';
  }
}

/// Shows the standard "Added to cart" (or stock-limit/already-in-cart/
/// out-of-stock) snackbar — shared by the product card quick-add, the
/// live-fish round button, and the detail screen's Add to Cart, so all
/// three dismiss the same way.
///
/// Belt-and-suspenders auto-dismiss: `SnackBar.duration` alone should be
/// enough, but a customer reported one staying on screen until manually
/// swiped away. Rather than leave that unresolved, this also grabs the
/// controller `showSnackBar` returns and explicitly `.close()`s it after
/// the same duration — a no-op if the bar already dismissed itself, a
/// real fix if something (a rebuild, another snackbar queued mid-flight)
/// was ever eating the automatic timer.
void showCartSnackBar(BuildContext context, CartAddResult result) {
  // Long enough to read and reach "View Cart": the product page has no
  // other confirmation that the item went in.
  const duration = Duration(seconds: 4);
  // Physical confirmation on the same frame as the snackbar: a light tap
  // when the item lands in the cart, a firmer one when it was refused.
  if (result == CartAddResult.added) {
    HapticFeedback.lightImpact();
  } else {
    HapticFeedback.mediumImpact();
  }
  final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
  final controller = messenger.showSnackBar(
    SnackBar(
      content: Text(cartAddMessage(result)),
      duration: duration,
      action: result == CartAddResult.added
          ? SnackBarAction(
              label: 'View Cart',
              textColor: AppColors.white,
              onPressed: () => context.push('/cart'),
            )
          : null,
    ),
  );
  Future.delayed(duration, () {
    try {
      controller.close();
    } catch (_) {
      // Already closed/disposed — nothing to do.
    }
  });
}

class CartNotifier extends Notifier<List<CartItem>> {
  String? _userId;

  @override
  List<CartItem> build() {
    // Re-runs whenever the signed-in user actually changes (login/logout/
    // switch account) — see currentUserIdProvider — discarding whatever
    // was in memory for the previous account and hydrating fresh from
    // that user's own scoped storage key.
    _userId = ref.watch(currentUserIdProvider);
    _unrestored = const [];
    _purchased = {};
    // Notifier.build() is synchronous, so kick the async hydration off in
    // a microtask and populate state once the saved cart (if any) has
    // been re-fetched from Supabase.
    Future.microtask(_hydrate);
    return [];
  }

  /// Saved lines that could not be checked (offline at launch, say). They
  /// stay in storage with the cart instead of being overwritten by the next
  /// change, and come back on a later launch.
  List<Map<String, dynamic>> _unrestored = const [];

  /// What a confirmed payment bought (see [removePurchased]) that a saved
  /// cart still being restored must not bring back, by line key: the units
  /// to take off the restored line, or null for the whole line.
  Map<String, int?> _purchased = {};

  /// [quantity] less the [bought] units; null (the whole line) leaves none.
  static int _remainder(int quantity, int? bought) =>
      bought == null || bought >= quantity ? 0 : quantity - bought;

  static String _lineKey(String productId, String? variantId, String? size) =>
      '$productId::${variantId ?? ''}::${size ?? ''}';

  Future<void> _hydrate() async {
    final userId = _userId;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = _savedLines(prefs, userId);
      // A guest's cart joins the account they sign in to.
      final guest = userId == null
          ? const <Map<String, dynamic>>[]
          : _savedLines(prefs, null);
      if (saved.isEmpty && guest.isEmpty) return;

      final repo = ref.read(productRepositoryProvider);
      final items = <CartItem>[];
      final unrestored = <Map<String, dynamic>>[];
      for (final entry in [...saved, ...guest]) {
        final productId = entry['product_id'] as String?;
        final variantId = entry['variant_id'] as String?;
        final sizeLabel = entry['size_label'] as String?;
        final quantity = entry['quantity'] as int? ?? 1;
        if (productId == null) continue;
        // Bought outright: not worth fetching. A part-bought line is cut
        // down below, once, when the restored lines join the cart.
        final key = _lineKey(productId, variantId, sizeLabel);
        if (_purchased.containsKey(key) && _purchased[key] == null) continue;
        final Product? product;
        try {
          product = await repo.fetchProductById(productId);
        } catch (_) {
          unrestored.add(entry);
          continue;
        }
        // Skip items that were deleted, sold out, or went out of stock while
        // the app was closed — mirrors the check in refreshFromServer() so a
        // restored cart never briefly shows a phantom in-stock line.
        if (product == null ||
            product.isSold ||
            !product.isPurchasable ||
            product.isOutOfStock) {
          continue;
        }
        ProductVariant? variant;
        if (variantId != null) {
          final match = product.variants.where((v) => v.id == variantId);
          // The saved variant no longer exists (removed by admin) — drop
          // this line rather than silently reverting to the base price.
          if (match.isEmpty) continue;
          variant = match.first;
        }
        if (product.hasSizeOptions) {
          if (sizeLabel == null || !product.sizeOptions.contains(sizeLabel)) {
            continue;
          }
        }
        final item = CartItem(
          product: product,
          quantity: quantity,
          selectedVariant: variant,
          selectedSize: product.hasSizeOptions ? sizeLabel : null,
        );
        if (items.any((i) => i.lineKey == item.lineKey)) continue;
        items.add(item);
      }
      // Fetching each product is several awaits deep: a fast logout/login
      // in the meantime must not land the previous account's items here.
      if (_userId != userId) return;
      _unrestored = unrestored;
      // Lines added while this ran stay; restored ones join them, except
      // any a payment confirmed meanwhile.
      state = [
        ...state,
        for (final item in items)
          if (!state.any((s) => s.lineKey == item.lineKey))
            if (!_purchased.containsKey(item.lineKey))
              item
            else if (_remainder(item.quantity, _purchased[item.lineKey]) > 0)
              item.copyWith(
                quantity: _remainder(item.quantity, _purchased[item.lineKey]),
              ),
      ];
      // Store the combined cart: lines added meanwhile were saved alone.
      await _persist();
      if (guest.isNotEmpty) await prefs.remove(_cartPrefsKey(null));
    } catch (_) {
      // Corrupt/unavailable local storage — just start with an empty cart.
    }
  }

  static List<Map<String, dynamic>> _savedLines(
    SharedPreferences prefs,
    String? userId,
  ) {
    final raw = prefs.getString(_cartPrefsKey(userId));
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> _persist() async {
    final userId = _userId;
    // Capture the matching account and lines before any asynchronous work.
    final payload = [
      for (final item in state)
        {
          'product_id': item.product.id,
          'variant_id': item.selectedVariant?.id,
          'size_label': item.selectedSize,
          'quantity': item.quantity,
        },
    ];
    String key(Map<String, dynamic> line) =>
        '${line['product_id']}::${line['variant_id'] ?? ''}::${line['size_label'] ?? ''}';
    final kept = payload.map(key).toSet();
    payload.addAll(_unrestored.where((line) => !kept.contains(key(line))));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cartPrefsKey(userId), jsonEncode(payload));
    } catch (_) {
      // Non-fatal — cart just won't survive a restart this time.
    }
  }

  /// Units of this line the shop can actually supply — weight×size cell
  /// when sizes exist, else the variant's stock, else the product's.
  static int availableFor(
    Product product,
    ProductVariant? variant, {
    String? size,
  }) {
    if (product.hasSizeOptions && variant != null) {
      return product.stockFor(variantId: variant.id, size: size);
    }
    return variant?.stockQuantity ?? product.availableStock;
  }

  /// Adds [quantity] units, never exceeding available stock. Returns the
  /// result so the caller can tell the customer when the cap was hit
  /// instead of silently adding fewer than requested.
  CartAddResult add(
    Product product, {
    int quantity = 1,
    ProductVariant? variant,
    String? size,
  }) {
    final selectedSize = product.hasSizeOptions ? size : null;
    final key = '${product.id}::${variant?.id ?? ''}::${selectedSize ?? ''}';
    final index = state.indexWhere((i) => i.lineKey == key);
    final available = availableFor(product, variant, size: selectedSize);
    if (available <= 0) return CartAddResult.outOfStock;

    if (index >= 0) {
      // Live fish (koi/arowana) are single-stock — never stack quantity.
      if (product.isLiveFish) return CartAddResult.alreadyInCart;
      final current = state[index].quantity;
      if (current >= available) return CartAddResult.stockLimit;
      final updated = [...state];
      updated[index] = updated[index].copyWith(
        quantity: (current + quantity).clamp(1, available),
      );
      state = updated;
      _persist();
      return current + quantity > available
          ? CartAddResult.stockLimit
          : CartAddResult.added;
    }

    state = [
      ...state,
      CartItem(
        product: product,
        quantity: quantity.clamp(1, available),
        selectedVariant: variant,
        selectedSize: selectedSize,
      ),
    ];
    _persist();
    return quantity > available
        ? CartAddResult.stockLimit
        : CartAddResult.added;
  }

  void remove(String productId, {String? variantId, String? size}) {
    state = state
        .where(
          (i) =>
              !(i.product.id == productId &&
                  i.selectedVariant?.id == variantId &&
                  i.selectedSize == size),
        )
        .toList();
    _persist();
  }

  /// Takes what a server-confirmed payment bought out of the cart: the
  /// purchased quantity comes off each line, and a line with nothing left
  /// is removed (units added while the payment was being confirmed stay).
  /// A purchase without a quantity takes the whole line. Applies also when
  /// the saved cart is still being restored (a payment confirmed on the
  /// launch after the app was closed), and to the lines that could not be
  /// checked yet.
  void removePurchased(Iterable<PurchasedLine> lines) {
    final bought = <String, int?>{};
    for (final line in lines) {
      final key = _lineKey(line.productId, line.variantId, line.size);
      final quantity = line.quantity;
      final already = bought[key];
      bought[key] =
          quantity == null || (bought.containsKey(key) && already == null)
          ? null
          : (already ?? 0) + quantity;
    }
    if (bought.isEmpty) return;

    var changed = false;
    final inMemory = <String>{};
    final kept = <CartItem>[];
    for (final item in state) {
      if (!bought.containsKey(item.lineKey)) {
        kept.add(item);
        continue;
      }
      changed = true;
      inMemory.add(item.lineKey);
      final left = _remainder(item.quantity, bought[item.lineKey]);
      if (left > 0) kept.add(item.copyWith(quantity: left));
    }
    final unrestored = <Map<String, dynamic>>[];
    for (final line in _unrestored) {
      final key = _lineKey(
        line['product_id'] as String? ?? '',
        line['variant_id'] as String?,
        line['size_label'] as String?,
      );
      if (!bought.containsKey(key)) {
        unrestored.add(line);
        continue;
      }
      // The same line in the cart already answered for the purchase; this
      // unchecked copy of it goes.
      if (inMemory.contains(key)) continue;
      changed = true;
      inMemory.add(key);
      final left = _remainder(line['quantity'] as int? ?? 1, bought[key]);
      if (left > 0) unrestored.add({...line, 'quantity': left});
    }
    // For a cart still being restored: a line dealt with above must not
    // come back from storage at all, the others lose what was bought.
    _purchased = {
      ..._purchased,
      for (final entry in bought.entries)
        entry.key: inMemory.contains(entry.key) ? null : entry.value,
    };
    if (!changed) {
      // Nothing of it in memory: restoring (if still running) takes it off
      // the saved lines and saves the result itself.
      return;
    }
    _unrestored = unrestored;
    state = kept;
    _persist();
  }

  /// Undo a removal without touching newer edits or a different account.
  bool restoreRemoved(CartItem item, {required String? ownerId}) {
    if (_userId != ownerId || state.any((i) => i.lineKey == item.lineKey)) {
      return false;
    }
    final available = availableFor(
      item.product,
      item.selectedVariant,
      size: item.selectedSize,
    );
    if (available <= 0) return false;
    state = [
      ...state,
      item.copyWith(quantity: item.quantity.clamp(1, available)),
    ];
    _persist();
    return true;
  }

  void updateQuantity(
    String productId,
    int quantity, {
    String? variantId,
    String? size,
  }) {
    if (quantity <= 0) {
      remove(productId, variantId: variantId, size: size);
      return;
    }
    state = [
      for (final item in state)
        if (item.product.id == productId &&
            item.selectedVariant?.id == variantId &&
            item.selectedSize == size)
          item.copyWith(
            quantity: quantity.clamp(
              1,
              // Never let the stepper run past what's in stock.
              availableFor(
                item.product,
                item.selectedVariant,
                size: item.selectedSize,
              ).clamp(1, 1 << 30),
            ),
          )
        else
          item,
    ];
    _persist();
  }

  void clear() {
    state = [];
    _persist();
  }

  /// Re-fetch every line from Supabase and drop/adjust sold-out or
  /// over-qty items. Call before payment so the client matches server
  /// stock/price (server still recalculates the charged total).
  Future<CartRefreshResult> refreshFromServer() async {
    if (state.isEmpty) {
      return const CartRefreshResult(removed: 0, adjusted: 0, isEmpty: true);
    }
    final userId = _userId;
    final startingItems = state;
    final repo = ref.read(productRepositoryProvider);
    final kept = <CartItem>[];
    var removed = 0;
    var adjusted = 0;

    for (final item in startingItems) {
      final product = await repo.fetchProductById(item.product.id);
      if (product == null ||
          product.isSold ||
          !product.isPurchasable ||
          product.isOutOfStock) {
        removed++;
        continue;
      }

      ProductVariant? variant = item.selectedVariant;
      if (variant != null) {
        final match = product.variants.where((v) => v.id == variant!.id);
        if (match.isEmpty) {
          removed++;
          continue;
        }
        variant = match.first;
      } else if (product.hasVariants) {
        // Line was saved without a size but the product now requires one.
        removed++;
        continue;
      }

      String? size = item.selectedSize;
      if (product.hasSizeOptions) {
        if (size == null || !product.sizeOptions.contains(size)) {
          removed++;
          continue;
        }
      } else {
        size = null;
      }

      final available = availableFor(product, variant, size: size);
      if (available < 1) {
        removed++;
        continue;
      }

      var qty = product.isLiveFish ? 1 : item.quantity;
      if (qty > available) {
        qty = available;
        adjusted++;
      }

      final refreshed = CartItem(
        product: product,
        quantity: qty,
        selectedVariant: variant,
        selectedSize: size,
      );
      if (refreshed.unitPrice != item.unitPrice) adjusted++;
      kept.add(refreshed);
    }

    // A late stock response must never undo newer edits or cross accounts.
    if (_userId != userId ||
        ref.read(currentUserIdProvider) != userId ||
        !identical(state, startingItems)) {
      return CartRefreshResult(removed: 0, adjusted: 0, isEmpty: state.isEmpty);
    }
    state = kept;
    await _persist();
    return CartRefreshResult(
      removed: removed,
      adjusted: adjusted,
      isEmpty: kept.isEmpty,
    );
  }
}

/// Outcome of [CartNotifier.refreshFromServer].
class CartRefreshResult {
  final int removed;
  final int adjusted;
  final bool isEmpty;

  const CartRefreshResult({
    required this.removed,
    required this.adjusted,
    required this.isEmpty,
  });

  bool get changed => removed > 0 || adjusted > 0;
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);

final cartTotalProvider = Provider<double>((ref) {
  final items = ref.watch(cartProvider);
  return items.fold<double>(0, (sum, item) => sum + item.subtotal);
});

final cartCountProvider = Provider<int>((ref) {
  return ref
      .watch(cartProvider)
      .fold<int>(0, (sum, item) => sum + item.quantity);
});
