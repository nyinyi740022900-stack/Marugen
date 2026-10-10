import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../cart/domain/cart_item.dart';
import '../../cart/presentation/cart_providers.dart';

/// Only recognized local destinations may survive authentication.
String? safeLocalRedirect(String? value) {
  if (value == null || value.contains('\\')) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority || uri.hasFragment) {
    return null;
  }
  final path = uri.path;
  if (!['/', '/checkout', '/cart', '/notifications', '/admin'].contains(path) &&
      !RegExp(r'^/(product|orders)/[^/]+$').hasMatch(path) &&
      !RegExp(r'^/admin/(customers|products)/[^/]+$').hasMatch(path) &&
      !['/admin/low-stock', '/admin/top-products'].contains(path)) {
    return null;
  }
  return uri.toString();
}

String authRouteWithRedirect(String route, String? redirect) {
  final safe = safeLocalRedirect(redirect);
  return safe == null
      ? route
      : Uri(path: route, queryParameters: {'redirect': safe}).toString();
}

bool checkoutCanPay({
  required bool hasItems,
  required bool hasAddress,
  required bool totalsReady,
  required bool promoLoading,
  required bool processing,
}) => hasItems && hasAddress && totalsReady && !promoLoading && !processing;

class PurchaseIntent {
  final String id;
  final String? ownerId;
  final List<CartItem> items;
  PurchaseIntent({
    required this.id,
    required this.ownerId,
    required List<CartItem> items,
  }) : items = List.unmodifiable(items);
}

/// Kept in memory only. Guest selections bind to the first sign-in and are
/// discarded on subsequent account changes. Never copied into an account cart.
class PurchaseIntentNotifier extends Notifier<PurchaseIntent?> {
  int _sequence = 0;
  @override
  PurchaseIntent? build() {
    ref.listen(currentUserIdProvider, (previous, next) {
      final intent = state;
      if (intent == null || previous == next) return;
      if (intent.ownerId == null && previous == null && next != null) {
        state = PurchaseIntent(
          id: intent.id,
          ownerId: next,
          items: intent.items,
        );
      } else {
        state = null;
      }
    });
    return null;
  }

  String start(List<CartItem> items) {
    final id = '${DateTime.now().microsecondsSinceEpoch}-${++_sequence}';
    state = PurchaseIntent(
      id: id,
      ownerId: ref.read(currentUserIdProvider),
      items: items,
    );
    return id;
  }

  /// A missing/expired token resolves to an empty isolated checkout, never the
  /// current account's cart. An un-tokened cart checkout clears stale intent.
  List<CartItem>? consume(String? id) {
    final items = peek(id);
    if (state != null) state = null;
    return items;
  }

  List<CartItem>? peek(String? id) {
    final intent = state;
    if (id == null) return null;
    final owner = ref.read(currentUserIdProvider);
    if (intent == null ||
        intent.id != id ||
        (intent.ownerId != null && intent.ownerId != owner)) {
      return [];
    }
    return List.of(intent.items);
  }

  void clear() => state = null;
}

final purchaseIntentProvider =
    NotifierProvider<PurchaseIntentNotifier, PurchaseIntent?>(
      PurchaseIntentNotifier.new,
    );

void beginCheckout(
  BuildContext context,
  WidgetRef ref, {
  List<CartItem>? buyNowItems,
}) {
  // Cart Undo must never change a purchase already in progress.
  ScaffoldMessenger.maybeOf(context)
    ?..clearSnackBars()
    ..removeCurrentSnackBar();
  final guest = ref.read(currentUserIdProvider) == null;
  final notifier = ref.read(purchaseIntentProvider.notifier);
  final snapshot = buyNowItems ?? (guest ? ref.read(cartProvider) : null);
  String destination = '/checkout';
  if (snapshot != null) {
    final id = notifier.start(snapshot);
    destination = Uri(
      path: '/checkout',
      queryParameters: {'intent': id},
    ).toString();
  } else {
    notifier.clear();
  }
  context.push(
    guest ? authRouteWithRedirect('/login', destination) : destination,
  );
}
