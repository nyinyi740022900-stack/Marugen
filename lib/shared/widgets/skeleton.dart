import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A gently shimmering gray box — the building block for skeleton loading
/// states across the app (product cards, text lines, list rows) in place
/// of a bare [CircularProgressIndicator].
class Skeleton extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.sm)),
  });

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(AppColors.lightGrey, AppColors.offWhite, t),
            borderRadius: widget.borderRadius,
          ),
        );
      },
    );
  }
}

/// Skeleton placeholder shaped like a [ProductCard] — used while the shop
/// grid or a related-products row is loading.
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AspectRatio(aspectRatio: 1, child: Skeleton(borderRadius: BorderRadius.zero)),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Skeleton(width: double.infinity, height: 14),
                const SizedBox(height: 8),
                Skeleton(width: 60, height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A grid of [ProductCardSkeleton]s matching the shop screen's grid layout.
class ProductGridSkeleton extends StatelessWidget {
  final int count;
  const ProductGridSkeleton({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.66,
      ),
      itemCount: count,
      itemBuilder: (context, i) => const ProductCardSkeleton(),
    );
  }
}

/// Skeleton for a single line-item row (used in order lists, etc).
class ListRowSkeleton extends StatelessWidget {
  const ListRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Skeleton(width: 120, height: 14),
              Skeleton(width: 56, height: 18, borderRadius: BorderRadius.circular(AppRadius.pill)),
            ],
          ),
          const SizedBox(height: 10),
          const Skeleton(width: 90, height: 11),
          const SizedBox(height: 10),
          Skeleton(width: 70, height: 15),
        ],
      ),
    );
  }
}

/// Skeleton for the product-detail screen's content column while it loads.
class ProductDetailSkeleton extends StatelessWidget {
  const ProductDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const AspectRatio(
          aspectRatio: 1.1,
          child: Skeleton(borderRadius: BorderRadius.all(Radius.circular(AppRadius.md))),
        ),
        const SizedBox(height: AppSpacing.xl),
        const Skeleton(width: 220, height: 20),
        const SizedBox(height: AppSpacing.sm),
        Skeleton(width: 100, height: 20),
        const SizedBox(height: AppSpacing.xl),
        const Skeleton(width: double.infinity, height: 13),
        const SizedBox(height: 8),
        const Skeleton(width: double.infinity, height: 13),
        const SizedBox(height: 8),
        Skeleton(width: 180, height: 13),
      ],
    );
  }
}
