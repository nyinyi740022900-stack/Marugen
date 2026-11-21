import 'press_scale.dart';
import 'sized_network_image.dart';
import 'skeleton.dart';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../models/product.dart';
import '../utils/price_format.dart';

/// At or below this many units a card shows an "Only N left" tag. Kept
/// separate from the admin low-stock threshold so the shop can tune the
/// customer-facing urgency independently.
const lowStockCardThreshold = 3;

/// A marketplace-style listing card: photo, name, price and one line of
/// proof. It carries no buttons — the whole card is one tap target that
/// opens the product page, where cart, buy now, wishlist and contact live.
class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback? onTap;

  const ProductCard({super.key, required this.product, this.onTap});

  // Body geometry. Every row has a fixed height derived from the text
  // scale, so cards in a row are the same height whatever each one has to
  // show, and [bodyHeight] is exact rather than an estimate.
  static const _sidePadding = 10.0;
  static const _topPadding = AppSpacing.sm;
  static const _bottomPadding = 10.0;
  static const _nameToPrice = AppSpacing.xs;
  static const _priceToProof = 3.0;
  static const _nameLeading = 1.2;
  static const _priceLeading = 1.2;
  static const _proofLeading = 1.3;

  static double _nameHeight(TextScaler scaler) =>
      (scaler.scale(AppTextStyles.cardTitle.fontSize!) * _nameLeading * 2)
          .ceilToDouble();

  static double _priceHeight(TextScaler scaler) =>
      (scaler.scale(AppTextStyles.price.fontSize!) * _priceLeading)
          .ceilToDouble();

  static double _proofHeight(TextScaler scaler) =>
      (scaler.scale(AppTextStyles.caption.fontSize!) * _proofLeading)
          .ceilToDouble();

  /// Height of everything under the square photo, for grids and carousels
  /// that size their cells to the card (see `productCardExtent`).
  static double bodyHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return _topPadding +
        _nameHeight(scaler) +
        _nameToPrice +
        _priceHeight(scaler) +
        _priceToProof +
        _proofHeight(scaler) +
        _bottomPadding;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(AppRadius.md);
    final unavailable = product.isPurchasable && product.isOutOfStock;

    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      label: productCardSemanticsLabel(product),
      onTap: onTap,
      excludeSemantics: true,
      child: PressScale(
        child: Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: radius,
          ),
          // Flat on the grid: a hairline separates the white card from the
          // ivory page in light mode; in dark the surface step is enough.
          // Painted over the content so it never changes the layout.
          foregroundDecoration: isDark
              ? null
              : BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: palette.border),
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
                    child: _Photo(product: product, unavailable: unavailable),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _sidePadding,
                      _topPadding,
                      _sidePadding,
                      _bottomPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Two lines are always reserved so prices line up
                        // across a row of one- and two-line names.
                        SizedBox(
                          height: _nameHeight(scaler),
                          child: Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.cardTitle.copyWith(
                              height: _nameLeading,
                            ),
                          ),
                        ),
                        const SizedBox(height: _nameToPrice),
                        SizedBox(
                          height: _priceHeight(scaler),
                          child: _PriceRow(
                            product: product,
                            unavailable: unavailable,
                          ),
                        ),
                        const SizedBox(height: _priceToProof),
                        // Reserved even when there is nothing to say.
                        SizedBox(
                          height: _proofHeight(scaler),
                          child: _ProofLine(product: product),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a screen reader announces for a card, in one sentence: name, fish
/// facts, price (with the sale), rating, units sold, then stock state.
@visibleForTesting
String productCardSemanticsLabel(Product product) {
  final parts = <String>[product.name, ..._fishFacts(product)];
  if (!product.isPurchasable) {
    parts.add('Contact for price');
  } else if (product.hasActiveSale) {
    parts.add(
      'on sale ${formatPrice(product.salePrice!)}, '
      'was ${formatPrice(product.price!)}, ${product.discountPercent}% off',
    );
  } else {
    parts.add(_priceLabel(product));
  }
  if (product.avgRating != null) {
    final rating = 'rating ${product.avgRating!.toStringAsFixed(1)} of 5';
    final reviews = product.reviewCount;
    parts.add(
      reviews > 0
          ? '$rating from $reviews review${reviews == 1 ? '' : 's'}'
          : rating,
    );
  }
  if (product.soldCount > 0) parts.add('${product.soldCount} sold');
  if (product.isPurchasable) {
    if (product.isOutOfStock) {
      parts.add(product.isLiveFish ? 'sold' : 'out of stock');
    } else if (_showsLowStock(product)) {
      parts.add('only ${product.availableStock} left');
    }
  }
  return parts.join(', ');
}

bool _showsLowStock(Product product) =>
    !product.isLiveFish &&
    product.isPurchasable &&
    !product.isOutOfStock &&
    product.availableStock <= lowStockCardThreshold;

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

/// "45 cm", "Male" for one specific fish. A batch listing is several fish,
/// so a single size or gender would not be true of it.
List<String> _fishFacts(Product product) {
  if (!product.isSingleFish) return const [];
  final f = product.fishDetails;
  return [
    if (f?.sizeCm != null)
      '${f!.sizeCm! % 1 == 0 ? f.sizeCm!.toInt() : f.sizeCm} cm',
    if (f?.gender != null && f!.gender!.trim().isNotEmpty) f.gender!.trim(),
  ];
}

class _Photo extends StatelessWidget {
  final Product product;
  final bool unavailable;
  const _Photo({required this.product, required this.unavailable});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final variety = product.fishDetails?.variety;
    return Stack(
      fit: StackFit.expand,
      children: [
        product.imageUrls.isNotEmpty
            ? SizedNetworkImage(
                imageUrl: product.imageUrls.first,
                fit: BoxFit.cover,
                // Soft shimmer while loading; still under reduced motion.
                placeholder: (_, _) => const Skeleton(
                  height: double.infinity,
                  borderRadius: BorderRadius.zero,
                ),
                errorWidget: (_, _, _) => ColoredBox(
                  color: palette.surfaceMuted,
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: palette.textMuted,
                  ),
                ),
              )
            : ColoredBox(
                color: palette.surfaceMuted,
                child: Icon(Icons.water, color: palette.textMuted, size: 40),
              ),
        // Sold / out of stock dims the photo. Above the photo, under the
        // tags, so the tags stay fully legible.
        if (unavailable)
          ColoredBox(color: AppColors.black.withValues(alpha: 0.55)),
        // Variety and discount stack: a koi on sale shows both. The right
        // inset leaves the corner free for the control the wishlist and the
        // admin Products screen lay over the card.
        if (variety != null || product.hasActiveSale)
          Positioned(
            left: 8,
            top: 8,
            right: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (variety != null) _Tag(label: variety),
                if (variety != null && product.hasActiveSale)
                  const SizedBox(height: 4),
                if (product.hasActiveSale)
                  _Tag(
                    label: '-${product.discountPercent}%',
                    color: AppColors.red,
                  ),
              ],
            ),
          ),
        // A sold fish keeps its stamp (one animal, gone for good); a
        // restockable item at 0 gets a quiet tag where "Only N left" sits.
        if (unavailable && product.isLiveFish)
          Center(
            child: Transform.rotate(
              angle: -0.12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.white, width: 1.5),
                ),
                child: Text(
                  product.unavailableLabel.toUpperCase(),
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 3,
                  ),
                ),
              ),
            ),
          )
        else if (unavailable)
          const Positioned(
            left: 8,
            bottom: 8,
            right: 8,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _Tag(
                label: 'Out of stock',
                color: AppColors.white,
                textColor: AppColors.black,
              ),
            ),
          )
        else if (_showsLowStock(product))
          Positioned(
            left: 8,
            bottom: 8,
            right: 8,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _Tag(
                label: 'Only ${product.availableStock} left',
                color: AppColors.red,
              ),
            ),
          ),
      ],
    );
  }
}

