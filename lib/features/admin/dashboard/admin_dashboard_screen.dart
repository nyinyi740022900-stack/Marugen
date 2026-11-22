import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/product.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/utils/price_format.dart';
import '../../../shared/widgets/notification_bell_button.dart';
import '../../orders/data/order_repository.dart'
    show
        AdminOrderSummary,
        AdminPaymentsSummary,
        StuckPendingOrders,
        TopProductSales;
import '../../orders/presentation/orders_providers.dart';
import '../../orders/presentation/staff_order_confirmations.dart';
import '../../orders/utils/checkout_totals.dart';
import '../../shop/presentation/shop_providers.dart';
import '../admin_shell.dart';
import '../delivery/admin_delivery_screen.dart'
    show
        FulfillmentSegment,
        fulfillmentSegmentContains,
        fulfillmentSegmentProvider;
import '../../../shared/utils/error_message.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/section_label.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(adminAllProductsProvider);
    final recentAsync = ref.watch(adminRecentOrdersProvider);
    final stuckAsync = ref.watch(adminStuckPendingOrdersProvider);
    final paymentsAsync = ref.watch(adminPaymentsSummaryProvider);
    final summaryAsync = ref.watch(adminOrderSummaryProvider);
    final topProductsAsync = ref.watch(adminTopProductsProvider);
    final lowStockAsync = ref.watch(lowStockProductsProvider);
    final queueAsync = ref.watch(fulfillmentOrdersProvider);

    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: AppBar(
        title: const Text('Home'),
        actions: const [NotificationBellButton(), SizedBox(width: 4)],
      ),
      body: RefreshIndicator(
        color: AppPalette.of(context).accent,
        onRefresh: () async {
          refreshAdminProducts(ref);
          refreshAdminOrders(ref);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // What needs a person today, before any revenue number.
            _TodayQueue(ordersAsync: queueAsync),
            const SizedBox(height: AppSpacing.xl),
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
                        ref.read(adminTabIndexProvider.notifier).state =
                            kAdminProductsTab,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _StatCard(
                    // Unpaid checkouts plus paid orders not yet packed.
                    label: 'Open Orders',
                    value: summaryAsync.maybeWhen(
                      data: (summary) => '${summary.openOrders}',
                      orElse: () => '—',
                    ),
                    icon: Icons.pending_actions_outlined,
                    accent: true,
                    // Orders tab.
                    onTap: () =>
                        ref.read(adminTabIndexProvider.notifier).state =
                            kAdminOrdersTab,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _SalesCard(
              summaryAsync: summaryAsync,
              paymentsAsync: paymentsAsync,
              // Orders tab: the orders are what the figure is made of.
              onOpenOrders: () =>
                  ref.read(adminTabIndexProvider.notifier).state =
                      kAdminOrdersTab,
              onRetry: () {
                ref.invalidate(adminOrderSummaryProvider);
                ref.invalidate(adminAllOrdersProvider);
                ref.invalidate(adminPaymentsSummaryProvider);
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            stuckAsync.maybeWhen(
              data: (stuck) => stuck.orders.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                      child: _StuckPendingSection(stuck: stuck),
                    ),
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
            Row(
              children: [
                const SectionLabel('TOP PRODUCTS'),
                const Spacer(),
                topProductsAsync.maybeWhen(
                  data: (ranked) => ranked.length > _TopProductsCard.maxRows
                      ? TextButton(
                          onPressed: () => context.push('/admin/top-products'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text(
                            'See all',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            topProductsAsync.when(
              data: (ranked) => _TopProductsCard(ranked: ranked),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => InlineErrorState(
                message: friendlyErrorMessage(
                  e,
                  fallback: 'Could not load top products.',
                  context: 'admin.dashboard',
                ),
                onRetry: () {
                  ref.invalidate(adminAllOrdersProvider);
                  ref.invalidate(adminTopProductsProvider);
                },
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('RECENT ORDERS'),
            const SizedBox(height: AppSpacing.sm),
            recentAsync.when(
              data: (recent) {
                if (recent.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: AppPalette.of(context).surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'No orders yet.',
                      style: TextStyle(color: AppPalette.of(context).textMuted),
                    ),
                  );
                }
                return Container(
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: AppShadows.card,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    color: AppPalette.of(context).surface,
                    child: Column(
                      children: [
                        for (var i = 0; i < recent.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, indent: 16, endIndent: 16),
                          _OrderRow(order: recent[i]),
                        ],
                      ],
                    ),
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => InlineErrorState(
                message: friendlyErrorMessage(
                  e,
                  fallback: 'Could not load orders.',
                  context: 'admin.dashboard',
                ),
                onRetry: () => ref.invalidate(adminRecentOrdersProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one money card on Home: sales after refunds, the last seven days,
/// and how much of it came through Stripe from how many paid orders.
///
/// The total is `admin_order_summary`; the Stripe line is
/// `admin_payments_summary`, shown as its own amount only when it differs
/// (an order paid outside Stripe), so a Stripe-only shop does not read the
/// same number twice. Opens Orders. When the total cannot be loaded the
/// card says so and offers Retry instead of a bare dash.
class _SalesCard extends ConsumerWidget {
  final AsyncValue<AdminOrderSummary> summaryAsync;
  final AsyncValue<AdminPaymentsSummary> paymentsAsync;
  final VoidCallback onOpenOrders;
  final VoidCallback onRetry;
  const _SalesCard({
    required this.summaryAsync,
    required this.paymentsAsync,
    required this.onOpenOrders,
    required this.onRetry,
  });

  static String paidOrders(int count) =>
      count == 1 ? '1 paid order' : '$count paid orders';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(shopSettingsProvider).valueOrNull;
    final palette = AppPalette.of(context);
    final summaryFailed = summaryAsync.hasError && !summaryAsync.isLoading;
    final summary = summaryFailed ? null : summaryAsync.valueOrNull;
    final paymentsFailed = paymentsAsync.hasError && !paymentsAsync.isLoading;
    final payments = paymentsFailed ? null : paymentsAsync.valueOrNull;
    final muted = TextStyle(fontSize: 12, color: palette.textMuted);

    final String? stripeLine;
    if (summary == null || payments == null) {
      stripeLine = null;
    } else if ((payments.collected - summary.totalRevenue).abs() >= 0.005) {
      stripeLine =
          '${formatPrice(payments.collected)} of this was collected through '
          'Stripe · ${paidOrders(payments.transactionCount)}';
    } else {
      stripeLine = paidOrders(payments.transactionCount);
    }

    Widget retryRow(String message) => Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 12.5, color: palette.error),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );

    return Semantics(
      container: true,
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onOpenOrders,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: kMinInteractiveDimension,
            ),
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: AppShadows.card,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: palette.accentSoft,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    color: palette.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sales after refunds',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (summaryFailed)
                        retryRow(
                          'Could not load sales. Check your connection and '
                          'try again.',
                        )
                      else ...[
                        Text(
                          summary == null
                              ? '—'
                              : formatPrice(summary.totalRevenue),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: palette.text,
                          ),
                        ),
                        if (summary != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Last 7 days: ${formatPrice(summary.weekRevenue)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: palette.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(salesIncludesCaption(settings), style: muted),
                        ],
                        if (stripeLine != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(stripeLine, style: muted),
                        ],
                        if (paymentsFailed)
                          retryRow('Could not load the Stripe figure.'),
                      ],
                    ],
                  ),
                ),
                if (!summaryFailed)
                  Icon(Icons.chevron_right, size: 20, color: palette.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
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
            const SectionLabel('LOW STOCK'),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppPalette.of(context).error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '${products.length}',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppPalette.of(context).error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            if (hasMore)
              TextButton(
                onPressed: () => context.push('/admin/low-stock'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text(
                  'See all',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: AppPalette.of(context).surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: AppShadows.card,
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: AppPalette.of(context).surface,
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  _LowStockRow(product: shown[i]),
                ],
                if (hasMore) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    dense: true,
                    onTap: () => context.push('/admin/low-stock'),
                    title: Text(
                      '+${products.length - shown.length} more',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppPalette.of(context).textMuted,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppPalette.of(context).textMuted,
                    ),
                  ),
                ],
              ],
            ),
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
      leading: Icon(
        Icons.warning_amber_rounded,
        size: 20,
        color: AppPalette.of(context).warning,
      ),
      title: Text(
        product.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
      trailing: Text(
        '${product.availableStock} left',
        style: TextStyle(
          fontSize: 12.5,
          color: AppPalette.of(context).error,
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
  final StuckPendingOrders stuck;
  const _StuckPendingSection({required this.stuck});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = stuck.orders;
    final notShown = stuck.total - orders.length;
    // At large text sizes "Cancel now" no longer fits beside the order
    // number, so it moves under it instead of squeezing the row.
    final stacked = MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3;
    Widget cancelButton(Order order) => TextButton(
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final confirmed = await confirmCancelOrder(context, order);
        if (!confirmed) return;
        try {
          await ref
              .read(orderRepositoryProvider)
              .updateOrderStatus(order.id, OrderStatus.cancelled);
        } catch (_) {
          // Server refuses while the payment may still complete.
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'The order was not cancelled. Its payment may still be processing; refresh and try again.',
              ),
            ),
          );
        }
        if (!context.mounted) return;
        refreshAdminOrders(ref);
      },
      child: const Text('Cancel now'),
    );
    Widget age(Order order) => Text(
      '${formatPrice(order.total)} · created '
      '${timeAgoLabel(DateTime.now().difference(order.createdAt))}',
      style: const TextStyle(fontSize: 12),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 16,
              color: AppPalette.of(context).warning,
            ),
            const SizedBox(width: 6),
            const Flexible(child: SectionLabel('STUCK PENDING ORDERS')),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppPalette.of(context).error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '${stuck.total}',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppPalette.of(context).error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Stock stays reserved until payment cancellation is confirmed. '
          'Refresh or cancel the order to check its latest payment status.',
          style: TextStyle(
            fontSize: 12,
            color: AppPalette.of(context).textMuted,
            height: 1.3,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: AppPalette.of(context).surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: AppShadows.card,
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: AppPalette.of(context).surface,
            child: Column(
              children: [
                for (var i = 0; i < orders.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    dense: true,
                    onTap: () => context.push('/orders/${orders[i].id}'),
                    leading: Icon(
                      Icons.hourglass_bottom,
                      size: 20,
                      color: AppPalette.of(context).warning,
                    ),
                    title: Text(
                      '#${orders[i].displayNumber}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: stacked
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [age(orders[i]), cancelButton(orders[i])],
                          )
                        : age(orders[i]),
                    trailing: stacked ? null : cancelButton(orders[i]),
                  ),
                ],
                if (notShown > 0) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    dense: true,
                    // Orders tab, All pane, filtered to Pending.
                    onTap: () {
                      ref.read(adminOrderStatusFilterProvider.notifier).state =
                          OrderStatus.pending;
                      ref.read(requestedOrdersTabProvider.notifier).state = 0;
                      ref.read(adminTabIndexProvider.notifier).state =
                          kAdminOrdersTab;
                    },
                    title: Text(
                      '+$notShown more in Orders',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppPalette.of(context).textMuted,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppPalette.of(context).textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Top products by units sold (see [adminTopProductsProvider]). Renders an
/// empty state rather than nothing when there isn't enough order data yet.
/// Only shows the top [maxRows] on the dashboard home to avoid the list
/// growing unbounded as more products sell — "See all" (above) opens the
/// full ranking on its own page instead.
class _TopProductsCard extends StatelessWidget {
  static const maxRows = 5;

  final List<TopProductSales> ranked;
  const _TopProductsCard({required this.ranked});

  @override
  Widget build(BuildContext context) {
    final top = ranked.take(maxRows).toList();
    final hasMore = ranked.length > top.length;

    if (top.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppPalette.of(context).surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        alignment: Alignment.center,
        child: Text(
          'Not enough order data yet.',
          style: TextStyle(color: AppPalette.of(context).textMuted),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppPalette.of(context).surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: AppPalette.of(context).surface,
        child: Column(
          children: [
            for (var i = 0; i < top.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                dense: true,
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
                  top[i].name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                trailing: Text(
                  '${top[i].units} sold',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppPalette.of(context).textMuted,
                  ),
                ),
              ),
            ],
            if (hasMore) ...[
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                dense: true,
                onTap: () => context.push('/admin/top-products'),
                title: Text(
                  '+${ranked.length - top.length} more',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppPalette.of(context).textMuted,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppPalette.of(context).textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "40 min ago", "5 hours ago", "3 days ago": how long ago, in the largest
/// unit that fits, for rows where the age is the point.
String timeAgoLabel(Duration age) {
  if (age.inMinutes < 1) return 'just now';
  if (age.inMinutes < 60) return '${age.inMinutes} min ago';
  if (age.inHours < 24) {
    return age.inHours == 1 ? '1 hour ago' : '${age.inHours} hours ago';
  }
  return age.inDays == 1 ? '1 day ago' : '${age.inDays} days ago';
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
      color: accent ? AppColors.black : AppPalette.of(context).surface,
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
                      ? AppPalette.of(context).accent.withValues(alpha: 0.18)
                      : AppPalette.of(context).accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  icon,
                  color: AppPalette.of(context).accent,
                  size: 20,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                value,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: accent ? AppColors.white : AppPalette.of(context).text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: accent
                      ? AppColors.white.withValues(alpha: 0.7)
                      : AppPalette.of(context).textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One recent order: opens the order, and says who it is for and where
/// it stands in the same words as the Orders tab.
class _OrderRow extends StatelessWidget {
  final Order order;
  const _OrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final recipient =
        (order.shippingAddress?['recipient_name'] as String?)?.trim() ?? '';
    final title = recipient.isEmpty
        ? '#${order.displayNumber}'
        : '#${order.displayNumber} · $recipient';
    final status = order.staffFulfillmentStatusLabel;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () => context.push('/orders/${order.id}'),
        child: Padding(
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
                  color: palette.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: 18,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatPrice(order.total),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: palette.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // Under the title, not beside it: the label can be a
                    // phrase ("Awaiting courier pickup") and must not
                    // squeeze the name at large text sizes.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: palette.accentSoft,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: palette.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today's work as tappable counters, each opening Fulfillment on that
/// segment. Cancellation requests count as attention: they pause delivery
/// and were otherwise visible only inside individual orders.
class _TodayQueue extends ConsumerWidget {
  final AsyncValue<List<Order>> ordersAsync;
  const _TodayQueue({required this.ordersAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final orders = ordersAsync.valueOrNull ?? const <Order>[];
    int count(FulfillmentSegment s) =>
        orders.where((o) => fulfillmentSegmentContains(o, s)).length;
    final tiles = [
      (FulfillmentSegment.toPack, 'To pack', Icons.inventory_outlined),
      (FulfillmentSegment.toShip, 'To ship', Icons.local_shipping_outlined),
      (FulfillmentSegment.inTransit, 'In transit', Icons.route_outlined),
      (
        FulfillmentSegment.attention,
        'Needs attention',
        Icons.report_problem_outlined,
      ),
    ];
    void open(FulfillmentSegment s) {
      ref.read(fulfillmentSegmentProvider.notifier).state = s;
      ref.read(requestedOrdersTabProvider.notifier).state = 1;
      ref.read(adminTabIndexProvider.notifier).state = kAdminOrdersTab;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TODAY',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: palette.textMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 640 ? 4 : 2;
            final width =
                (constraints.maxWidth - AppSpacing.md * (columns - 1)) /
                columns;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final (segment, label, icon) in tiles)
                  SizedBox(
                    width: width,
                    child: _QueueTile(
                      label: label,
                      icon: icon,
                      count: ordersAsync.hasValue ? count(segment) : null,
                      urgent:
                          segment == FulfillmentSegment.attention &&
                          count(segment) > 0,
                      onTap: () => open(segment),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _QueueTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final int? count;
  final bool urgent;
  final VoidCallback onTap;
  const _QueueTile({
    required this.label,
    required this.icon,
    required this.count,
    required this.urgent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = urgent ? palette.error : palette.text;
    return Semantics(
      button: true,
      label: '$label, ${count ?? 'loading'}',
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: urgent ? palette.error : palette.border,
                width: urgent ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: urgent ? color : palette.textMuted),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        count == null ? '—' : '$count',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: color,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
