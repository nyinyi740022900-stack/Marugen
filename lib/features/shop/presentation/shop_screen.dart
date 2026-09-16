import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/product.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/product_card.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../cart/presentation/cart_providers.dart';
import 'shop_providers.dart';

class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(visibleProductListProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final cartCount = ref.watch(cartCountProvider);
    final sort = ref.watch(productSortProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const BrandLogo(size: 26),
            const SizedBox(width: 8),
            const Text('MARUGEN KOI FARM'),
          ],
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_bag_outlined),
                onPressed: () => context.push('/cart'),
              ),
              if (cartCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: AppColors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$cartCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10, color: AppColors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.white,
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
            child: Row(
              children: [
                const Expanded(child: _SearchField()),
                const SizedBox(width: AppSpacing.sm),
                _SortButton(
                  sort: sort,
                  onChanged: (s) => ref.read(productSortProvider.notifier).state = s,
                ),
              ],
            ),
          ),
          Container(
            color: AppColors.white,
            child: SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                children: [
                  _CategoryChip(
                    label: 'All',
                    selected: selectedCategory == null,
                    onSelected: () =>
                        ref.read(selectedCategoryProvider.notifier).state = null,
                  ),
                  for (final category in ProductCategory.values)
                    _CategoryChip(
                      label: categoryLabel(category),
                      selected: selectedCategory == category,
                      onSelected: () =>
                          ref.read(selectedCategoryProvider.notifier).state = category,
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  return const _EmptyState();
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    childAspectRatio: 0.66,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, i) => ProductCard(
                    product: products[i],
                    onTap: () => context.push('/product/${products[i].id}'),
                  ),
                );
              },
              loading: () => const ProductGridSkeleton(),
              error: (e, _) => _EmptyState(error: e.toString()),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _CategoryChip({required this.label, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

/// Search field with its own stable [TextEditingController] so the cursor
/// and focus survive provider-driven rebuilds; pushes changes into
/// [searchQueryProvider] and stays in sync if the query is cleared
/// elsewhere (e.g. its own clear button).
class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(searchQueryProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    if (query != _controller.text) {
      _controller.value = _controller.value.copyWith(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
    return TextField(
      controller: _controller,
      onChanged: (v) => ref.read(searchQueryProvider.notifier).state = v,
      decoration: InputDecoration(
        hintText: 'Search koi, arowana, food…',
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => ref.read(searchQueryProvider.notifier).state = '',
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        filled: true,
        fillColor: AppColors.offWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  final ProductSort sort;
  final ValueChanged<ProductSort> onChanged;

  const _SortButton({required this.sort, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ProductSort>(
      initialValue: sort,
      onSelected: onChanged,
      tooltip: 'Sort',
      itemBuilder: (context) => [
        for (final s in ProductSort.values)
          PopupMenuItem(
            value: s,
            child: Row(
              children: [
                if (s == sort)
                  const Icon(Icons.check, size: 16, color: AppColors.red)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Text(sortLabel(s)),
              ],
            ),
          ),
      ],
      child: Container(
        height: 44,
        width: 44,
        decoration: BoxDecoration(
          color: AppColors.offWhite,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Icon(Icons.sort, size: 20, color: AppColors.black),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String? error;
  const _EmptyState({this.error});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: error == null ? Icons.water_outlined : Icons.wifi_off_outlined,
      title: error == null ? 'No products yet' : 'Could not load products',
      subtitle: error == null
          ? 'Check back soon — new koi and supplies are added regularly.'
          : 'Configure Supabase in .env and try again.',
    );
  }
}