/// One line, never truncated and never wrapped: the price takes the full
/// content width and only shrinks if a very large amount would not fit.
/// On sale the struck original sits beside it when there is room and the
/// text is not enlarged past 1.3× — the -N% tag on the photo says it
/// otherwise.
class _PriceRow extends StatelessWidget {
  final Product product;
  final bool unavailable;
  const _PriceRow({required this.product, required this.unavailable});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    // "Contact for price" is a note, not an amount: the quieter supporting
    // role, so it also fits a narrow card at larger text sizes.
    final priceStyle = DefaultTextStyle.of(context).style.merge(
      product.isPurchasable
          ? AppTextStyles.price.copyWith(
              height: ProductCard._priceLeading,
              color: unavailable ? palette.textMuted : palette.accent,
            )
          : AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              height: ProductCard._priceLeading,
              color: palette.textMuted,
            ),
    );
    final label = product.hasActiveSale
        ? formatPrice(product.salePrice!)
        : _priceLabel(product);
    final price = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(label, maxLines: 1, softWrap: false, style: priceStyle),
    );
    if (!product.hasActiveSale || scaler.scale(14) > 14 * 1.3) {
      return Align(alignment: Alignment.centerLeft, child: price);
    }
    final original = formatPrice(product.price!);
    final originalStyle = DefaultTextStyle.of(context).style.merge(
      AppTextStyles.caption.copyWith(
        height: ProductCard._priceLeading,
        color: palette.textMuted,
        decoration: TextDecoration.lineThrough,
      ),
    );
    const gap = 6.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        double width(String text, TextStyle style) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final w = painter.width;
          painter.dispose();
          return w;
        }

        final fits =
            width(label, priceStyle) + gap + width(original, originalStyle) <=
            constraints.maxWidth;
        if (!fits) return Align(alignment: Alignment.centerLeft, child: price);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(child: price),
            const SizedBox(width: gap),
            Text(original, maxLines: 1, softWrap: false, style: originalStyle),
          ],
        );
      },
    );
  }
}

