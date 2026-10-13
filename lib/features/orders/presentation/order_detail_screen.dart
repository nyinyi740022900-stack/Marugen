import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/content_width.dart';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/product.dart';
import '../../../shared/utils/price_format.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../admin/delivery/delivery_repository.dart';
import '../../admin/delivery/easyparcel_repository.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../cart/presentation/cart_providers.dart';
import '../../reviews/presentation/review_providers.dart';
import '../../reviews/presentation/reviews_section.dart' show openReviewForm;
import '../../shop/presentation/shell_tab_provider.dart';
import '../../shop/presentation/shop_providers.dart';
import '../utils/invoice_pdf.dart';
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
      backgroundColor: AppPalette.of(context).background,
      appBar: AppBar(
        title: const Text('Order Detail'),
        actions: [
          orderAsync.maybeWhen(
            data: (o) => o == null
                ? const SizedBox.shrink()
                : _OrderAppBarActions(order: o),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: orderAsync.when(
        data: (o) {
          if (o == null) {
            return EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Order not found',
              subtitle:
                  "It may have been removed, or you don't have access to it.",
              actionLabel: 'Back to Orders',
              onAction: () =>
                  context.canPop() ? context.pop() : context.go('/'),
            );
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
        error: (e, _) => ErrorState(
          onRetry: () => ref.invalidate(orderByIdProvider(orderId)),
        ),
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
      backgroundColor: AppPalette.of(context).background,
      appBar: AppBar(
        title: Text(
          justPlaced ? 'Order Placed' : 'Order #${order.displayNumber}',
        ),
        automaticallyImplyLeading: !justPlaced,
        actions: [_OrderAppBarActions(order: order)],
      ),
      body: ContentWidth(
        maxWidth: 760,
        child: _OrderDetailBody(order: order, justPlaced: justPlaced),
      ),
    );
  }
}

class _OrderDetailBody extends ConsumerWidget {
  final Order order;
  final bool justPlaced;
  const _OrderDetailBody({required this.order, this.justPlaced = false});

  String _shortId(String id) => id.length > 18 ? '${id.substring(0, 18)}…' : id;

  void _copyAddress(BuildContext context, Map<String, dynamic> shipping) {
    final text = [
      shipping['recipient_name'],
      shipping['phone'],
      shipping['line1'],
      shipping['line2'],
      shipping['city'],
      shipping['postal_code'],
    ].whereType<String>().where((s) => s.isNotEmpty).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Address copied')));
  }

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
              color: AppPalette.of(context).success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppPalette.of(context).success.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: AppPalette.of(context).success,
                  size: 28,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Thank you — order placed!',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "We'll notify you as your order is packed and shipped.",
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppPalette.of(context).textMuted
                              .withValues(alpha: 0.9),
                        ),
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
            color: AppPalette.of(context).surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Order #${order.displayNumber}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  _StatusBadge(status: order.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                DateFormat.yMMMd().add_jm().format(order.createdAt),
                style: TextStyle(
                  color: AppPalette.of(context).textMuted,
                  fontSize: 12.5,
                ),
              ),
              if (order.stripePaymentIntentId != null &&
                  order.stripePaymentIntentId!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Payment: ${_shortId(order.stripePaymentIntentId!)}',
                  style: TextStyle(
                    color: AppPalette.of(context).textMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
              if (order.qxpressTrackingNo != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.local_shipping_outlined,
                      size: 15,
                      color: AppPalette.of(context).accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Tracking: ${order.qxpressTrackingNo}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              try {
                await shareReceipt(ref, order);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Could not open the invoice. Please try again.',
                      ),
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.description_outlined, size: 17),
            label: const Text('View / Download Invoice'),
          ),
        ),
        if (order.qxpressTrackingNo != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _TrackingStatusCard(order: order),
        ],
        const SizedBox(height: AppSpacing.lg),
        OrderStatusTimeline(
          status: order.status,
          trackingProvider: order.trackingProvider,
          trackingStatusCode: order.trackingStatusCode,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (shipping != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SHIPPING ADDRESS',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.8,
                  color: AppPalette.of(context).textMuted,
                ),
              ),
              // Admin-only: staff copying an address to paste into a
              // courier's own app/label almost always needs it as one
              // block of text, not retyped field-by-field from the screen.
              if (ref.watch(currentAppUserProvider).valueOrNull?.role.isAdmin ??
                  false)
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () => _copyAddress(context, shipping),
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 13,
                          color: AppPalette.of(context).textMuted,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppPalette.of(context).textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppPalette.of(context).surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shipping['recipient_name'] as String? ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  shipping['phone'] as String? ?? '',
                  style: TextStyle(
                    color: AppPalette.of(context).textMuted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                        shipping['line1'],
                        shipping['line2'],
                        shipping['city'],
                        shipping['postal_code'],
                      ]
                      .where((e) => e != null && (e as String).isNotEmpty)
                      .join(', '),
                  style: const TextStyle(fontSize: 13.5, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (order.customerRemarks?.trim().isNotEmpty ?? false) ...[
          Text(
            'CUSTOMER REQUESTS / REMARKS',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.8,
              color: AppPalette.of(context).textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppPalette.of(context).surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: AppShadows.card,
            ),
            child: SelectableText(
              order.customerRemarks!,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppPalette.of(context).text,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Text(
          'ITEMS',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.8,
            color: AppPalette.of(context).textMuted,
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
          child: Column(
            children: [
              for (final item in order.items)
                _OrderItemTile(
                  item: item,
                  // Gated on the *order's own owner*, not just "delivered"
                  // — this same screen is also how an admin opens a
                  // customer's order from admin_orders_screen.dart, and
                  // without this check they'd see (and could tap) a
                  // "Write a review" prompt on somebody else's purchase,
                  // which is confusing and not what it's for. A review
                  // still only ever posts as whoever is logged in
                  // (upsertMyReview / RLS both key off auth.uid()), but
                  // the prompt itself shouldn't even appear unless this
                  // is genuinely the viewer's own order.
                  canReview:
                      order.status == OrderStatus.delivered &&
                      order.userId != null &&
                      order.userId ==
                          ref.watch(currentAppUserProvider).valueOrNull?.id,
                ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              if (order.discountAmount != null && order.discountAmount! > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        order.promoCode != null
                            ? 'Promo discount (${order.promoCode})'
                            : 'Promo discount',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppPalette.of(context).textMuted,
                        ),
                      ),
                      Text(
                        '-${formatPrice(order.discountAmount!)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppPalette.of(context).accent,
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppPalette.of(context).textMuted,
                      ),
                    ),
                    Text(
                      formatPrice(order.total),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppPalette.of(context).text,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Cancel/Reorder are shopper actions on their own order — an admin
        // viewing any customer's order manages its lifecycle from the
        // Orders status dropdown instead, not from these buttons.
        Builder(
          builder: (context) {
            final isAdmin =
                ref.watch(currentAppUserProvider).valueOrNull?.role.isAdmin ??
                false;
            if (isAdmin) return const SizedBox.shrink();
            if (justPlaced) return const _ContinueShoppingButton();
            return Column(
              children: [
                if (order.status == OrderStatus.pending ||
                    order.status == OrderStatus.paid) ...[
                  _CancelOrderButton(order: order),
                  const SizedBox(height: AppSpacing.lg),
                ],
                _ReorderButton(order: order),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One order line — bigger thumbnail and clearer name/option/qty layout
/// than the previous compact row, plus (only once [canReview] — i.e. the
/// order is `delivered`) a "Write a review"/"Edit your review" affordance
/// so a customer doesn't have to navigate back to the product page to
/// leave one. Reviews are per product+user (not per order — see
/// review_repository.dart), so this reads the same
/// `myReviewForProductProvider` the product page uses.
class _OrderItemTile extends ConsumerWidget {
  final OrderItem item;
  final bool canReview;
  const _OrderItemTile({required this.item, required this.canReview});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: item.imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: item.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            color: AppPalette.of(context).background,
                          ),
                          errorWidget: (_, _, _) => ColoredBox(
                            color: AppPalette.of(context).background,
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              size: 20,
                              color: AppPalette.of(context).textMuted,
                            ),
                          ),
                        )
                      : ColoredBox(
                          color: AppPalette.of(context).background,
                          child: Icon(
                            Icons.inventory_2_outlined,
                            size: 20,
                            color: AppPalette.of(context).textMuted,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    if (item.optionLabel != null) ...[
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.of(context).background,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          item.optionLabel!,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppPalette.of(context).textMuted,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Qty ${item.quantity} × ${formatPrice(item.unitPrice)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppPalette.of(context).textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                formatPrice(item.subtotal),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (canReview) ...[
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(left: 72),
              child: _ReviewAffordance(productId: item.productId),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewAffordance extends ConsumerWidget {
  final String productId;
  const _ReviewAffordance({required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myReviewAsync = ref.watch(myReviewForProductProvider(productId));
    return myReviewAsync.when(
      data: (myReview) {
        if (myReview == null) {
          return OutlinedButton.icon(
            onPressed: () => openReviewForm(context, ref, productId),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            icon: const Icon(Icons.star_border, size: 15),
            label: const Text(
              'Write a review',
              style: TextStyle(fontSize: 12.5),
            ),
          );
        }
        return InkWell(
          onTap: () =>
              openReviewForm(context, ref, productId, existing: myReview),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 1; i <= 5; i++)
                Icon(
                  i <= myReview.rating ? Icons.star : Icons.star_border,
                  size: 14,
                  color: AppPalette.of(context).warning,
                ),
              const SizedBox(width: 6),
              Text(
                'Edit your review',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppPalette.of(context).textMuted,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
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
      if (product.isLiveFish &&
          !product.hasVariants &&
          (product.isSold || product.stockQuantity <= 0)) {
        // This exact fish is gone — can't reorder a unique animal. A batch
        // listing with fish options falls through to the per-variant stock
        // check below instead (the base stock field doesn't apply to it).
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
      final variant = matchingVariants.isNotEmpty
          ? matchingVariants.first
          : null;
      final size =
          item.sizeLabel != null &&
              product.hasSizeOptions &&
              product.sizeOptions.contains(item.sizeLabel)
          ? item.sizeLabel
          : null;
      // Size-required products can't reorder without a valid size pick.
      if (product.hasSizeOptions && size == null) {
        skipped++;
        continue;
      }
      final result = cart.add(
        product,
        quantity: product.isLiveFish ? 1 : item.quantity,
        variant: variant,
        size: size,
      );
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    if (added > 0) context.push('/cart');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : _reorder,
        icon: _loading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppPalette.of(context).text,
                ),
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
          'This cannot be undone. Refunds (if already paid) are handled by the shop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Order'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Cancel Order',
              style: TextStyle(color: AppPalette.of(context).error),
            ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'The order was not cancelled. Refresh its status and try again, or contact the shop.',
            ),
          ),
        );
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
          foregroundColor: AppPalette.of(context).error,
          side: BorderSide(color: AppPalette.of(context).error, width: 1.2),
        ),
        icon: _loading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppPalette.of(context).error,
                ),
              )
            : const Icon(Icons.cancel_outlined, size: 18),
        label: const Text('Cancel Order'),
      ),
    );
  }
}

/// AppBar action(s) for the order detail screen: an admin looking at a
/// customer's order (not their own) gets a "view customer" button instead
/// of the share-receipt one — sharing a receipt is a customer action, and
/// swapping it out keeps the AppBar to one icon rather than crowding it.
/// Everyone else (the customer on their own order, or an admin viewing
/// their own order) keeps the share button as before.
class _OrderAppBarActions extends ConsumerWidget {
  final Order order;
  const _OrderAppBarActions({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentAppUserProvider).valueOrNull;
    final isAdmin = currentUser?.role.isAdmin ?? false;
    final isOwnOrder = order.userId == currentUser?.id;
    if (isAdmin && !isOwnOrder && order.userId != null) {
      return IconButton(
        tooltip: 'View Customer',
        icon: const Icon(Icons.person_outline),
        onPressed: () => context.push('/admin/customers/${order.userId}'),
      );
    }
    return _ShareReceiptButton(order: order);
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
          await shareReceipt(ref, order);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Could not share your receipt. Please try again.',
                ),
              ),
            );
          }
        }
      },
    );
  }
}

/// Live carrier status — 17TRACK (via `track-register`/`track-webhook`/
/// `track-status`) for manually-entered tracking numbers, or EasyParcel
/// (via `easyparcel-book-shipment`/`easyparcel-webhook`/
/// `easyparcel-refresh-status`) when `order.trackingProvider == 'easyparcel'`
/// — the refresh button below routes to whichever one actually owns this
/// shipment instead of always asking 17TRACK, which doesn't know about
/// EasyParcel's tracking numbers at all.
class _TrackingStatusCard extends ConsumerStatefulWidget {
  final Order order;
  const _TrackingStatusCard({required this.order});

  @override
  ConsumerState<_TrackingStatusCard> createState() =>
      _TrackingStatusCardState();
}

class _TrackingStatusCardState extends ConsumerState<_TrackingStatusCard> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      if (widget.order.trackingProvider == 'easyparcel') {
        await EasyParcelRepository().refreshStatus(widget.order.id);
      } else {
        await DeliveryRepository().refreshTrackingStatus(widget.order.id);
      }
      ref.invalidate(orderByIdProvider(widget.order.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not refresh the order. Check your connection and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// Maps EasyParcel's numeric shipment status code (migration 0043) to an
  /// icon + color so the card visually distinguishes "booked, courier
  /// hasn't collected it yet" from "actually moving" instead of showing the
  /// same truck-ish icon throughout. Null (17TRACK orders, or before the
  /// first refresh) keeps the original generic icon.
  (IconData, Color) _iconForStatusCode(int? code) {
    switch (code) {
      case 2: // To Be Collected
      case 7: // Schedule In Arrangement
      case 8: // On Hold
        return (Icons.schedule, AppPalette.of(context).warning);
      case 3: // Collected — courier has picked it up from the shop
        return (Icons.inventory_2_outlined, AppPalette.of(context).accent);
      case 11: // Drop Off — shop dropped it at a courier point itself
        return (Icons.storefront_outlined, AppPalette.of(context).accent);
      case 4: // Delivery In Transit
        return (Icons.local_shipping_outlined, AppPalette.of(context).accent);
      case 5: // Delivered
        return (Icons.check_circle_outline, AppPalette.of(context).success);
      case 0: // Cancel
      case 6: // Returned
        return (Icons.assignment_return_outlined, AppPalette.of(context).error);
      default:
        return (Icons.track_changes, AppPalette.of(context).accent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final hasStatus =
        order.trackingStatus != null && order.trackingStatus!.isNotEmpty;
    final (statusIcon, statusColor) = _iconForStatusCode(
      order.trackingStatusCode,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppPalette.of(context).surface,
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
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(statusIcon, size: 18, color: statusColor),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasStatus ? order.trackingStatus! : 'Awaiting carrier update',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                if (order.trackingStatusDetail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    order.trackingStatusDetail!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppPalette.of(context).textMuted,
                    ),
                  ),
                ],
                if (order.trackingUpdatedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Updated ${DateFormat.yMMMd().add_jm().format(order.trackingUpdatedAt!)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppPalette.of(context).textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh tracking',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppPalette.of(context).accent,
                    ),
                  )
                : Icon(
                    Icons.refresh,
                    size: 20,
                    color: AppPalette.of(context).textMuted,
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final OrderStatus status;
  const _StatusBadge({required this.status});

  Color _color(BuildContext context) {
    switch (status) {
      case OrderStatus.delivered:
        return AppPalette.of(context).success;
      case OrderStatus.cancelled:
      case OrderStatus.refunded:
        return AppPalette.of(context).error;
      case OrderStatus.pending:
        return AppPalette.of(context).warning;
      default:
        return AppPalette.of(context).accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        orderStatusLabel(status),
        style: TextStyle(
          color: _color(context),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
