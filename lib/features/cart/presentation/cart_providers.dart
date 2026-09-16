import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/models/product.dart';
import '../../shop/presentation/shop_providers.dart';
import '../domain/cart_item.dart';

/// Local storage key the cart is serialized under (product id + variant id
/// + quantity only — full [Product]/[ProductVariant] data is re-fetched on
/// hydration so stock/price stay in sync with the server instead of going
/// stale on disk).
const _cartPrefsKey = 'cart_items_v1';

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

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() {
    // Notifier.build() is synchronous, so kick the async hydration off in
    // a microtask and populate state once the saved cart (if any) has
    // been re-fetched from Supabase.
    Future.microtask(_hydrate);
    return [];
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cartPrefsKey);
      if (raw == null || raw.isEmpty) return;

      final saved = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      if (saved.isEmpty) return;

      final repo = ref.read(productRepositoryProvider);
      final items = <CartItem>[];
      for (final entry in saved) {
        final productId = entry['product_id'] as String?;
        final variantId = entry['variant_id'] as String?;
        final quantity = entry['quantity'] as int? ?? 1;
        if (productId == null) continue;
        final product = await repo.fetchProductById(productId);
        // Skip items that were deleted, sold out, or hidden since saving.
        if (product == null || product.isSold) continue;
        ProductVariant? variant;
        if (variantId != null) {
          final match = product.variants.where((v) => v.id == variantId);
          // The saved variant no longer exists (removed by admin) — drop
          // this line rather than silently reverting to the base price.
          if (match.isEmpty) continue;
          variant = match.first;
        }
        items.add(CartItem(product: product, quantity: quantity, selectedVariant: variant));
      }
      // Only overwrite if the user hasn't already started shopping while
      // hydration was in flight.
      if (state.isEmpty) {
        state = items;
      }
    } catch (_) {
      // Corrupt/unavailable local storage — just start with an empty cart.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = [
        for (final item in state)
          {
            'product_id': item.product.id,
            'variant_id': item.selectedVariant?.id,
            'quantity': item.quantity,
          },
      ];
      await prefs.setString(_cartPrefsKey, jsonEncode(payload));
    } catch (_) {
      // Non-fatal — cart just won't survive a restart this time.
    }
  }

  /// Units of this line the shop can actually supply — the variant's
  /// stock when one is selected, else the product's.
  static int availableFor(Product product, ProductVariant? variant) =>
      variant?.stockQuantity ?? product.availableStock;

  /// Adds [quantity] units, never exceeding available stock. Returns the
  /// result so the caller can tell the customer when the cap was hit
  /// instead of silently adding fewer than requested.
  CartAddResult add(Product product, {int quantity = 1, ProductVariant? variant}) {
    final key = '${product.id}::${variant?.id ?? ''}';
    final index = state.indexWhere((i) => i.lineKey == key);
    final available = availableFor(product, variant);
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
      return current + quantity > available ? CartAddResult.stockLimit : CartAddResult.added;
    }

    state = [
      ...state,
      CartItem(
        product: product,
        quantity: quantity.clamp(1, available),
        selectedVariant: variant,
      ),
    ];
    _persist();
    return quantity > available ? CartAddResult.stockLimit : CartAddResult.added;
  }

  void remove(String productId, {String? variantId}) {
    state = state
        .where((i) => !(i.product.id == productId && i.selectedVariant?.id == variantId))
        .toList();
    _persist();
  }

  void updateQuantity(String productId, int quantity, {String? variantId}) {
    if (quantity <= 0) {
      remove(productId, variantId: variantId);
      return;
    }
    state = [
      for (final item in state)
        if (item.product.id == productId && item.selectedVariant?.id == variantId)
          item.copyWith(
            quantity: quantity.clamp(
              1,
              // Never let the stepper run past what's in stock.
              availableFor(item.product, item.selectedVariant).clamp(1, 1 << 30),
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
    final repo = ref.read(productRepositoryProvider);
    final kept = <CartItem>[];
    var removed = 0;
    var adjusted = 0;

    for (final item in state) {
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
        if (match.isEmpty || match.first.stockQuantity < 1) {
          removed++;
          continue;
        }
        variant = match.first;
      } else if (product.hasVariants) {
        // Line was saved without a size but the product now requires one.
        removed++;
        continue;
      }

      final available = availableFor(product, variant);
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
      );
      if (refreshed.unitPrice != item.unitPrice) adjusted++;
      kept.add(refreshed);
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

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(CartNotifier.new);

final cartTotalProvider = Provider<double>((ref) {
  final items = ref.watch(cartProvider);
  return items.fold<double>(0, (sum, item) => sum + item.subtotal);
});

final cartCountProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).fold<int>(0, (sum, item) => sum + item.quantity);
});
