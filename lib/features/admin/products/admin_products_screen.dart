import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/product.dart';
import '../../../shared/providers/paged_notifier.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/product_card.dart';
import '../../shop/data/product_repository.dart';
import '../../shop/presentation/shop_providers.dart';

/// Free-text query for the admin Products search bar — kept separate from
/// the customer shop's [searchQueryProvider] so typing in one never
/// affects the other.
final adminProductSearchQueryProvider = StateProvider<String>((ref) => '');

class AdminProductsScreen extends ConsumerStatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  ConsumerState<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends ConsumerState<AdminProductsScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.attachPagination(
      () => ref.read(adminProductsPagedProvider.notifier).loadNextPage(),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(adminProductSearchQueryProvider).trim().toLowerCase();
    final selectedCategory = ref.watch(selectedCategoryProvider);
    // Pagination only applies to the default (no search) view — same
    // reasoning as the admin Orders list (see AdminOrdersPagedNotifier).
    final searching = query.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.red,
        onPressed: () => context.push('/admin/products/new'),
        child: const Icon(Icons.add, color: AppColors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
            child: _AdminSearchField(),
          ),
          SizedBox(
            height: 48,
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
                    onSelected: () => ref
                        .read(selectedCategoryProvider.notifier)
                        .state = category,
                  ),
              ],
            ),
          ),
          Expanded(
            child: searching
                ? ref.watch(productListProvider).when(
                    data: (products) {
                      final filtered = products.where((p) {
                        if (p.name.toLowerCase().contains(query)) return true;
                        final variety = p.fishDetails?.variety;
                        return variety != null && variety.toLowerCase().contains(query);
                      }).toList();

                      if (filtered.isEmpty) {
                        return const EmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: 'No matches',
                          subtitle: 'Try a different search or category.',
                        );
                      }
                      return _ProductGrid(products: filtered);
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: AppColors.red),
                    ),
                    error: (e, _) => ErrorState(onRetry: () => ref.invalidate(productListProvider)),
                  )
                : ref.watch(adminProductsPagedProvider).when(
                    data: (paged) {
                      if (paged.items.isEmpty) {
                        return const EmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: 'No products yet',
                          subtitle: 'Tap the + button to add your first product.',
                        );
                      }
                      return _ProductGrid(
                        products: paged.items,
                        scrollController: _scrollController,
                        trailingLoader: paged.hasMore,
                      );
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: AppColors.red),
                    ),
                    error: (e, _) => ErrorState(
                      onRetry: () => ref.read(adminProductsPagedProvider.notifier).refresh(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The product grid itself, shared by both the search-mode (unbounded,
/// no scrollController needed) and paged-mode (infinite scroll) branches
/// above. A `CustomScrollView` + `SliverGrid` (rather than a plain
/// `GridView.builder`) so the "loading next page" spinner can render as
/// a normal full-width row below the grid instead of awkwardly fitting
/// into one grid cell.
class _ProductGrid extends ConsumerWidget {
  final List<Product> products;
  final ScrollController? scrollController;
  final bool trailingLoader;

  const _ProductGrid({
    required this.products,
    this.scrollController,
    this.trailingLoader = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
          ),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 0.6,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final product = products[i];
                return Stack(
                  children: [
                    ProductCard(
                      product: product,
                      onTap: () => context.push('/admin/products/${product.id}'),
                      // Favoriting is a customer affordance — admin has no
                      // use for it, and it collides with the sold-toggle
                      // below in the same corner.
                      showFavoriteToggle: false,
                    ),
                    // One-tap "mark sold/unavailable" for a single live
                    // fish — a farm admin selling a koi/arowana in
                    // person (at a show, or a walk-in) needs to pull it
                    // from the app immediately without opening the full
                    // edit form. Not shown for a batch listing with fish
                    // options: each option's own stock field is the
                    // right place to mark that one sold. Regular
                    // restockable goods don't get this either: their
                    // "how many are left" question is better answered by
                    // the numeric stock field in the edit form.
                    if (product.isLiveFish && !product.hasVariants)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: _AvailabilityToggle(product: product, ref: ref),
                      ),
                  ],
                );
              },
              childCount: products.length,
            ),
          ),
        ),
        if (trailingLoader)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.red, strokeWidth: 2),
              ),
            ),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxxl + AppSpacing.xl)),
      ],
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
/// and focus survive provider-driven rebuilds — same pattern as the
/// customer shop's search field, but against [adminProductSearchQueryProvider].
class _AdminSearchField extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AdminSearchField> createState() => _AdminSearchFieldState();
}

class _AdminSearchFieldState extends ConsumerState<_AdminSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(adminProductSearchQueryProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(adminProductSearchQueryProvider);
    if (query != _controller.text) {
      _controller.value = _controller.value.copyWith(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
    return TextField(
      controller: _controller,
      onChanged: (v) => ref.read(adminProductSearchQueryProvider.notifier).state = v,
      decoration: InputDecoration(
        hintText: 'Search products…',
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () =>
                    ref.read(adminProductSearchQueryProvider.notifier).state = '',
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

/// Small floating pill on the admin grid card for a live fish — flips
/// `stock_quantity` between 0/1 (the same field checkout and the DB stock
/// triggers already read) so a fish sold face-to-face stops appearing
/// purchasable in the app immediately, with an Undo in case of a stray tap.
class _AvailabilityToggle extends StatelessWidget {
  final Product product;
  final WidgetRef ref;
  const _AvailabilityToggle({required this.product, required this.ref});

  @override
  Widget build(BuildContext context) {
    final available = !product.isOutOfStock;
    return Tooltip(
      message: available ? 'Mark as sold' : 'Mark as available',
      child: Material(
        // Red once sold — a "SOLD" tag reads at a glance, unlike a
        // same-color eye icon that just says "something toggled".
        color: available
            ? AppColors.black.withValues(alpha: 0.55)
            : AppColors.red,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _toggle(context, available),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              available ? Icons.sell_outlined : Icons.sell,
              size: 16,
              color: AppColors.white,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, bool wasAvailable) async {
    final newStock = wasAvailable ? 0 : 1;
    final repo = ProductRepository();
    await repo.updateProduct(product.id, {'stock_quantity': newStock});
    refreshAdminProducts(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            wasAvailable
                ? '${product.name} marked sold'
                : '${product.name} marked available',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await repo.updateProduct(product.id, {
                'stock_quantity': wasAvailable ? 1 : 0,
              });
              refreshAdminProducts(ref);
            },
          ),
        ),
      );
  }
}
