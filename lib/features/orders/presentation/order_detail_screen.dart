import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/product.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../admin/delivery/delivery_repository.dart';
import '../../cart/presentation/cart_providers.dart';
import '../../shop/presentation/shell_tab_provider.dart';
import '../../shop/presentation/shop_providers.dart';
import '../utils/receipt_generator.dart';
import 'order_status_timeline.dart';
import 'orders_providers.dart';

/// Full detail view for a single order — pushed from [OrdersScreen].
/// The [order] is normally passed straight through via `GoRouter`'s
/// `extra` (it's already fully loaded, items included, from
/// `OrderRepository.fetchMyOrders`), avoiding a second query. If it's
/// missing (e.g. a deep link), it's re-fetched by [orderId].
class OrderDetailScreen extends ConsumerWidget {
  final String orderId;
  final Order? order;

  /// True when arriving straight from a successful checkout — shows a
  /// one-time "order placed" banner instead of a separate confirmation
  /// screen, so there's a clear acknowledgment without duplicating this
  /// screen's content elsewhere.
  final bool justPlaced;

  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.order,
    this.justPlaced = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (order != null) {
      return _OrderDetailScaffold(order: order!, justPlaced: justPlaced);
    }

    final orderAsync = ref.watch(orderByIdProvider(orderId));
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: const Text('Order Detail'),
        actions: [
          orderAsync.maybeWhen(
            data: (o) => o == null ? const SizedBox.shrink() : _ShareReceiptButton(order: o),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: orderAsync.when(
        data: (o) {
          if (o == null) {
            return const Center(child: Text('Order not found.'));
          }
          return _OrderDetailBody(order: o, justPlaced: justPlaced);
        },
        loading: () => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: const [
            ListRowSkeleton(),
            SizedBox(height: AppSpacing.lg),
            ListRowSkeleton(),
          ],
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _OrderDetailScaffold extends StatelessWidget {
  final Order order;
  final bool justPlaced;
  const _OrderDetailScaffold({required this.order, this.justPlaced = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: Text(justPlaced ? 'Order Placed' : 'Order #${order.id.substring(0, 8)}'),
        automaticallyImplyLeading: !justPlaced,
        actions: [_ShareReceiptButton(order: order)],
      ),
      body: _OrderDetailBody(order: order, justPlaced: justPlaced),
    );
  }
}

class _OrderDetailBody extends ConsumerWidget {
  final Order order;
  final bool justPlaced;
  const _OrderDetailBody({required this.order, this.justPlaced = false});

  String _shortId(String id) => id.length > 18 ? '${id.substring(0, 18)}…' : id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shipping = order.shippingAddress;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (justPlaced) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success, size: 28),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Thank you — order placed!',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        "We'll notify you as your order is packed and shipped.",
                        style: TextStyle(fontSize: 12.5, color: AppColors.grey.withValues(alpha: 0.9)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Container(
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
                  Text('Order #${order.id.substring(0, 8)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  _StatusBadge(status: order.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(DateFormat.yMMMd().add_jm().format(order.createdAt),
                  style: const TextStyle(color: AppColors.grey, fontSize: 12.5)),
              if (order.stripePaymentIntentId != null &&
                  order.stripePaymentIntentId!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Payment: ${_shortId(order.stripePaymentIntentId!)}',
                  style: const TextStyle(color: AppColors.grey, fontSize: 12.5),
                ),
              ],
              if (order.qxpressTrackingNo != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.local_shipping_outlined, size: 15, color: AppColors.red),
                    const SizedBox(width: 4),
                    Text('Tracking: ${order.qxpressTrackingNo}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (order.qxpressTrackingNo != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _TrackingStatusCard(order: order),
        ],
        const SizedBox(height: AppSpacing.lg),
        OrderStatusTimeline(status: order.status),
        const SizedBox(height: AppSpacing.lg),
        if (shipping != null) ...[
          const Text('SHIPPING ADDRESS',
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.8, color: AppColors.grey)),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shipping['recipient_name'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(shipping['phone'] as String? ?? '',
                    style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  [
                    shipping['line1'],
                    shipping['line2'],
                    shipping['city'],
                    shipping['postal_code'],
                  ].where((e) => e != null && (e as String).isNotEmpty).join(', '),
                  style: const TextStyle(fontSize: 13.5, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        const Text('ITEMS',
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.8, color: AppColors.grey)),
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
              for (final item in order.items)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.productName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            if (item.variantLabel != null && item.variantLabel!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(item.variantLabel!,
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.grey)),
                            ],
                            const SizedBox(height: 2),
                            Text('Qty ${item.quantity} × S\$${item.unitPrice.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12.5, color: AppColors.grey)),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text('S\$${item.subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    ],
                  ),
                ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              if (order.discountAmount != null && order.discountAmount! > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        order.promoCode != null
                            ? 'Promo discount (${order.promoCode})'
                            : 'Promo discount',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
                      ),
                      Text('-S\$${order.discountAmount!.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.red)),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.grey)),
                    Text('S\$${order.total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: AppColors.black, fontSize: 18)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (justPlaced)
          const _ContinueShoppingButton()
        else ...[
          if (order.status == OrderStatus.pending || order.status == OrderStatus.paid) ...[
            _CancelOrderButton(order: order),
            const SizedBox(height: AppSpacing.lg),
          ],
          _ReorderButton(order: order),
        ],
      ],
    );
  }
}

/// Shown instead of Cancel/Reorder right after checkout — Reorder makes no
/// sense for an order the customer just placed, and this is the clearest
/// path back into the shop (no dead-end on the confirmation state).
class _ContinueShoppingButton extends ConsumerWidget {
  const _ContinueShoppingButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          ref.read(customerTabIndexProvider.notifier).state = 0;
          context.go('/');
        },
        icon: const Icon(Icons.storefront_outlined, size: 18),
        label: const Text('Continue Shopping'),
      ),
    );
  }
}

