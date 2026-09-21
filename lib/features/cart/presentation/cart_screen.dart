import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/price_format.dart';
import '../../../shared/widgets/empty_state.dart';
import 'cart_providers.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
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
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(title: const Text('MY CART')),
      body: items.isEmpty
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
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) {
                final item = items[i];
                return Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: AppShadows.card,
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: SizedBox(
                          width: 60,
                          height: 60,
                          child: item.product.imageUrls.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: item.product.imageUrls.first,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) =>
                                      Container(color: AppColors.offWhite),
                                  errorWidget: (_, _, _) => Container(
                                    color: AppColors.offWhite,
                                    child: const Icon(Icons.image_not_supported_outlined,
                                        color: AppColors.greySoft, size: 20),
                                  ),
                                )
                              : Container(
                                  color: AppColors.offWhite,
                                  child: const Icon(Icons.water,
                                      color: AppColors.greySoft, size: 22),
                                ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.product.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14)),
                            if (item.optionLabel != null) ...[
                              const SizedBox(height: 2),
                              Text(item.optionLabel!,
                                  style: const TextStyle(
                                      color: AppColors.grey, fontSize: 12.5)),
                            ],
                            const SizedBox(height: 3),
                            Text(
                              formatPrice(item.unitPrice),
                              style: const TextStyle(
                                  color: AppColors.red,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5),
                            ),
                          ],
                        ),
                      ),
                      if (item.product.isLiveFish)
                        IconButton(
                          tooltip: 'Remove from cart',
                          icon: const Icon(Icons.delete_outline, color: AppColors.error),
                          onPressed: () => ref
                              .read(cartProvider.notifier)
                              .remove(
                                item.product.id,
                                variantId: item.selectedVariant?.id,
                                size: item.selectedSize,
                              ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.offWhite,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _QtyButton(
                                icon: Icons.remove,
                                onTap: () => ref.read(cartProvider.notifier).updateQuantity(
                                    item.product.id, item.quantity - 1,
                                    variantId: item.selectedVariant?.id,
                                    size: item.selectedSize),
                              ),
                              SizedBox(
                                width: 24,
                                child: Text('${item.quantity}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                              ),
                              _QtyButton(
                                icon: Icons.add,
                                onTap: () => ref.read(cartProvider.notifier).updateQuantity(
                                    item.product.id, item.quantity + 1,
                                    variantId: item.selectedVariant?.id,
                                    size: item.selectedSize),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: items.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  boxShadow: AppShadows.raised,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.grey)),
                        Text(formatPrice(total),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, color: AppColors.black, fontSize: 20)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ElevatedButton(
                      onPressed: () => context.push('/checkout'),
                      child: const Text('Proceed to Checkout'),
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
        // 14px padding + 16px icon = 44px tap target (was 6px = 28px).
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(icon, size: 16, color: AppColors.black),
        ),
      ),
    );
  }
}
