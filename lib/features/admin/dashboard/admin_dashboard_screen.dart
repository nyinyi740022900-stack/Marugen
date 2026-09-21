import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/product.dart';
import '../../../shared/utils/price_format.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/notification_bell_button.dart';
import '../../orders/presentation/orders_providers.dart';
import '../../shop/presentation/shop_providers.dart';
import '../admin_shell.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productListProvider);
    final ordersAsync = ref.watch(adminOrdersProvider);
    final lowStockAsync = ref.watch(lowStockProductsProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: const Text('DASHBOARD'),
        actions: const [NotificationBellButton(), SizedBox(width: 4)],
      ),
      body: RefreshIndicator(
        color: AppColors.red,
        onRefresh: () async {
          refreshAdminProducts(ref);
          refreshAdminOrders(ref);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Products',
                    value: productsAsync.maybeWhen(
                      data: (p) => '${p.length}',
                      orElse: () => '—',
                    ),
                    icon: Icons.inventory_2_outlined,
                    // Products tab.
                    onTap: () =>
                        ref.read(adminTabIndexProvider.notifier).state = 1,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _StatCard(
                    label: 'Pending Orders',
                    value: ordersAsync.maybeWhen(
                      data: (orders) =>
                          '${orders.where((o) => o.status.name == 'pending' || o.status.name == 'paid').length}',
                      orElse: () => '—',
                    ),
                    icon: Icons.pending_actions_outlined,
                    accent: true,
                    // Orders tab.
                    onTap: () =>
                        ref.read(adminTabIndexProvider.notifier).state = 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Total Revenue',
                    value: ordersAsync.maybeWhen(
                      data: (orders) =>
                          'S\$${_totalRevenue(orders).toStringAsFixed(0)}',
                      orElse: () => '—',
                    ),
                    icon: Icons.account_balance_wallet_outlined,
                    // Analytics tab (index 7, under More).
                    onTap: () =>
                        ref.read(adminTabIndexProvider.notifier).state = 7,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _StatCard(
                    label: 'Revenue This Week',
                    value: ordersAsync.maybeWhen(
                      data: (orders) =>
                          'S\$${_revenueThisWeek(orders).toStringAsFixed(0)}',
                      orElse: () => '—',
                    ),
                    icon: Icons.trending_up,
                    accent: true,
                    onTap: () =>
                        ref.read(adminTabIndexProvider.notifier).state = 7,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            ordersAsync.maybeWhen(
              data: (orders) {
                final stuck = orders
                    .where(
                      (o) =>
                          o.status == OrderStatus.pending &&
                          DateTime.now().difference(o.createdAt) >
                              const Duration(minutes: 30),
                    )
                    .toList();
                return stuck.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                        child: _StuckPendingSection(orders: stuck),
                      );
              },
              orElse: () => const SizedBox.shrink(),
            ),
            lowStockAsync.maybeWhen(
              data: (products) => products.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                      child: _LowStockSection(products: products),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
            const Text(
              'TOP PRODUCTS',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
                color: AppColors.grey,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ordersAsync.when(
              data: (orders) => _TopProductsCard(orders: orders),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(
                'Error: $e',
                style: const TextStyle(color: AppColors.error),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'RECENT ORDERS',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
                color: AppColors.grey,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ordersAsync.when(
              data: (orders) {
                final recent = orders.take(5).toList();
                if (recent.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'No orders yet.',
                      style: TextStyle(color: AppColors.grey),
                    ),
                  );
                }
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: AppShadows.card,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < recent.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 16, endIndent: 16),
                        _OrderRow(order: recent[i]),
                      ],
                    ],
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(
                'Error: $e',
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sum of non-cancelled/refunded order totals.
  double _totalRevenue(List<Order> orders) {
    return orders
        .where(
          (o) =>
              o.status != OrderStatus.cancelled &&
              o.status != OrderStatus.refunded,
        )
        .fold(0.0, (sum, o) => sum + o.total);
  }

  double _revenueThisWeek(List<Order> orders) {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    return orders
        .where(
          (o) =>
              o.status != OrderStatus.cancelled &&
              o.status != OrderStatus.refunded &&
              o.createdAt.isAfter(weekAgo),
        )
        .fold(0.0, (sum, o) => sum + o.total);
  }
}

/// "LOW STOCK" — restockable products (fish food / accessories) at or
/// below the admin-configured threshold (Settings → Inventory). Live fish
/// are excluded since each one is a unique animal, not restockable
/// inventory. Only shows the worst [_maxRows] on the dashboard home to
/// avoid flooding the page — "See all" opens the full list.
class _LowStockSection extends StatelessWidget {
  static const _maxRows = 4;

  final List<Product> products;
  const _LowStockSection({required this.products});

  @override
  Widget build(BuildContext context) {
    final shown = products.take(_maxRows).toList();
    final hasMore = products.length > shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'LOW STOCK',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
                color: AppColors.grey,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '${products.length}',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            if (hasMore)
              GestureDetector(
                onTap: () => context.push('/admin/low-stock'),
                child: const Text(
                  'See all',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: AppColors.red,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: AppShadows.card,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                _LowStockRow(product: shown[i]),
              ],
              if (hasMore) ...[
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  dense: true,
                  onTap: () => context.push('/admin/low-stock'),
                  title: Text(
                    '+${products.length - shown.length} more',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.grey,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.grey,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LowStockRow extends StatelessWidget {
  final Product product;
  const _LowStockRow({required this.product});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: () => context.push('/admin/products/${product.id}'),
      leading: const Icon(
        Icons.warning_amber_rounded,
        size: 20,
        color: AppColors.warning,
      ),
      title: Text(
        product.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
      trailing: Text(
        '${product.availableStock} left',
        style: const TextStyle(
          fontSize: 12.5,
          color: AppColors.error,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Orders still `pending` (payment never confirmed) for more than 30
/// minutes. A scheduled job (see 0014_stale_order_cleanup.sql, runs every
/// 10 min) auto-cancels these on its own and releases any stock/live-fish
/// reservation they're holding — this section just gives admin visibility
/// into that happening, plus a manual "Cancel now" for anything they want
/// released immediately instead of waiting for the next sweep.
class _StuckPendingSection extends ConsumerWidget {
  final List<Order> orders;
  const _StuckPendingSection({required this.orders});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 16,
              color: AppColors.warning,
            ),
            const SizedBox(width: 6),
            const Text(
              'STUCK PENDING ORDERS',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
                color: AppColors.grey,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '${orders.length}',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Payment was never confirmed — any stock or live fish these hold '
          'is auto-released within ~40 min, or cancel now to free it sooner.',
          style: TextStyle(fontSize: 12, color: AppColors.grey, height: 1.3),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: AppShadows.card,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < orders.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  dense: true,
                  onTap: () => context.push('/orders/${orders[i].id}'),
                  leading: const Icon(
                    Icons.hourglass_bottom,
                    size: 20,
                    color: AppColors.warning,
                  ),
                  title: Text(
                    '#${orders[i].displayNumber}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  subtitle: Text(
                    '${formatPrice(orders[i].total)} · created '
                    '${DateTime.now().difference(orders[i].createdAt).inMinutes} min ago',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      final confirmed = await confirmDestructiveAction(
                        context,
                        title: 'Cancel this order?',
                        message:
                            'Order #${orders[i].displayNumber} will be cancelled and any reserved stock released. This cannot be undone.',
                        confirmLabel: 'Cancel Order',
                      );
                      if (!confirmed) return;
                      await ref
                          .read(orderRepositoryProvider)
                          .updateOrderStatus(
                            orders[i].id,
                            OrderStatus.cancelled,
                          );
                      refreshAdminOrders(ref);
                    },
                    child: const Text('Cancel now'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Top products by order-item quantity across all orders. Renders an
/// empty state rather than nothing when there isn't enough order data yet.
class _TopProductsCard extends StatelessWidget {
  final List<Order> orders;
  const _TopProductsCard({required this.orders});

  @override
  Widget build(BuildContext context) {
    final qtyByName = <String, int>{};
    for (final order in orders) {
      if (order.status == OrderStatus.cancelled) continue;
      for (final item in order.items) {
        qtyByName[item.productName] =
            (qtyByName[item.productName] ?? 0) + item.quantity;
      }
    }
    final ranked = qtyByName.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.take(5).toList();

    if (top.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Not enough order data yet.',
          style: TextStyle(color: AppColors.grey),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < top.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.redSoft,
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: AppColors.redDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              title: Text(
                top[i].key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              trailing: Text(
                '${top[i].value} sold',
                style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool accent;
  final VoidCallback? onTap;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.accent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent ? AppColors.black : AppColors.white,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent
                      ? AppColors.red.withValues(alpha: 0.18)
                      : AppColors.redSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, color: AppColors.red, size: 20),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                value,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: accent ? AppColors.white : AppColors.black,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: accent
                      ? AppColors.white.withValues(alpha: 0.7)
                      : AppColors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final Order order;
  const _OrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order.status.name;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.offWhite,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 18,
              color: AppColors.grey,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${order.displayNumber}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatPrice(order.total),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.redSoft,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              status.toUpperCase(),
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.redDark,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
