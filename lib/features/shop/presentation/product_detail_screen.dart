import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/utils/contact_launcher.dart';
import '../../../shared/utils/price_format.dart';
import '../../../shared/widgets/product_card.dart';
import '../../../shared/widgets/product_video_player.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/models/product.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../cart/presentation/cart_providers.dart';
import '../../reviews/presentation/reviews_section.dart';
import '../../wishlist/presentation/wishlist_providers.dart';
import 'shop_providers.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  ProductVariant? _selectedVariant;
  String? _selectedVariantForProductId;
  int _quantity = 1;

  Future<void> _contactShop(Product product) async {
    final settings = await ref.read(shopSettingsProvider.future);
    final phone = settings['shop_phone'] as String? ?? '';
    await launchShopContact(phone, message: "Hi, I'm interested in ${product.name}");
  }

  /// Shared by Add to Cart and Buy Now so both respect the selected
  /// variant, the quantity stepper and the stock cap.
  CartAddResult _addToCart(Product product) {
    return ref.read(cartProvider.notifier).add(
          product,
          quantity: product.isLiveFish ? 1 : _quantity,
          variant: _selectedVariant,
        );
  }

  void _showCartMessage(CartAddResult result) {
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
  }

  /// Buy Now = add to cart, then jump straight to checkout. Guests hit the
  /// router's `/checkout` login gate and are bounced back here afterwards
  /// with the cart intact (it's persisted locally).
  void _buyNow(Product product) {
    final result = _addToCart(product);
    if (result == CartAddResult.outOfStock) {
      _showCartMessage(result);
      return;
    }
    context.push('/checkout');
  }

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(productDetailProvider(widget.productId));

    return Scaffold(
      body: productAsync.when(
        data: (product) {
          if (product == null) {
            return const Center(child: Text('Product not found.'));
          }
          // Reset the selection if we've navigated to a different product
          // (e.g. via the "You may also like" row) without this widget
          // being recreated.
          if (_selectedVariantForProductId != product.id) {
            _selectedVariantForProductId = product.id;
            _selectedVariant = null;
            _quantity = 1;
          }
          final fish = product.fishDetails;
          final hasFishDetails = fish != null && fish.hasAnyDetail;
          final hasImages = product.imageUrls.isNotEmpty;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: hasImages ? 320 : 200,
                pinned: true,
                backgroundColor: AppColors.black,
                foregroundColor: AppColors.white,
                // Chat lives in the bottom action bar (one clear place to
                // contact the shop), so the app bar only keeps the heart.
                actions: [_FavoriteAppBarButton(productId: product.id)],
                flexibleSpace: FlexibleSpaceBar(
                  background: hasImages
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            PageView(
                              children: [
                                for (final url in product.imageUrls)
                                  CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
                              ],
                            ),
                            // Scrim so the back/heart/chat icons stay legible
                            // over bright photos, matching the solid app bar
                            // treatment used everywhere else in the app.
                            IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      AppColors.black.withValues(alpha: 0.45),
                                      Colors.transparent,
                                    ],
                                    stops: const [0.0, 0.35],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Container(
                          color: AppColors.charcoal,
                          child: const Icon(Icons.water,
                              size: 48, color: AppColors.greySoft),
                        ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.offWhite,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                  ),
                  transform: Matrix4.translationValues(0, -AppRadius.lg, 0),
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.xxxl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.name,
                          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                      if (product.hasVariants) ...[
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            for (final v in product.variants)
                              ChoiceChip(
                                label: Text(v.stockQuantity > 0
                                    ? v.label
                                    : '${v.label} (Sold out)'),
                                selected: _selectedVariant?.id == v.id,
                                showCheckmark: false,
                                onSelected: v.stockQuantity > 0
                                    ? (_) => setState(() {
                                          _selectedVariant = v;
                                          _quantity = 1;
                                        })
                                    : null,
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        !product.isPurchasable
                            ? 'Contact us for price'
                            : product.hasVariants
                                ? (_selectedVariant != null
                                    ? formatPrice(_selectedVariant!.price)
                                    : 'Select an option')
                                : formatPrice(product.price!),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.red,
                        ),
                      ),
                      ReviewSummary(productId: product.id),
                      const SizedBox(height: AppSpacing.md),
                      _StockLine(product: product, variant: _selectedVariant),
                      if (!product.isLiveFish &&
                          product.isPurchasable &&
                          !product.isOutOfStock &&
                          (!product.hasVariants || _selectedVariant != null)) ...[
                        const SizedBox(height: AppSpacing.md),
                        _QuantityStepper(
                          quantity: _quantity,
                          max: CartNotifier.availableFor(product, _selectedVariant),
                          onChanged: (q) => setState(() => _quantity = q),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      _DeliveryInfoCard(isLiveFish: product.isLiveFish),
                      const SizedBox(height: AppSpacing.xl),
                      if (product.videoUrl != null && product.videoUrl!.isNotEmpty) ...[
                        const Text('VIDEO',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 0.8,
                                color: AppColors.grey)),
                        const SizedBox(height: AppSpacing.sm),
                        ProductVideoPlayer(videoUrl: product.videoUrl!),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      if (hasFishDetails) ...[
                        const Text('DETAILS',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 0.8,
                                color: AppColors.grey)),
                        const SizedBox(height: AppSpacing.sm),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            boxShadow: AppShadows.card,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              if (fish.variety != null)
                                _SpecRow('Variety', fish.variety!),
                              if (fish.sizeCm != null)
                                _SpecRow('Size', '${fish.sizeCm!.toStringAsFixed(0)} cm'),
                              if (fish.gender != null) _SpecRow('Gender', fish.gender!),
                              if (fish.breeder != null) _SpecRow('Breeder', fish.breeder!),
                              if (fish.hasCertificate) _SpecRow('Certificate', 'Included'),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      if (product.description != null) ...[
                        const Text('DESCRIPTION',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 0.8,
                                color: AppColors.grey)),
                        const SizedBox(height: AppSpacing.sm),
                        Text(product.description!,
                            style: const TextStyle(fontSize: 14, height: 1.5)),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      _RelatedProductsRow(product: product),
                      const SizedBox(height: AppSpacing.xl),
                      ReviewsSection(productId: product.id),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const ProductDetailSkeleton(),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      bottomNavigationBar: productAsync.maybeWhen(
        data: (product) {
          if (product == null) return null;
          final soldOut = product.isOutOfStock;
          final contactForPrice = !product.isPurchasable;
          final needsVariantSelection =
              product.hasVariants && !soldOut && _selectedVariant == null;
          final canBuy = !soldOut && !contactForPrice && !needsVariantSelection;

          return SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.white,
                boxShadow: AppShadows.raised,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (needsVariantSelection) ...[
                    const Text('Select a size/option above to continue',
                        style: TextStyle(fontSize: 12.5, color: AppColors.grey)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Row(
                    children: [
                      // 1. Chat — the single place to reach the shop.
                      _ChatButton(onPressed: () => _contactShop(product)),
                      const SizedBox(width: AppSpacing.md),
                      if (contactForPrice && !soldOut)
                        // No price → no Add/Buy; the bar collapses to
                        // [Chat] [Contact Us for Price].
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _contactShop(product),
                            icon: const Icon(Icons.chat_bubble_outline, size: 18),
                            label: const Text('Contact Us for Price'),
                          ),
                        )
                      else if (soldOut)
                        Expanded(
                          child: ElevatedButton(
                            onPressed: null,
                            child: Text(product.unavailableLabel),
                          ),
                        )
                      else ...[
                        // 2. Add to Cart (outlined) — stays on the page.
                        Expanded(
                          child: OutlinedButton(
                            onPressed: canBuy
                                ? () => _showCartMessage(_addToCart(product))
                                : null,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                            ),
                            child: Text(
                              needsVariantSelection ? 'Select a Size' : 'Add to Cart',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        // 3. Buy Now (filled red) — straight to checkout.
                        Expanded(
                          child: ElevatedButton(
                            onPressed: canBuy ? () => _buyNow(product) : null,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                            ),
                            child: const Text('Buy Now',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
        orElse: () => null,
      ),
    );
  }
}

/// Round outlined chat icon at the left of the action bar (Shopee/Lazada
/// "Chat with seller"). Opens WhatsApp/phone via [launchShopContact].
class _ChatButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ChatButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Chat with shop',
      child: Material(
        color: AppColors.white,
        shape: const CircleBorder(side: BorderSide(color: AppColors.lightGrey, width: 1.2)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.chat_bubble_outline, size: 22, color: AppColors.black),
          ),
        ),
      ),
    );
  }
}

/// "In stock" / "Only N left" / "Sold" line under the price. For variant
/// products it reflects the selected variant once one is chosen, else the
/// total across variants.
class _StockLine extends StatelessWidget {
  final Product product;
  final ProductVariant? variant;
  const _StockLine({required this.product, required this.variant});

  @override
  Widget build(BuildContext context) {
    if (!product.isPurchasable) return const SizedBox.shrink();

    final available = variant?.stockQuantity ?? product.availableStock;
    final IconData icon;
    final Color color;
    final String label;
    if (available <= 0) {
      icon = Icons.remove_circle_outline;
      color = AppColors.grey;
      label = product.unavailableLabel;
    } else if (product.isLiveFish) {
      icon = Icons.check_circle_outline;
      color = AppColors.success;
      label = 'Available — one-of-a-kind fish';
    } else if (available <= lowStockThreshold) {
      icon = Icons.local_fire_department_outlined;
      color = AppColors.red;
      label = 'Only $available left';
    } else {
      icon = Icons.check_circle_outline;
      color = AppColors.success;
      label = 'In stock';
    }
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

/// Quantity picker shown before Add to Cart for restockable goods. Capped
/// at [max] so the customer can't queue more than the shop has.
class _QuantityStepper extends StatelessWidget {
  final int quantity;
  final int max;
  final ValueChanged<int> onChanged;
  const _QuantityStepper({required this.quantity, required this.max, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final effectiveMax = max < 1 ? 1 : max;
    final q = quantity.clamp(1, effectiveMax);
    return Row(
      children: [
        const Text('Quantity', style: TextStyle(fontSize: 13.5, color: AppColors.grey)),
        const Spacer(),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.lightGrey),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StepButton(
                icon: Icons.remove,
                enabled: q > 1,
                onTap: () => onChanged(q - 1),
              ),
              SizedBox(
                width: 32,
                child: Text('$q',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              _StepButton(
                icon: Icons.add,
                enabled: q < effectiveMax,
                onTap: () => onChanged(q + 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _StepButton({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 18, color: enabled ? AppColors.black : AppColors.greySoft),
      ),
    );
  }
}

/// Delivery & pickup block built from the `settings` row: island-wide
/// courier delivery (Qxpress), self-collection at the farm address, and
/// the live-arrival note for fish. Answers the "how do I get it?" question
/// every marketplace shows above the fold.
class _DeliveryInfoCard extends ConsumerWidget {
  final bool isLiveFish;
  const _DeliveryInfoCard({required this.isLiveFish});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(shopSettingsProvider).valueOrNull;
    final address = (settings?['shop_address'] as String?)?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('DELIVERY & PICKUP',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
                color: AppColors.grey)),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: AppShadows.card,
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              const _InfoRow(
                icon: Icons.local_shipping_outlined,
                title: 'Island-wide delivery in Singapore',
                subtitle: 'Shipped by courier; tracking number appears on your order.',
              ),
              if (address.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _InfoRow(
                  icon: Icons.storefront_outlined,
                  title: 'Self-collection at the farm',
                  subtitle: address,
                ),
              ],
              if (isLiveFish) ...[
                const SizedBox(height: AppSpacing.md),
                const _InfoRow(
                  icon: Icons.health_and_safety_outlined,
                  title: 'Live arrival care',
                  subtitle:
                      'Packed for transit; contact us within 24h of delivery if a fish arrives unwell.',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _InfoRow({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.red),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.grey, height: 1.35)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Heart toggle in the product detail app bar. Mirrors [ProductCard]'s
/// favorite button, including the guest login gate.
class _FavoriteAppBarButton extends ConsumerWidget {
  final String productId;
  const _FavoriteAppBarButton({required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(isLoggedInProvider);
    final idsAsync = ref.watch(wishlistProductIdsProvider);
    final isFavorited = idsAsync.valueOrNull?.contains(productId) ?? false;

    return IconButton(
      tooltip: isFavorited ? 'Remove from wishlist' : 'Add to wishlist',
      icon: Icon(isFavorited ? Icons.favorite : Icons.favorite_border),
      color: isFavorited ? AppColors.red : AppColors.white,
      onPressed: () async {
        if (!isLoggedIn) {
          context.push('/login');
          return;
        }
        await ref.read(wishlistControllerProvider).toggle(productId, isFavorited);
      },
    );
  }
}

/// "You may also like" — other products in the same category.
class _RelatedProductsRow extends ConsumerWidget {
  final Product product;
  const _RelatedProductsRow({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relatedAsync = ref.watch(
      relatedProductsProvider((id: product.id, category: product.category)),
    );
    return relatedAsync.maybeWhen(
      data: (related) {
        if (related.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('YOU MAY ALSO LIKE',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.8,
                    color: AppColors.grey)),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: related.length,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
                itemBuilder: (context, i) => SizedBox(
                  width: 150,
                  child: ProductCard(
                    product: related[i],
                    onTap: () => context.push('/product/${related[i].id}'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _SpecRow extends StatelessWidget {
  final String label;
  final String value;
  const _SpecRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.grey)),
          Text(value,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
