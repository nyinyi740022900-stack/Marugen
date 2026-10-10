import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shares real card geometry with loading states and saved products.
SliverGridDelegate productGridDelegate(BuildContext context, double width) {
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  final minimum = scale > 1.3 ? 240.0 : 160.0;
  final count = math.max(1, ((width + 16) / (minimum + 16)).floor());
  final cardWidth = (width - 16 * (count - 1)) / count;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: count,
    crossAxisSpacing: 16,
    mainAxisSpacing: 16,
    mainAxisExtent: cardWidth + 80 + 85 * scale,
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