/// "45 cm · Male · ★ 4.8 (152) · 991 sold": the social proof shoppers
/// expect from a marketplace card, on one muted line. The facts of a single
/// fish lead, because size is what a koi buyer scans for and the end of the
/// line is what a narrow card cuts off.
class _ProofLine extends StatelessWidget {
  final Product product;
  const _ProofLine({required this.product});

  @override
  Widget build(BuildContext context) {
    final facts = _fishFacts(product);
    final rating = product.avgRating;
    final after = <String>[
      if (rating != null)
        product.reviewCount > 0
            ? '${rating.toStringAsFixed(1)} (${product.reviewCount})'
            : rating.toStringAsFixed(1),
      if (product.soldCount > 0) '${product.soldCount} sold',
    ];
    if (facts.isEmpty && after.isEmpty) return const SizedBox.shrink();

    final style = AppTextStyles.caption.copyWith(
      color: AppPalette.of(context).textMuted,
      height: ProductCard._proofLeading,
    );
    const separator = ' · ';
    return Align(
      alignment: Alignment.centerLeft,
      // One paragraph, so a narrow card trims the end of the line instead of
      // squeezing each part.
      child: Text.rich(
        TextSpan(
          children: [
            if (facts.isNotEmpty) TextSpan(text: facts.join(separator)),
            if (facts.isNotEmpty && after.isNotEmpty)
              const TextSpan(text: separator),
            if (rating != null)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Icon(
                    Icons.star_rounded,
                    size: MediaQuery.textScalerOf(context)
                        .scale(style.fontSize!),
                    color: const Color(0xFFFFA726),
                  ),
                ),
              ),
            if (after.isNotEmpty) TextSpan(text: after.join(separator)),
          ],
        ),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color? color;
  final Color textColor;
  const _Tag({
    required this.label,
    this.color,
    this.textColor = AppColors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color ?? AppColors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppSpacing.xs),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
