import '../../../shared/widgets/sized_network_image.dart';

import 'package:flutter/material.dart';

import '../../../shared/widgets/content_width.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/price_format.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/undo_snack_bar.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../orders/presentation/purchase_intent.dart';
import '../domain/cart_item.dart';
import 'cart_providers.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  void _removeWithUndo(CartItem item) {
    final ownerId = ref.read(currentUserIdProvider);
    ref
        .read(cartProvider.notifier)
        .remove(
          item.product.id,
          variantId: item.selectedVariant?.id,
          size: item.selectedSize,
        );
    showUndoSnackBar(
      ScaffoldMessenger.of(context),
      message: 'Removed ${item.product.name}',
      onAction: () {
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
        final restored = ref
            .read(cartProvider.notifier)
            .restoreRemoved(item, ownerId: ownerId);
        if (!restored) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your cart has changed. Add this item from the shop if needed.',
              ),
            ),
          );
        }
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // Cart lines were previously only revalidated against live stock/price
    // at checkout — a shopper who added an item, left it in cart for a
    // while, and came back could keep incrementing quantity on something
    // that had since sold out with no indication until the checkout step.
    // Revalidating on open surfaces that immediately instead.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final result = await ref.read(cartProvider.notifier).refreshFromServer();
      if (!mounted || !result.changed) return;
      final message = result.removed > 0 && result.adjusted > 0
          ? '${result.removed} item(s) sold out and ${result.adjusted} adjusted for stock/price changes'
          : result.removed > 0
          ? '${result.removed} item(s) removed — no longer available'
          : '${result.adjusted} item(s) adjusted for stock/price changes';
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);

    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: AppBar(title: const Text('Cart')),
      body: ContentWidth(
        maxWidth: 760,
        child: items.isEmpty
            ? EmptyState(
                icon: Icons.shopping_bag_outlined,
                title: 'Your cart is empty',
                subtitle: 'Browse the shop to add koi, fish & supplies.',
                actionLabel: 'Browse shop',
                onAction: () {
                  // Pop back to the customer shell shop tab when possible.
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/');
                  }
                },
              )
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, i) {
                  final item = items[i];
                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppPalette.of(context).surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      boxShadow: AppShadows.card,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              child: SizedBox(
                                width: 60,
                                height: 60,
                                child: item.product.imageUrls.isNotEmpty
                                    ? SizedNetworkImage(
                                        imageUrl: item.product.imageUrls.first,
                                        fit: BoxFit.cover,
                                        placeholder: (_, _) => Container(
                                          color: AppPalette.of(context)
                                              .background,
                                        ),
                                        errorWidget: (_, _, _) => Container(
                                          color: AppPalette.of(context)
                                              .background,
                                          child: Icon(
                                            Icons.image_not_supported_outlined,
                                            color: AppPalette.of(context)
                                                .textMuted,
                                            size: 20,
                                          ),
                                        ),
                                      )
                                    : Container(
                                        color: AppPalette.of(context)
                                            .background,
                                        child: Icon(
                                          Icons.water,
                                          color: AppPalette.of(context)
                                              .textMuted,
                                          size: 22,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.product.name,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (item.optionLabel != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      item.optionLabel!,
                                      style: TextStyle(
                                        color: AppPalette.of(context).textMuted,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 3),
                                  Text(
                                    formatPrice(item.unitPrice),
                                    style: TextStyle(
                                      color: AppPalette.of(context).accent,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Align(
                          alignment: Alignment.centerRight,
                          child: item.product.isLiveFish
                              ? IconButton(
                                  tooltip: 'Remove from cart',
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: AppPalette.of(context).error,
                                  ),
                                  onPressed: () => _removeWithUndo(item),
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    color: AppPalette.of(context).background,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.pill,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _QtyButton(
                                        icon: Icons.remove,
                                        onTap: () {
                                          if (item.quantity == 1) {
                                            _removeWithUndo(item);
                                          } else {
                                            ref
                                                .read(cartProvider.notifier)
                                                .updateQuantity(
                                                  item.product.id,
                                                  item.quantity - 1,
                                                  variantId:
                                                      item.selectedVariant?.id,
                                                  size: item.selectedSize,
                                                );
                                          }
                                        },
                                      ),
                                      SizedBox(
                                        width: 48,
                                        child: Text(
                                          '${item.quantity}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                      ),
                                      _QtyButton(
                                        icon: Icons.add,
                                        onTap: () => ref
                                            .read(cartProvider.notifier)
                                            .updateQuantity(
                                              item.product.id,
                                              item.quantity + 1,
                                              variantId:
                                                  item.selectedVariant?.id,
                                              size: item.selectedSize,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      bottomNavigationBar: items.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                decoration: BoxDecoration(
                  color: AppPalette.of(context).surface,
                  boxShadow: AppShadows.raised,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppPalette.of(context).textMuted,
                          ),
                        ),
                        Text(
                          formatPrice(total),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppPalette.of(context).text,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => beginCheckout(context, ref),
                        child: const Text('Proceed to Checkout'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: icon == Icons.add ? 'Increase quantity' : 'Decrease quantity',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        // A 48px target works for both iOS and Android.
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(icon, size: 16, color: AppPalette.of(context).text),
        ),
      ),
    );
  }
}
