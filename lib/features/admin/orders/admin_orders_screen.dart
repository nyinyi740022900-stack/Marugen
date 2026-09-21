import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';
import '../../../shared/utils/contact_launcher.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/providers/paged_notifier.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../orders/presentation/orders_providers.dart';
import '../../orders/utils/invoice_pdf.dart';
import '../delivery/admin_delivery_screen.dart';
import '../payments/admin_payments_screen.dart';

/// Orders hub: status list + fulfillment (ex-Delivery) + payments ledger.
class AdminOrdersScreen extends StatelessWidget {
  const AdminOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Orders'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'All'),
              Tab(text: 'Fulfillment'),
              Tab(text: 'Payments'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _OrdersListPane(),
            AdminDeliveryPane(),
            AdminPaymentsPane(),
          ],
        ),
      ),
    );
  }
}

/// Free-text query for the admin Orders search bar — matches order number,
/// buyer name/phone, or an item's product name.
final adminOrderSearchQueryProvider = StateProvider<String>((ref) => '');

class _OrdersListPane extends ConsumerStatefulWidget {
  const _OrdersListPane();

  @override
  ConsumerState<_OrdersListPane> createState() => _OrdersListPaneState();
}

class _OrdersListPaneState extends ConsumerState<_OrdersListPane> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.attachPagination(
      () => ref.read(adminOrdersPagedProvider.notifier).loadNextPage(),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(adminOrderStatusFilterProvider);
    final query = ref.watch(adminOrderSearchQueryProvider).trim().toLowerCase();
    // Pagination only applies to the default (no search) view — a search
    // query needs the full unbounded list so it can find a match on any
    // page, not just whatever's been scrolled into view so far.
    final searching = query.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
          child: _AdminOrderSearchField(),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: filter == null,
                  onSelected: (_) =>
                      ref.read(adminOrderStatusFilterProvider.notifier).state = null,
                ),
              ),
              for (final s in OrderStatus.values)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    label: Text(orderStatusLabel(s)),
                    selected: filter == s,
                    onSelected: (_) =>
                        ref.read(adminOrderStatusFilterProvider.notifier).state = s,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: searching
              ? ref.watch(adminOrdersProvider).when(
                    data: (orders) {
                      final filtered = orders.where((o) {
                        if (o.displayNumber.toLowerCase().contains(query)) return true;
                        final name = o.shippingAddress?['recipient_name'] as String?;
                        if (name != null && name.toLowerCase().contains(query)) return true;
                        final phone = o.shippingAddress?['phone'] as String?;
                        if (phone != null && phone.contains(query)) return true;
                        return o.items
                            .any((item) => item.productName.toLowerCase().contains(query));
                      }).toList();

                      if (filtered.isEmpty) {
                        return const Center(
                          child: Text('No matches.', style: TextStyle(color: AppColors.grey)),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                        itemBuilder: (context, i) => _AdminOrderCard(order: filtered[i]),
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator(color: AppColors.red)),
                    error: (e, _) => ErrorState(onRetry: () => ref.invalidate(adminOrdersProvider)),
                  )
              : ref.watch(adminOrdersPagedProvider).when(
                    data: (paged) {
                      if (paged.items.isEmpty) {
                        return const Center(
                          child: Text('No orders.', style: TextStyle(color: AppColors.grey)),
                        );
                      }
                      return ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                        itemCount: paged.items.length + (paged.hasMore ? 1 : 0),
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                        itemBuilder: (context, i) {
                          if (i >= paged.items.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                              child: Center(
                                child: CircularProgressIndicator(color: AppColors.red, strokeWidth: 2),
                              ),
                            );
                          }
                          return _AdminOrderCard(order: paged.items[i]);
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator(color: AppColors.red)),
                    error: (e, _) => ErrorState(
                      onRetry: () => ref.read(adminOrdersPagedProvider.notifier).refresh(),
                    ),
                  ),
        ),
      ],
    );
  }
}

/// Search field with its own stable [TextEditingController] so the cursor
/// and focus survive provider-driven rebuilds — same pattern as the admin
/// Products search bar.
class _AdminOrderSearchField extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AdminOrderSearchField> createState() => _AdminOrderSearchFieldState();
}

