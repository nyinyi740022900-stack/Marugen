import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bottom_inset.dart';
import 'product_card.dart';

/// The square photo plus the exact height of the card body, so a grid cell
/// ends where the card's content ends: no band of empty surface under the
/// proof line and nothing clipped at large text sizes. The body height comes
/// from the card itself, so the two cannot drift apart.
double productCardExtent(BuildContext context, double cardWidth) =>
    cardWidth + ProductCard.bodyHeight(context);

/// Space between cards, in both directions.
const productGridGutter = 12.0;

/// Shares real card geometry with loading states and saved products.
SliverGridDelegate productGridDelegate(BuildContext context, double width) {
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  // A 360-wide phone has 328 available pixels after outer padding: two
  // 158-wide cards plus the gutter. Column counts are unchanged from the
  // 16-pixel gutter this replaced; the cards are simply a little wider.
  const gutter = productGridGutter;
  final minimum = scale > 1.3 ? 240.0 : 156.0;
  final count = math.max(1, ((width + 16) / (minimum + 16)).floor());
  final cardWidth = (width - gutter * (count - 1)) / count;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: count,
    crossAxisSpacing: gutter,
    mainAxisSpacing: gutter,
    mainAxisExtent: productCardExtent(context, cardWidth),
  );
}

class ProductGrid extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Scrolls away with the grid (the Shop tab's hero carousel); the header
  /// brings its own horizontal padding.
  final Widget? header;

  const ProductGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.header,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final delegate = productGridDelegate(context, constraints.maxWidth - 32);
      final padding = const EdgeInsets.all(16).plusBottomInset(context);
      // Pull-to-refresh must work even when a few products fit on screen.
      const physics = AlwaysScrollableScrollPhysics();
      if (header == null) {
        return GridView.builder(
          physics: physics,
          padding: padding,
          gridDelegate: delegate,
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      }
      return CustomScrollView(
        physics: physics,
        slivers: [
          SliverToBoxAdapter(child: header),
          SliverPadding(
            padding: padding,
            sliver: SliverGrid(
              gridDelegate: delegate,
              delegate: SliverChildBuilderDelegate(
                itemBuilder,
                childCount: itemCount,
              ),
            ),
          ),
        ],
      );
    },
  );
}