/// Re-adds an order's items to the cart. Live fish (koi/arowana) are
/// unique, single-stock items — if one from this order was already sold
/// or is otherwise unavailable, it's skipped with a warning rather than
/// silently added. Regular restockable items (fish food, accessories) are
/// added normally.
class _ReorderButton extends ConsumerStatefulWidget {
  final Order order;
  const _ReorderButton({required this.order});

  @override
  ConsumerState<_ReorderButton> createState() => _ReorderButtonState();
}

class _ReorderButtonState extends ConsumerState<_ReorderButton> {
  bool _loading = false;

  Future<void> _reorder() async {
    setState(() => _loading = true);
    final repo = ref.read(productRepositoryProvider);
    final cart = ref.read(cartProvider.notifier);

    var added = 0;
    var skipped = 0;
    for (final item in widget.order.items) {
      final product = await repo.fetchProductById(item.productId);
      if (product == null) {
        skipped++;
        continue;
      }
      if (product.isLiveFish && (product.isSold || product.stockQuantity <= 0)) {
        // This exact fish is gone — can't reorder a unique animal.
        skipped++;
        continue;
      }
      // Try to re-select the same variant by label (ids are stable, but
      // matching by label is more forgiving if variants were recreated).
      // If it's gone, fall back to the base product rather than skipping
      // the whole line.
      final matchingVariants = item.variantLabel == null
          ? const <ProductVariant>[]
          : product.variants.where((v) => v.label == item.variantLabel);
      final variant = matchingVariants.isNotEmpty ? matchingVariants.first : null;
      final result = cart.add(product,
          quantity: product.isLiveFish ? 1 : item.quantity, variant: variant);
      if (result == CartAddResult.outOfStock) {
        skipped++;
      } else {
        added++;
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);

    final message = skipped == 0
        ? 'Added $added item${added == 1 ? '' : 's'} to cart'
        : 'Added $added item${added == 1 ? '' : 's'} — $skipped no longer available';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    if (added > 0) context.push('/cart');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _reorder,
        icon: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.black),
              )
            : const Icon(Icons.replay, size: 18),
        label: const Text('Reorder'),
      ),
    );
  }
}