class _AdminOrderSearchFieldState extends ConsumerState<_AdminOrderSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(adminOrderSearchQueryProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(adminOrderSearchQueryProvider);
    if (query != _controller.text) {
      _controller.value = _controller.value.copyWith(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
    return TextField(
      controller: _controller,
      onChanged: (v) => ref.read(adminOrderSearchQueryProvider.notifier).state = v,
      decoration: InputDecoration(
        hintText: 'Search order #, buyer, or item…',
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () =>
                    ref.read(adminOrderSearchQueryProvider.notifier).state = '',
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

/// Lazada-style order card: order number + copy, a preview of the first
/// item, the order total, a status control, and quick actions to contact
/// the buyer or share the invoice. The whole card pushes into the full
/// order detail on tap; the controls below stop that tap from firing so
/// they act independently.
class _AdminOrderCard extends ConsumerStatefulWidget {
  final Order order;
  const _AdminOrderCard({required this.order});

  @override
  ConsumerState<_AdminOrderCard> createState() => _AdminOrderCardState();
}

class _AdminOrderCardState extends ConsumerState<_AdminOrderCard> {
  bool _sharing = false;

  Future<void> _copyOrderId(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.order.displayNumber));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Order number copied')));
  }

  Future<void> _printInvoice(BuildContext context) async {
    setState(() => _sharing = true);
    try {
      await shareReceipt(ref, widget.order);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not share invoice: $e')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final phone = order.shippingAddress?['phone'] as String?;
    final hasPhone = phone != null && phone.trim().isNotEmpty;
    final firstItem = order.items.isNotEmpty ? order.items.first : null;
    final extraCount = order.items.length - 1;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/orders/${order.id}', extra: order),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text('Order #${order.displayNumber}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            onTap: () => _copyOrderId(context),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.copy_rounded, size: 15, color: AppColors.greySoft),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Text(DateFormat.yMMMd().add_jm().format(order.createdAt),
                    style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                const SizedBox(height: AppSpacing.md),
                if (firstItem != null)
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: AppColors.offWhite,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: firstItem.imageUrl != null && firstItem.imageUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: firstItem.imageUrl!,
                                fit: BoxFit.cover,
                                placeholder: (_, _) => const SizedBox.shrink(),
                                errorWidget: (_, _, _) => const Icon(Icons.inventory_2_outlined,
                                    size: 18, color: AppColors.greySoft),
                              )
                            : const Icon(Icons.inventory_2_outlined,
                                size: 18, color: AppColors.greySoft),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(firstItem.productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                            const SizedBox(height: 2),
                            Text(
                              extraCount > 0
                                  ? 'Qty ${firstItem.quantity} · +$extraCount more'
                                  : 'Qty ${firstItem.quantity}',
                              style: const TextStyle(fontSize: 12, color: AppColors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.md),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Purchase',
                        style: TextStyle(fontSize: 12.5, color: AppColors.grey)),
                    Text('S\$${order.total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.red)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _StatusSelector(order: order),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _PillButton(
                        icon: Icons.chat_bubble_outline,
                        label: 'Contact Buyer',
                        onTap: hasPhone
                            ? () => launchShopContact(phone,
                                message:
                                    "Hi, this is Marugen Koi Farm regarding your order #${order.displayNumber}")
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _PillButton(
                        icon: Icons.receipt_long_outlined,
                        label: 'Print Invoice',
                        filled: true,
                        loading: _sharing,
                        onTap: _sharing ? null : () => _printInvoice(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Current-status pill + a row of buttons for only the statuses that are
/// actually valid next steps from here (see `validNextStatuses` in
/// order.dart) — replaces a freeform "any of 7 statuses" dropdown that let
/// an admin accidentally move a `delivered` order back to `shipped`/
/// `packing` (confusing for the customer, who already saw the order
/// marked delivered) or otherwise jump the pipeline out of order. A
/// terminal order (cancelled/refunded) shows the pill with no buttons at
/// all, since 0030_order_status_forward_only.sql blocks any further
/// change server-side anyway. Picking `cancelled`/`refunded` still asks
/// for confirmation first, since both are final and release stock/trigger
/// refund side effects.
class _StatusSelector extends ConsumerStatefulWidget {
  final Order order;
  const _StatusSelector({required this.order});

  @override
  ConsumerState<_StatusSelector> createState() => _StatusSelectorState();
}

class _StatusSelectorState extends ConsumerState<_StatusSelector> {
  bool _updating = false;

  Color _colorFor(OrderStatus s) {
    switch (s) {
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

  Future<void> _moveTo(OrderStatus s) async {
    if (s == OrderStatus.cancelled || s == OrderStatus.refunded) {
      final confirmed = await confirmDestructiveAction(
        context,
        title: s == OrderStatus.cancelled ? 'Cancel this order?' : 'Mark as refunded?',
        message:
            'Order #${widget.order.displayNumber} will move to "${orderStatusLabel(s)}". '
            'This is final — the status can never be changed again after this.',
        confirmLabel: orderStatusLabel(s),
      );
      if (!confirmed) return;
    }

    setState(() => _updating = true);
    try {
      await ref.read(orderRepositoryProvider).updateOrderStatus(widget.order.id, s);
      refreshAdminOrders(ref);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update status: $e')),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.order.status;
    final color = _colorFor(status);
    final nextStatuses = validNextStatuses(status);
    // Cancel/refund are final and consequence-heavy (release stock, trigger
    // a refund) — kept visually separate and muted from the ordinary
    // forward-progress actions so they read as deliberate, not just
    // another button in the same row an admin might tap by reflex.
    final progressStatuses =
        nextStatuses.where((s) => s != OrderStatus.cancelled && s != OrderStatus.refunded);
    final riskyStatuses =
        nextStatuses.where((s) => s == OrderStatus.cancelled || s == OrderStatus.refunded);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Text(
                orderStatusLabel(status),
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            if (_updating) ...[
              const SizedBox(width: AppSpacing.sm),
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        if (!_updating && progressStatuses.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in progressStatuses)
                OutlinedButton(
                  onPressed: () => _moveTo(s),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    side: BorderSide(color: _colorFor(s).withValues(alpha: 0.4)),
                    foregroundColor: _colorFor(s),
                  ),
                  child: Text(orderStatusLabel(s), style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
        if (!_updating && riskyStatuses.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: 4,
            children: [
              for (final s in riskyStatuses)
                TextButton(
                  onPressed: () => _moveTo(s),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    foregroundColor: AppColors.greySoft,
                  ),
                  child: Text(orderStatusLabel(s),
                      style: const TextStyle(fontSize: 11.5, decoration: TextDecoration.underline)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Shared pill-shaped action button used across the admin order card —
/// `filled: true` reads as the primary action, otherwise it's an outline.
/// Disabled (null `onTap`) reads as greyed-out rather than just inert.
class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool loading;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = filled
        ? AppColors.white
        : enabled
            ? AppColors.black
            : AppColors.greySoft;
    final bg = filled ? (enabled ? AppColors.black : AppColors.lightGrey) : Colors.transparent;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: filled ? null : Border.all(color: enabled ? AppColors.lightGrey : AppColors.lightGrey),
          ),
          alignment: Alignment.center,
          child: loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 15, color: fg),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
