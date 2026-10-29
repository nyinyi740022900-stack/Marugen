import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../shop/presentation/shop_providers.dart';

/// Full list of low-stock products — reached from the dashboard's
/// "LOW STOCK" section via "See all" once it has more than a few rows.
class AdminLowStockScreen extends ConsumerWidget {
  const AdminLowStockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lowStockAsync = ref.watch(lowStockProductsProvider);

    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: AppBar(title: const Text('LOW STOCK')),
      body: lowStockAsync.when(
        data: (products) {
          if (products.isEmpty) {
            return const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'All stocked up',
              subtitle: 'Nothing low on stock right now.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final product = products[i];
              return Container(
                decoration: BoxDecoration(
                  color: AppPalette.of(context).surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: AppShadows.card,
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    onTap: () => context.push('/admin/products/${product.id}'),
                    leading: Icon(
                      Icons.warning_amber_rounded,
                      color: AppPalette.of(context).warning,
                    ),
                    title: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: Text(
                      '${product.availableStock} left',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppPalette.of(context).error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => Center(
          child: CircularProgressIndicator(
            color: AppPalette.of(context).accent,
          ),
        ),
        error: (e, _) =>
            ErrorState(onRetry: () => ref.invalidate(lowStockProductsProvider)),
      ),
    );
  }
}
