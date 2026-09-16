import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/cart/presentation/cart_providers.dart';
import '../../features/wishlist/presentation/wishlist_providers.dart';
import '../models/product.dart';
import '../providers/settings_providers.dart';
import '../utils/contact_launcher.dart';
import '../utils/price_format.dart';

/// At or below this many units a card shows an "Only N left" tag. Kept
/// separate from the admin low-stock threshold so the shop can tune the
/// customer-facing urgency independently.
const lowStockCardThreshold = 3;

class ProductCard extends ConsumerWidget {
  final Product product;
  final VoidCallback? onTap;

  /// Whether the heart/favorite toggle is shown. Off by default for
  /// places like the wishlist screen itself where a remove button already
  /// does that job.
  final bool showFavoriteToggle;

  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.showFavoriteToggle = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    product.imageUrls.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: product.imageUrls.first,
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                Container(color: AppColors.offWhite),
                            errorWidget: (_, _, _) => Container(
                              color: AppColors.offWhite,
                              child: const Icon(Icons.image_not_supported_outlined,
                                  color: AppColors.greySoft),
                            ),
                          )
                        : Container(
                            color: AppColors.offWhite,
                            child: const Icon(Icons.water,
                                color: AppColors.greySoft, size: 40),
                          ),
                    if (product.fishDetails?.variety != null)
                      Positioned(
                        left: 8,
                        top: 8,
                        right: 40,
                        child: _Tag(label: product.fishDetails!.variety!),
                      ),
                    if (showFavoriteToggle)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: _FavoriteButton(productId: product.id),
                      ),
                    // Stock signal: a sold fish gets the stamped SOLD
                    // overlay; a restockable item at 0 gets a clear
                    // "Out of Stock" overlay so nobody taps into a dead end.
                    if (product.isPurchasable && product.isOutOfStock)
                      IgnorePointer(
                        child: Container(
                          color: AppColors.black.withValues(alpha: 0.55),
                          alignment: Alignment.center,
                          child: Transform.rotate(
                            angle: product.isLiveFish ? -0.12 : 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.white, width: 1.5),
                              ),
                              child: Text(
                                product.unavailableLabel.toUpperCase(),
                                style: TextStyle(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: product.isLiveFish ? 13 : 11,
                                  letterSpacing: product.isLiveFish ? 3 : 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (!product.isLiveFish &&
                        product.isPurchasable &&
                        product.availableStock <= lowStockCardThreshold)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: _Tag(
                          label: 'Only ${product.availableStock} left',
                          color: AppColors.red,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14, height: 1.2),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _priceLabel(product),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: product.isPurchasable ? AppColors.red : AppColors.grey,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        _CardActionButtons(product: product, onOpenDetail: onTap),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _priceLabel(Product product) {
  if (!product.isPurchasable) return 'Contact for price';
  if (product.hasVariants) {
    final prices = product.variants.map((v) => v.price).toList()..sort();
    final low = prices.first;
    final high = prices.last;
    return low == high ? formatPrice(low) : 'From ${formatPrice(low)}';
  }
  return formatPrice(product.price!);
}

/// CTA row on the card price line:
/// - restockable + priced → quick-add cart (variant products open PDP)
/// - live fish + priced + in stock → Buy Now (cart + checkout)
/// - contact-for-price → Chat with shop
class _CardActionButtons extends ConsumerWidget {
  final Product product;
  final VoidCallback? onOpenDetail;
  const _CardActionButtons({required this.product, this.onOpenDetail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!product.isPurchasable) {
      return _RoundIconButton(
        icon: Icons.chat_bubble_outline,
        tooltip: 'Chat with seller',
        onTap: () => _chatAbout(ref, product),
      );
    }

    if (product.isOutOfStock) {
      return const SizedBox.shrink();
    }

    if (product.isLiveFish) {
      return _RoundIconButton(
        icon: Icons.flash_on,
        tooltip: 'Buy Now',
        color: AppColors.red,
        onTap: () {
          final result = ref.read(cartProvider.notifier).add(product);
          if (result == CartAddResult.outOfStock) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(cartAddMessage(result))));
            return;
          }
          // alreadyInCart or added → go checkout with that fish in cart
          context.push('/checkout');
        },
      );
    }

    return _QuickAddButton(product: product, onOpenDetail: onOpenDetail);
  }

  Future<void> _chatAbout(WidgetRef ref, Product product) async {
    final settings = await ref.read(shopSettingsProvider.future);
    final phone = settings['shop_phone'] as String? ?? '';
    await launchShopContact(
      phone,
      message: "Hi, I'm interested in ${product.name}",
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = AppColors.black,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 15, color: AppColors.white),
          ),
        ),
      ),
    );
  }
}

/// Compact cart icon in the card's price row. Plain products go straight
/// into the cart with a snackbar; variant products bounce to the detail
/// page (via [onOpenDetail]) because a size has to be chosen first.
class _QuickAddButton extends ConsumerWidget {
  final Product product;
  final VoidCallback? onOpenDetail;
  const _QuickAddButton({required this.product, this.onOpenDetail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.black,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (!product.supportsQuickAdd) {
            onOpenDetail?.call();
            return;
          }
          final result = ref.read(cartProvider.notifier).add(product);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(cartAddMessage(result)),
              duration: const Duration(seconds: 2),
              action: result == CartAddResult.added
                  ? SnackBarAction(
                      label: 'View Cart',
                      textColor: AppColors.white,
                      onPressed: () => context.push('/cart'),
                    )
                  : null,
            ));
        },
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.add_shopping_cart, size: 15, color: AppColors.white),
        ),
      ),
    );
  }
}

/// Heart toggle shown on product cards. Guests get prompted to log in
/// instead of the toggle silently failing (same gating pattern checkout
/// uses via the router's `_authRequiredRoutes`).
class _FavoriteButton extends ConsumerWidget {
  final String productId;
  const _FavoriteButton({required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(isLoggedInProvider);
    final idsAsync = ref.watch(wishlistProductIdsProvider);
    final isFavorited = idsAsync.valueOrNull?.contains(productId) ?? false;

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (!isLoggedIn) {
            context.push('/login');
            return;
          }
          await ref.read(wishlistControllerProvider).toggle(productId, isFavorited);
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isFavorited ? Icons.favorite : Icons.favorite_border,
            size: 16,
            color: isFavorited ? AppColors.red : AppColors.white,
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color? color;
  const _Tag({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color ?? AppColors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
