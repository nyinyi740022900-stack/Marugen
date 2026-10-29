import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Includes the square image and enough space for scaled card content.
double productCardExtent(BuildContext context, double cardWidth) {
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  // Dates spanning two months can wrap beside the 48px cart action. Measure
  // that complete range instead of assuming the delivery row is one line.
  final delivery = TextPainter(
    text: TextSpan(
      text: '30 Sep – 30 Nov',
      style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 10.5),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: math.max(1, cardWidth - 24 - 48 - 15));
  final extra = math.max(0.0, delivery.height - 48);
  delivery.dispose();
  return cardWidth + 80 + 100 * scale + extra;
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
  const ProductGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: productGridDelegate(context, constraints.maxWidth - 32),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    },
  );
}