/// Lets the customer cancel their own order while it's still `pending` or
/// `paid` — RLS (0007_customer_order_cancel.sql) only allows the update to
/// land once it's already `packing`/`shipped`/`delivered`, so this button
/// only ever shows for the earlier statuses (see the caller's guard).
class _CancelOrderButton extends ConsumerStatefulWidget {
  final Order order;
  const _CancelOrderButton({required this.order});

  @override
  ConsumerState<_CancelOrderButton> createState() => _CancelOrderButtonState();
}

class _CancelOrderButtonState extends ConsumerState<_CancelOrderButton> {
  bool _loading = false;

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text(
            'This cannot be undone. Refunds (if already paid) are handled by the shop.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Order')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Order', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await ref.read(orderRepositoryProvider).cancelMyOrder(widget.order.id);
      ref.invalidate(myOrdersProvider);
      ref.invalidate(orderByIdProvider(widget.order.id));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Order cancelled.')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not cancel order: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _cancel,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error, width: 1.2),
        ),
        icon: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error),
              )
            : const Icon(Icons.cancel_outlined, size: 18),
        label: const Text('Cancel Order'),
      ),
    );
  }
}

/// Shares a plain-text receipt/tax invoice for [order] via the platform
/// share sheet.
class _ShareReceiptButton extends ConsumerWidget {
  final Order order;
  const _ShareReceiptButton({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Share Receipt',
      icon: const Icon(Icons.ios_share),
      onPressed: () async {
        try {
          final settings = await ref.read(shopSettingsProvider.future);
          final text = buildReceiptText(order: order, settings: settings);
          await SharePlus.instance.share(ShareParams(
            text: text,
            subject: 'Receipt — Order #${order.id.substring(0, 8)}',
          ));
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Could not share receipt: $e')));
          }
        }
      },
    );
  }
}

/// Live carrier status pulled from 17TRACK (via `track-register` when the
/// admin ships the order, kept fresh by `track-webhook` pushes, and
/// refreshable on demand here with `track-status`).
class _TrackingStatusCard extends ConsumerStatefulWidget {
  final Order order;
  const _TrackingStatusCard({required this.order});

  @override
  ConsumerState<_TrackingStatusCard> createState() => _TrackingStatusCardState();
}

class _TrackingStatusCardState extends ConsumerState<_TrackingStatusCard> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await DeliveryRepository().refreshTrackingStatus(widget.order.id);
      ref.invalidate(orderByIdProvider(widget.order.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not refresh: $e')));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final hasStatus = order.trackingStatus != null && order.trackingStatus!.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.redSoft,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.track_changes, size: 18, color: AppColors.red),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hasStatus ? order.trackingStatus! : 'Awaiting carrier update',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                if (order.trackingStatusDetail != null) ...[
                  const SizedBox(height: 2),
                  Text(order.trackingStatusDetail!,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.grey)),
                ],
                if (order.trackingUpdatedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Updated ${DateFormat.yMMMd().add_jm().format(order.trackingUpdatedAt!)}',
                    style: const TextStyle(fontSize: 11, color: AppColors.greySoft),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh tracking',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.red),
                  )
                : const Icon(Icons.refresh, size: 20, color: AppColors.grey),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final OrderStatus status;
  const _StatusBadge({required this.status});

  Color get _color {
    switch (status) {
      case OrderStatus.delivered:
        return AppColors.success;
      case OrderStatus.cancelled:
      case OrderStatus.refunded:
        return AppColors.error;
      case OrderStatus.pending:
        return AppColors.warning;
      default:
        return AppColors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: _color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Text(
        orderStatusLabel(status),
        style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
