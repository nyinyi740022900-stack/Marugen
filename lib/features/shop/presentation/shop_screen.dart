import '../../../shared/widgets/product_grid.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/product.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../../shared/widgets/cart_badge_button.dart';
import '../../../shared/widgets/support_contact_picker.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/product_card.dart';
import '../../../shared/widgets/notification_bell_button.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../banners/presentation/hero_banner_carousel.dart';
import '../../banners/presentation/home_banner_providers.dart';
import 'shop_providers.dart';

class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(visibleProductListProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final sort = ref.watch(productSortProvider);
    // Pull down for stock and prices changed since opening the app (e.g. a
    // koi sold to someone else).
    Future<void> refreshCatalogue() => Future.wait([
      ref.refresh(productListProvider.future),
      // Banners too, so a slide the owner just changed shows up. They fail
      // soft: a banner outage must not turn a good catalogue refresh into
      // an error.
      ref
          .refresh(liveHomeBannersProvider.future)
          .then<void>((_) {}, onError: (_) {}),
    ]);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const BrandLogo(size: 26),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'MARUGEN FISH FARM',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          const NotificationBellButton(),
          const SizedBox(width: 6),
          const CartBadgeButton(),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppPalette.of(context).surface,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              0,
            ),
            child: Row(
              children: [
                const Expanded(child: _SearchField()),
                const SizedBox(width: AppSpacing.sm),
                _SortButton(
                  sort: sort,
                  onChanged: (s) =>
                      ref.read(productSortProvider.notifier).state = s,
                ),
              ],
            ),
          ),
          Container(
            color: AppPalette.of(context).surface,
            child: SizedBox(
              height: 32 + MediaQuery.textScalerOf(context).scale(24),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                children: [
                  _CategoryChip(
                    label: 'All',
                    selected: selectedCategory == null,
                    onSelected: () =>
                        ref.read(selectedCategoryProvider.notifier).state =
                            null,
                  ),
                  for (final category in ProductCategory.values)
                    _CategoryChip(
                      label: categoryLabel(category),
                      selected: selectedCategory == category,
                      onSelected: () =>
                          ref.read(selectedCategoryProvider.notifier).state =
                              category,
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  final searching = ref
                      .watch(searchQueryProvider)
                      .trim()
                      .isNotEmpty;
                  // Empty is still a state worth refreshing: a fish listed
                  // a minute ago should appear without restarting the app.
                  return _RefreshableEmpty(
                    onRefresh: refreshCatalogue,
                    child: searching
                        ? EmptyState(
                            icon: Icons.search_off,
                            title: 'No matching products',
                            subtitle:
                                'Try another search or clear your filters.',
                            actionLabel: 'Clear filters',
                            onAction: () {
                              ref.read(searchQueryProvider.notifier).state =
                                  '';
                              ref
                                      .read(selectedCategoryProvider.notifier)
                                      .state =
                                  null;
                            },
                          )
                        : selectedCategory != null
                        // A category with nothing in it is not a failed
                        // filter: say so, and offer the farm.
                        ? EmptyState(
                            icon: Icons.water_outlined,
                            title: emptyCategoryTitle(selectedCategory),
                            subtitle: emptyCategorySubtitle(selectedCategory),
                            actionLabel: 'Ask the farm',
                            onAction: () => showSupportContactPicker(
                              context,
                              message: emptyCategoryEnquiry(selectedCategory),
                              messageIsPersonal: false,
                            ),
                            secondaryLabel: 'See all products',
                            onSecondary: () =>
                                ref
                                        .read(selectedCategoryProvider.notifier)
                                        .state =
                                    null,
                          )
                        : const _EmptyState(),
                  );
                }
                return RefreshIndicator.adaptive(
                  onRefresh: refreshCatalogue,
                  child: ProductGrid(
                    header: const HeroBannerCarousel(),
                    itemCount: products.length,
                    itemBuilder: (context, i) => ProductCard(
                      product: products[i],
                      onTap: () => context.push('/product/${products[i].id}'),
                    ),
                  ),
                );
              },
              loading: () =>
                  const ProductGridSkeleton(header: HeroBannerCarousel()),
              error: (e, _) => ErrorState(
                onRetry: () => ref.invalidate(productListProvider),
              ),
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

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

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
                tooltip: 'Clear search',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () =>
                    ref.read(searchQueryProvider.notifier).state = '',
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        filled: true,
        fillColor: AppPalette.of(context).background,
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
                  Icon(
                    Icons.check,
                    size: 16,
                    color: AppPalette.of(context).accent,
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Text(sortLabel(s)),
              ],
            ),
          ),
      ],
      child: Container(
        height: 48,
        width: 48,
        decoration: BoxDecoration(
          color: AppPalette.of(context).background,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(Icons.sort, size: 20, color: AppPalette.of(context).text),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.water_outlined,
      title: 'No products yet',
      subtitle: 'Check back soon — new koi and supplies are added regularly.',
    );
  }
}

/// "koi" in "No koi available right now".
String _categoryNoun(ProductCategory category) => switch (category) {
  ProductCategory.koi => 'koi',
  ProductCategory.arowana => 'arowana',
  _ => categoryLabel(category).toLowerCase(),
};

/// Title of the Shop's empty state when a category chip is selected and
/// there is no search text: the category has nothing listed right now.
String emptyCategoryTitle(ProductCategory category) =>
    'No ${_categoryNoun(category)} available right now';

String emptyCategorySubtitle(ProductCategory category) =>
    category == ProductCategory.koi || category == ProductCategory.arowana
    ? 'New fish are listed as soon as they are ready. Message us to ask what is in the ponds.'
    : 'New stock is listed as soon as it arrives. Message us to ask what is on the way.';

/// What "Ask the farm" pre-fills. Nothing personal in it, so a guest can
/// send it too.
String emptyCategoryEnquiry(ProductCategory category) =>
    'Hi, do you have any ${_categoryNoun(category)} available?';

/// An empty state that can still be pulled down to refresh.
class _RefreshableEmpty extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  const _RefreshableEmpty({required this.onRefresh, required this.child});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator.adaptive(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(height: constraints.maxHeight, child: child),
        ),
      ),
    );
  }
}
