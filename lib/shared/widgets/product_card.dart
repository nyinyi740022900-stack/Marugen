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
import '../utils/delivery_estimate.dart';
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
                      )
                    else if (product.hasActiveSale)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _Tag(
                          label: '-${product.discountPercent}%',
                          color: AppColors.red,
                        ),
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
                    // Always reserve this line's height (even with nothing
                    // to show) so the price/cart-button row lands at the
                    // same Y across every card in a grid row, whether or
                    // not that particular card has options/reviews/sold count.
                    const SizedBox(height: 3),
                    _StatsRow(product: product),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: product.hasActiveSale
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      formatPrice(product.price!),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.grey,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                    Text(
                                      formatPrice(product.salePrice!),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.red,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
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
                    if (product.isPurchasable && !product.isOutOfStock) ...[
                      const SizedBox(height: 3),
                      const _DeliveryEstimateLabel(),
                    ],
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

    if (product.isLiveFish && !product.hasVariants) {
      return _RoundIconButton(
        icon: Icons.add_shopping_cart,
        tooltip: 'Buy Now',
        onTap: () {
          final result = ref.read(cartProvider.notifier).add(product);
          if (result == CartAddResult.outOfStock) {
            showCartSnackBar(context, result);
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

  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.black,
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
          showCartSnackBar(context, result);
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

/// "★4.8 (191) · 500 sold" line, matching the marketplace-style social
/// proof shoppers expect (Lazada/Shopee) — only shown when there's
/// something real to say (see the call site's guard).
class _StatsRow extends StatelessWidget {
  final Product product;
  const _StatsRow({required this.product});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (product.reviewCount > 0) {
      parts.add('(${product.reviewCount})');
    }
    if (product.soldCount > 0) {
      parts.add('${product.soldCount} sold');
    }
    if (product.hasVariants) {
      parts.add('${product.variantCount} option${product.variantCount == 1 ? '' : 's'}');
    }
    // Nothing to say — still reserve the line's height so cards without
    // stats don't pull their price/cart row up relative to cards that do.
    if (product.avgRating == null && parts.isEmpty) {
      return const SizedBox(height: 15);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (product.avgRating != null) ...[
          const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFFA726)),
          const SizedBox(width: 2),
          Text(
            product.avgRating!.toStringAsFixed(1),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.grey),
          ),
        ],
        if (parts.isNotEmpty) ...[
          if (product.avgRating != null) const SizedBox(width: 3),
          Flexible(
            child: Text(
              parts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.grey),
            ),
          ),
        ],
      ],
    );
  }
}

/// Estimated delivery window computed from the shop's configured lead
/// time (`settings.delivery_lead_days_min/max`, migration 0013).
class _DeliveryEstimateLabel extends ConsumerWidget {
  const _DeliveryEstimateLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(shopSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    if (settings == null) return const SizedBox.shrink();
    final label = formatDeliveryEstimate(
      minDays: settings['delivery_lead_days_min'] as int? ?? 2,
      maxDays: settings['delivery_lead_days_max'] as int? ?? 5,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.local_shipping_outlined, size: 12, color: AppColors.greySoft),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: AppColors.greySoft),
          ),
        ),
      ],
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
