import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bottom_inset.dart';

/// The square image plus the measured height of the card body, so the grid
/// cell ends where the card's content ends instead of leaving a band of
/// empty surface under the delivery row. Mirrors the body layout in
/// `product_card.dart`: 8/12 vertical padding, a two-line name, the stats
/// line, the price line and a 48 px action row the delivery text may wrap
/// beside.
double productCardExtent(BuildContext context, double cardWidth) {
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  final contentWidth = math.max(1.0, cardWidth - 24);

  double textHeight(
    String text,
    TextStyle style, {
    int? maxLines = 1,
    double? maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth ?? contentWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  final body = Theme.of(context).textTheme.bodyMedium!;
  // Two full lines even for a short name (the card reserves them).
  final name = math.max(
    (scaler.scale(14) * 1.2 * 2).ceilToDouble(),
    textHeight('Mm\nMm', body.copyWith(fontSize: 14, height: 1.2), maxLines: 2),
  );
  // Star icon (12 px) or the reserved empty line, whichever is taller.
  final stats = math.max(scaler.scale(11) * 1.2, 14.0);
  // The longest price label, allowed to wrap: it is never truncated.
  final price = textHeight(
    'From S\$8,888.80',
    body.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
    maxLines: null,
  );
  // Dates spanning two months can wrap beside the 48 px cart action. Measure
  // that complete range instead of assuming the delivery row is one line.
  final delivery = textHeight(
    '30 Sep – 30 Nov',
    body.copyWith(fontSize: 10.5),
    // Unbounded: at 2× on a narrow card the range wraps word by word.
    maxLines: null,
    maxWidth: math.max(1, cardWidth - 24 - 48 - 15),
  );
  final actionRow = math.max(48.0, delivery);
  return cardWidth + 8 + name + 3 + stats + 4 + price + 4 + actionRow + 12 + 2;
}

/// Shares real card geometry with loading states and saved products.
SliverGridDelegate productGridDelegate(BuildContext context, double width) {
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  // A 360-wide phone has 328 available pixels after outer padding:
  // two 156-wide cards plus the 16-pixel gutter must still fit.
  final minimum = scale > 1.3 ? 240.0 : 156.0;
  final count = math.max(1, ((width + 16) / (minimum + 16)).floor());
  final cardWidth = (width - 16 * (count - 1)) / count;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: count,
    crossAxisSpacing: 16,
    mainAxisSpacing: 16,
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
