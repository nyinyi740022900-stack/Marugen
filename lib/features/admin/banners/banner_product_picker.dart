import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/product.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../shop/presentation/shop_providers.dart';

/// Lets the owner choose the product a banner opens, by name instead of by
/// typing its id. Returns null when closed without choosing.
Future<Product?> showBannerProductPicker(BuildContext context) {
  return Navigator.of(context).push<Product>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const BannerProductPickerScreen(),
    ),
  );
}

class BannerProductPickerScreen extends ConsumerStatefulWidget {
  const BannerProductPickerScreen({super.key});

  @override
  ConsumerState<BannerProductPickerScreen> createState() =>
      _BannerProductPickerScreenState();
}

class _BannerProductPickerScreenState
    extends ConsumerState<BannerProductPickerScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final query = _search.text.trim().toLowerCase();
    // Every product whatever the Products tab is filtered to, searched with
    // the same rule as that tab.
    final productsAsync = ref.watch(adminAllProductsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a product')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: TextField(
              controller: _search,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search products…',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(_search.clear),
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: palette.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: productsAsync.when(
              loading: () => ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: const [
                  ListRowSkeleton(),
                  SizedBox(height: AppSpacing.md),
                  ListRowSkeleton(),
                ],
              ),
              error: (_, _) => ErrorState(
                onRetry: () => ref.invalidate(adminAllProductsProvider),
              ),
              data: (products) {
                final matches = query.isEmpty
                    ? products
                    : products
                          .where((p) => productMatchesSearch(p, query))
                          .toList();
                if (matches.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: products.isEmpty ? 'No products yet' : 'No matches',
                    subtitle: products.isEmpty
                        ? 'Add a product first, then link the banner to it.'
                        : 'Try another name or variety.',
                  );
                }
                return ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom + 16,
                  ),
                  itemCount: matches.length,
                  itemBuilder: (context, i) {
                    final product = matches[i];
                    return ListTile(
                      title: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        product.isOutOfStock
                            ? '${categoryLabel(product.category)} · '
                                  '${product.unavailableLabel}'
                            : categoryLabel(product.category),
                        style: TextStyle(color: palette.textMuted),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, product),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
