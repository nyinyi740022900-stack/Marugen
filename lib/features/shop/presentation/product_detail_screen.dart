import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/utils/contact_launcher.dart';
import '../../../shared/utils/price_format.dart';
import '../../../shared/utils/view_tracker.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/fullscreen_image_gallery.dart';
import '../../../shared/widgets/product_card.dart';
import '../../../shared/widgets/product_video_player.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/models/product.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../cart/domain/cart_item.dart';
import '../../cart/presentation/cart_providers.dart';
import '../../reviews/presentation/reviews_section.dart';
import '../../wishlist/presentation/wishlist_providers.dart';
import 'shop_providers.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen>
    with SingleTickerProviderStateMixin {
  ProductVariant? _selectedVariant;
  String? _selectedSize;
  String? _selectedVariantForProductId;
  int _quantity = 1;
  int _imagePage = 0;

  // Lazada/Shopee-style PDP tabs: one continuous scroll with an anchor per
  // section (not 4 separate TabBarViews — switching those would reset
  // scroll position oddly and duplicate the single shared scroll
  // experience). No NestedScrollView/SliverPersistentHeader-with-TabBar
  // pattern existed anywhere in this codebase before this screen, so this
  // is a small hand-rolled scroll-spy: a GlobalKey per section, a scroll
  // listener that highlights whichever section's top has just passed
  // under the pinned tab bar, and a tap handler that scrolls to a
  // section's position computed the same way.
  static const _tabBarHeight = 46.0;
  late final TabController _tabController;
  final _scrollController = ScrollController();
  final _overviewKey = GlobalKey();
  final _detailsKey = GlobalKey();
  final _reviewsKey = GlobalKey();
  final _recommendationsKey = GlobalKey();
  bool _userTappedTab = false;

  List<GlobalKey> get _sectionKeys =>
      [_overviewKey, _detailsKey, _reviewsKey, _recommendationsKey];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  double get _stickyThresholdY =>
      MediaQuery.of(context).padding.top + kToolbarHeight + _tabBarHeight;

  void _onScroll() {
    // While a tap-triggered animateTo is in flight, don't fight it by
    // recomputing the "nearest section" from intermediate scroll frames
    // — the tapped tab is already the one the user wants highlighted.
    if (_userTappedTab) return;
    var activeIndex = 0;
    for (var i = 0; i < _sectionKeys.length; i++) {
      final ctx = _sectionKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final globalY = box.localToGlobal(Offset.zero).dy;
      if (globalY <= _stickyThresholdY) activeIndex = i;
    }
    if (_tabController.index != activeIndex) {
      _tabController.animateTo(activeIndex, duration: Duration.zero);
    }
  }

  Future<void> _onTabTap(int index) async {
    final ctx = _sectionKeys[index].currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox;
    final currentGlobalY = box.localToGlobal(Offset.zero).dy;
    final targetOffset =
        (_scrollController.offset + currentGlobalY - _stickyThresholdY)
            .clamp(0.0, _scrollController.position.maxScrollExtent);

    setState(() {
      _userTappedTab = true;
      _tabController.index = index;
    });
    await _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
    _userTappedTab = false;
  }

  Future<void> _contactShop(Product product) async {
    final settings = await ref.read(shopSettingsProvider.future);
    final phone = settings['shop_phone'] as String? ?? '';
    await launchShopContact(
      phone,
      message: "Hi, I'm interested in ${product.name}",
    );
  }

  /// Shared by Add to Cart and Buy Now so both respect the selected
  /// variant, the quantity stepper and the stock cap.
  CartAddResult _addToCart(Product product) {
    return ref
        .read(cartProvider.notifier)
        .add(
          product,
          quantity: product.isLiveFish ? 1 : _quantity,
          variant: _selectedVariant,
          size: _selectedSize,
        );
  }

  void _showCartMessage(CartAddResult result) {
    showCartSnackBar(context, result);
  }

  /// Buy Now — an isolated single-item purchase, same as Amazon/Shopee/
  /// Lazada's "Buy Now": it never touches the persistent cart (doesn't
  /// add to it, doesn't clear it), so whatever's already in the cart
  /// stays exactly as it was before and after. The picked item goes
  /// straight to checkout via router `extra` instead of merging into
  /// [cartProvider] — see CheckoutScreen.buyNowItems and the `/checkout`
  /// route in app_router.dart.
  void _buyNow(Product product) {
    final quantity = product.isLiveFish ? 1 : _quantity;
    final available = CartNotifier.availableFor(
      product,
      _selectedVariant,
      size: product.hasSizeOptions ? _selectedSize : null,
    );
    if (available <= 0) {
      _showCartMessage(CartAddResult.outOfStock);
      return;
    }
    final item = CartItem(
      product: product,
      quantity: quantity.clamp(1, available),
      selectedVariant: _selectedVariant,
      selectedSize: product.hasSizeOptions ? _selectedSize : null,
    );
    context.push('/checkout', extra: [item]);
  }

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(productDetailProvider(widget.productId));

    return Scaffold(
      body: productAsync.when(
        data: (product) {
          if (product == null) {
            return EmptyState(
              icon: Icons.search_off_outlined,
              title: 'Product not found',
              subtitle: 'It may have been removed or is no longer available.',
              actionLabel: 'Back to Shop',
              onAction: () => context.canPop() ? context.pop() : context.go('/'),
            );
          }
          // Reset the selection if we've navigated to a different product
          // (e.g. via the "You may also like" row) without this widget
          // being recreated.
          if (_selectedVariantForProductId != product.id) {
            _selectedVariantForProductId = product.id;
            _selectedVariant = null;
            _selectedSize = null;
            _quantity = 1;
            _imagePage = 0;
            ViewTracker.logProductView(product.id);
          }
          final fish = product.fishDetails;
          final hasFishDetails = fish != null && fish.hasAnyDetail;
          final hasImages = product.imageUrls.isNotEmpty;
          return CustomScrollView(
            controller: _scrollController,
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
                              onPageChanged: (i) =>
                                  setState(() => _imagePage = i),
                              children: [
                                for (final url in product.imageUrls)
                                  GestureDetector(
                                    onTap: () => FullscreenImageGallery.open(
                                      context,
                                      imageUrls: product.imageUrls,
                                      initialIndex: _imagePage,
                                    ),
                                    // BoxFit.contain (not .cover) so the
                                    // whole uploaded photo is visible
                                    // up-front — .cover was cropping the
                                    // top/bottom of tall product photos,
                                    // only fixable before by tapping into
                                    // the fullscreen gallery.
                                    child: Container(
                                      color: AppColors.charcoal,
                                      child: CachedNetworkImage(
                                        imageUrl: url,
                                        fit: BoxFit.contain,
                                        placeholder: (_, _) =>
                                            Container(color: AppColors.offWhite),
                                        errorWidget: (_, _, _) => Container(
                                          color: AppColors.offWhite,
                                          child: const Icon(
                                            Icons.image_not_supported_outlined,
                                            color: AppColors.greySoft,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
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
                          child: const Icon(
                            Icons.water,
                            size: 48,
                            color: AppColors.greySoft,
                          ),
                        ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PdpTabBarDelegate(
                  height: _tabBarHeight,
                  child: TabBar(
                    controller: _tabController,
                    onTap: _onTabTap,
                    // The app's shared TabBarThemeData styles white labels
                    // for tabs that sit on the black AppBar (Knowledge
                    // screen) — invisible on this tab bar's white
                    // background, so this one overrides colors explicitly.
                    // Labels are also kept short (not "Product Details" /
                    // "Recommendations") so all 4 fit without truncation
                    // on a standard phone width.
                    labelColor: AppColors.black,
                    unselectedLabelColor: AppColors.grey,
                    indicatorColor: AppColors.red,
                    dividerColor: Colors.transparent,
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    tabs: const [
                      Tab(text: 'Overview'),
                      Tab(text: 'Details'),
                      Tab(text: 'Reviews'),
                      Tab(text: 'Related'),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  key: _overviewKey,
                  decoration: const BoxDecoration(
                    color: AppColors.offWhite,
                  ),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.xxxl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (product.hasVariants) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          product.hasSizeOptions
                              ? 'WEIGHT'
                              : (product.isLiveFish ? 'CHOOSE FISH' : 'OPTIONS'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0.8,
                            color: AppColors.grey,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            for (final v in product.variants)
                              Builder(
                                builder: (_) {
                                  final weightStock = product.hasSizeOptions
                                      ? product.sizeOptions.fold<int>(
                                          0,
                                          (s, size) {
                                            final q = product.stockFor(
                                              variantId: v.id,
                                              size: size,
                                            );
                                            return s + (q > 0 ? q : 0);
                                          },
                                        )
                                      : v.stockQuantity;
                                  final inStock = weightStock > 0;
                                  return ChoiceChip(
                                    label: Text(
                                      inStock
                                          ? v.label
                                          : '${v.label} (Sold out)',
                                    ),
                                    selected: _selectedVariant?.id == v.id,
                                    showCheckmark: false,
                                    onSelected: inStock
                                        ? (_) => setState(() {
                                            _selectedVariant = v;
                                            _quantity = 1;
                                          })
                                        : null,
                                  );
                                },
                              ),
                          ],
                        ),
                      ],
                      if (product.hasSizeOptions) ...[
                        const SizedBox(height: AppSpacing.md),
                        const Text(
                          'SIZE',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0.8,
                            color: AppColors.grey,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            for (final size in product.sizeOptions)
                              Builder(
                                builder: (_) {
                                  final sizeStock = _selectedVariant == null
                                      ? null
                                      : product.stockFor(
                                          variantId: _selectedVariant!.id,
                                          size: size,
                                        );
                                  final soldOut = sizeStock != null &&
                                      sizeStock <= 0;
                                  return ChoiceChip(
                                    label: Text(
                                      soldOut ? '$size (Sold out)' : size,
                                    ),
                                    selected: _selectedSize == size,
                                    showCheckmark: false,
                                    onSelected: soldOut
                                        ? null
                                        : (_) => setState(() {
                                            _selectedSize = size;
                                            _quantity = 1;
                                          }),
                                  );
                                },
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      if (product.isPurchasable &&
                          !product.hasVariants &&
                          product.hasActiveSale)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              formatPrice(product.salePrice!),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppColors.red,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatPrice(product.price!),
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.grey,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.red,
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Text(
                                '-${product.discountPercent}%',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
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
                      _StockLine(
                        product: product,
                        variant: _selectedVariant,
                        size: _selectedSize,
                      ),
                      if (!product.isLiveFish &&
                          product.isPurchasable &&
                          !product.isOutOfStock &&
                          (!product.hasVariants ||
                              _selectedVariant != null) &&
                          (!product.hasSizeOptions ||
                              _selectedSize != null)) ...[
                        const SizedBox(height: AppSpacing.md),
                        _QuantityStepper(
                          quantity: _quantity,
                          max: CartNotifier.availableFor(
                            product,
                            _selectedVariant,
                            size: _selectedSize,
                          ),
                          onChanged: (q) => setState(() => _quantity = q),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      _DeliveryInfoCard(isLiveFish: product.isLiveFish),
                      const SizedBox(height: AppSpacing.xl),
                      if (product.videoUrl != null &&
                          product.videoUrl!.isNotEmpty) ...[
                        const Text(
                          'VIDEO',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0.8,
                            color: AppColors.grey,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ProductVideoPlayer(videoUrl: product.videoUrl!),
                      ],
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  key: _detailsKey,
                  color: AppColors.offWhite,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.xxxl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!hasFishDetails && product.description == null)
                        const Text(
                          'No additional details for this product.',
                          style: TextStyle(color: AppColors.grey, fontSize: 13.5),
                        ),
                      if (hasFishDetails) ...[
                        const Text(
                          'DETAILS',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0.8,
                            color: AppColors.grey,
                          ),
                        ),
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
                                _SpecRow(
                                  'Size',
                                  '${fish.sizeCm!.toStringAsFixed(0)} cm',
                                ),
                              if (fish.gender != null)
                                _SpecRow('Gender', fish.gender!),
                              if (fish.breeder != null)
                                _SpecRow('Breeder', fish.breeder!),
                              if (fish.hasCertificate)
                                _SpecRow('Certificate', 'Included'),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      if (product.description != null) ...[
                        const Text(
                          'DESCRIPTION',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0.8,
                            color: AppColors.grey,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          product.description!,
                          style: const TextStyle(fontSize: 14, height: 1.5),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  key: _reviewsKey,
                  color: AppColors.offWhite,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.xl,
                  ),
                  child: ReviewsSection(productId: product.id),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  key: _recommendationsKey,
                  color: AppColors.offWhite,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.xxxl,
                  ),
                  child: _RelatedProductsRow(product: product),
                ),
              ),
            ],
          );
        },
        loading: () => const ProductDetailSkeleton(),
        error: (e, _) => ErrorState(
          onRetry: () => ref.invalidate(productDetailProvider(widget.productId)),
        ),
      ),
      bottomNavigationBar: productAsync.maybeWhen(
        data: (product) {
          if (product == null) return null;
          final soldOut = product.isOutOfStock;
          final contactForPrice = !product.isPurchasable;
          final needsVariantSelection =
              product.hasVariants && !soldOut && _selectedVariant == null;
          final needsSizeSelection =
              product.hasSizeOptions && !soldOut && _selectedSize == null;
          final needsOptionSelection =
              needsVariantSelection || needsSizeSelection;
          final canBuy =
              !soldOut && !contactForPrice && !needsOptionSelection;

          return SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: AppColors.white,
                boxShadow: AppShadows.raised,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (needsOptionSelection) ...[
                    Text(
                      needsVariantSelection && needsSizeSelection
                          ? 'Select weight and size above to continue'
                          : needsVariantSelection
                              ? 'Select an option above to continue'
                              : 'Select a size above to continue',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.grey,
                      ),
                    ),
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
                            icon: const Icon(
                              Icons.chat_bubble_outline,
                              size: 18,
                            ),
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
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 8,
                              ),
                            ),
                            child: Text(
                              needsOptionSelection
                                  ? (needsVariantSelection && needsSizeSelection
                                      ? 'Select Options'
                                      : needsSizeSelection
                                          ? 'Select a Size'
                                          : 'Select an Option')
                                  : 'Add to Cart',
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
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 8,
                              ),
                            ),
                            child: const Text(
                              'Buy Now',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
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
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.lightGrey, width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 22,
              color: AppColors.black,
            ),
          ),
        ),
      ),
    );
  }
}

/// "In stock" / "Only N left" / "Sold" line under the price. For variant
/// products it reflects the selected weight×size once chosen, else the
/// total across variants.
class _StockLine extends ConsumerWidget {
  final Product product;
  final ProductVariant? variant;
  final String? size;
  const _StockLine({
    required this.product,
    required this.variant,
    this.size,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!product.isPurchasable) return const SizedBox.shrink();

    final int available;
    if (variant != null && product.hasSizeOptions) {
      available = size == null
          ? 0
          : product.stockFor(variantId: variant!.id, size: size);
    } else {
      available = variant?.stockQuantity ?? product.availableStock;
    }
    final threshold = ref.watch(lowStockThresholdProvider);
    final IconData icon;
    final Color color;
    final String label;
    if (available <= 0) {
      icon = Icons.remove_circle_outline;
      color = AppColors.grey;
      label = product.unavailableLabel;
    } else if (product.isLiveFish && !product.hasVariants) {
      // A single fish with no options is one specific animal — "in stock"
      // reads oddly. A batch listing with options is picked per-variety
      // instead, so it falls through to the normal stock messaging below.
      icon = Icons.check_circle_outline;
      color = AppColors.success;
      label = 'Available — one-of-a-kind fish';
    } else if (available <= threshold) {
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
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
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
  const _QuantityStepper({
    required this.quantity,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveMax = max < 1 ? 1 : max;
    final q = quantity.clamp(1, effectiveMax);
    return Row(
      children: [
        const Text(
          'Quantity',
          style: TextStyle(fontSize: 13.5, color: AppColors.grey),
        ),
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
                child: Text(
                  '$q',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
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
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: icon == Icons.add ? 'Increase quantity' : 'Decrease quantity',
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        // 13px padding + 18px icon = 44px tap target (was 8px = 34px).
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? AppColors.black : AppColors.greySoft,
          ),
        ),
      ),
    );
  }
}

/// Delivery block built from the `settings` row: island-wide delivery
/// (courier for regular items, hand-delivered by the shop for live fish)
/// and the live-arrival note for fish. Answers the "how do I get it?"
/// question every marketplace shows above the fold. There is no
/// self-collection/pickup option — every order is delivered.
class _DeliveryInfoCard extends ConsumerWidget {
  final bool isLiveFish;
  const _DeliveryInfoCard({required this.isLiveFish});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DELIVERY',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.8,
            color: AppColors.grey,
          ),
        ),
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
              _InfoRow(
                icon: Icons.local_shipping_outlined,
                title: 'Island-wide delivery in Singapore',
                subtitle: isLiveFish
                    // Live fish are not handed to a courier/API — the shop
                    // hand-delivers these orders itself for animal welfare.
                    ? 'Hand-delivered by our team; no courier tracking for live fish.'
                    : 'Shipped by courier; tracking number appears on your order.',
              ),
              if (isLiveFish) ...[
                const SizedBox(height: AppSpacing.md),
                const _InfoRow(
                  icon: Icons.health_and_safety_outlined,
                  title: 'Live arrival care',
                  subtitle: 'Packed for transit; contact us within 24h of delivery if a fish arrives unwell.',
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
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

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
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.grey,
                  height: 1.35,
                ),
              ),
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
        await ref
            .read(wishlistControllerProvider)
            .toggle(productId, isFavorited);
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
            const Text(
              'YOU MAY ALSO LIKE',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
                color: AppColors.grey,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 260,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: related.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.md),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13.5, color: AppColors.grey),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Pinned Overview/Product Details/Reviews/Recommendations tab bar — the
/// Lazada/Shopee-style PDP chrome, sitting between the collapsed hero
/// image app bar and the scrolling sections below (see the scroll-spy
/// logic in _ProductDetailScreenState: _onScroll / _onTabTap).
class _PdpTabBarDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  const _PdpTabBarDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: AppColors.white,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _PdpTabBarDelegate oldDelegate) =>
      oldDelegate.child != child || oldDelegate.height != height;
}
