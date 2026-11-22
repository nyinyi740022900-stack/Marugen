import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../features/cart/presentation/cart_providers.dart';

/// App-bar route to the cart with the item count on it — on the Shop and on
/// the product page, the only place an item is added from.
///
/// Isolated so only this small badge rebuilds when [cartCountProvider]
/// changes, not the screen whose app bar it sits in.
class CartBadgeButton extends ConsumerWidget {
  const CartBadgeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartCount = ref.watch(cartCountProvider);
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          tooltip: 'Open cart',
          icon: const Icon(Icons.shopping_bag_outlined),
          onPressed: () => context.push('/cart'),
        ),
        if (cartCount > 0)
          Positioned(
            right: 8,
            top: 8,
            // The count is read out with the button, not as a stray number.
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: AppColors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  '$cartCount',
                  textAlign: TextAlign.center,
                  semanticsLabel: '$cartCount in cart',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
