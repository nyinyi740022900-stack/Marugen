import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../orders/presentation/orders_providers.dart';
import 'admin_dashboard_screen.dart' show rankTopProducts;

/// Full product-sales ranking — the "See all" destination from the
/// dashboard's capped Top Products preview (see admin_dashboard_screen.dart).
class AdminTopProductsScreen extends ConsumerWidget {
  const AdminTopProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(adminOrdersProvider);
    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: AppBar(title: const Text('Top Products')),
      body: ordersAsync.when(
        data: (orders) {
          final ranked = rankTopProducts(orders);
          if (ranked.isEmpty) {
            return const EmptyState(
              icon: Icons.bar_chart_outlined,
              title: 'Not enough order data yet',
              subtitle:
                  'Product rankings will show up here once orders come in.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: ranked.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              return ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: AppPalette.of(context).accentSoft,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: AppPalette.of(context).accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                title: Text(
                  ranked[i].key,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: Text(
                  '${ranked[i].value} sold',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppPalette.of(context).textMuted,
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
            ErrorState(onRetry: () => ref.invalidate(adminOrdersProvider)),
      ),
    );
  }
}
