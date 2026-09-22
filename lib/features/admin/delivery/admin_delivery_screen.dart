import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../orders/presentation/orders_providers.dart';
import 'delivery_repository.dart';
import 'easyparcel_providers.dart';
import 'easyparcel_repository.dart';

/// 17TRACK carrier codes for couriers this shop actually uses — passed as
/// `carrier_code` so 17TRACK doesn't have to guess from the tracking
/// number's format (which fails for newer/less common numbering schemes,
/// e.g. TracX Logis's). See https://www.17track.net/en/carriers for the
/// full list if another courier is needed.
const _carrierOptions = <int?, String>{
  null: 'Auto-detect',
  100190: 'TracX Logis (Qxpress)',
  100124: 'Ninja Van',
  100229: 'J&T Express',
  101004: 'SingPost / Speedpost',
  100001: 'DHL Express',
};

/// Delivery pane embedded in the Orders hub (no Scaffold). Every order is
/// delivered — there is no self-collection/pickup option. Courier tracking
/// (17TRACK) is optional: live fish and any other order the shop
/// hand-delivers itself can be marked delivered without a courier or
/// tracking number.
class AdminDeliveryPane extends ConsumerWidget {
  const AdminDeliveryPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(adminOrdersProvider);
    // Defaults to false (manual-entry-only) while unknown/loading/errored —
    // EasyParcel is meant to be a convenience on top of the always-working
    // manual path, never a blocker if the status check itself fails.
    final easyParcelConnected =
        ref.watch(easyParcelConnectedProvider).valueOrNull ?? false;

    return ordersAsync.when(
      data: (orders) {
        final readyToShip = orders
            .where(
              (o) =>
                  o.status == OrderStatus.paid ||
                  o.status == OrderStatus.packing,
            )
            .toList();
        if (readyToShip.isEmpty) {
          return const EmptyState(
            icon: Icons.local_shipping_outlined,
            title: 'Nothing to fulfil',
            subtitle: 'No orders are ready for delivery right now.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: readyToShip.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, i) => _FulfillmentCard(
            order: readyToShip[i],
            easyParcelConnected: easyParcelConnected,
          ),
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.red),
      ),
      error: (e, _) => ErrorState(onRetry: () => ref.invalidate(adminOrdersProvider)),
    );
  }
}

class _FulfillmentCard extends ConsumerStatefulWidget {
  final Order order;
  final bool easyParcelConnected;
  const _FulfillmentCard({required this.order, required this.easyParcelConnected});

  @override
  ConsumerState<_FulfillmentCard> createState() => _FulfillmentCardState();
}

class _FulfillmentCardState extends ConsumerState<_FulfillmentCard> {
  bool _markingDelivered = false;

  /// Bottom sheet: fetch live rates, let the admin pick a courier, then
  /// book — mirrors _enterTracking's dialog-then-register shape, but as a
  /// sheet since the rate list is a longer, scrollable choice.
  Future<void> _shipWithEasyParcel() async {
    final selected = await showModalBottomSheet<EasyParcelRate>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _EasyParcelRateSheet(orderId: widget.order.id),
    );
    if (selected == null || !mounted) return;

    try {
      await EasyParcelRepository().bookShipment(
        orderId: widget.order.id,
        serviceId: selected.serviceId,
        courierId: selected.courierId,
      );
      refreshAdminOrders(ref);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text('Booked with ${selected.courierName} — tracking is automatic')),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('EasyParcel error: $e')));
      }
    }
  }

  Future<void> _markDeliveredByShop() async {
    final order = widget.order;
    // Every major platform (Shopify's "Fulfill order", Amazon Seller
    // Central's "Confirm shipment", Shopee/Lazada) confirms before a
    // shipment/delivery action — it immediately notifies the customer and
    // (0030_order_status_forward_only.sql) can never be reverted to
    // shipped/packing afterwards, so a stray tap has real consequences.
    final confirmed = await confirmAction(
      context,
      title: 'Mark as delivered?',
      message:
          'Order #${order.displayNumber} will be marked "Delivered" and the customer notified. '
          'Use this only once it has actually been handed to them — this cannot be undone.',
      confirmLabel: 'Mark Delivered',
    );
    if (!confirmed) return;

    setState(() => _markingDelivered = true);
    try {
      await ref
          .read(orderRepositoryProvider)
          .updateOrderStatus(order.id, OrderStatus.delivered);
      refreshAdminOrders(ref);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update status: $e')),
      );
    } finally {
      if (mounted) setState(() => _markingDelivered = false);
    }
  }

  Future<void> _registerTracking(
    String trackingNumber,
    int? carrierCode,
  ) async {
    try {
      await DeliveryRepository().registerTracking(
        orderId: widget.order.id,
        trackingNumber: trackingNumber,
        carrierCode: carrierCode,
      );
      refreshAdminOrders(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registered with 17TRACK — tracking is now automatic')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('17TRACK error: $e')));
      }
    }
  }

  /// Tracking number + courier picker. Passing the courier explicitly
  /// avoids 17TRACK's "carrier cannot be detected" failure for numbering
  /// schemes it doesn't recognise yet (seen with TracX Logis/Qxpress).
  Future<void> _enterTracking({String? initialNumber}) async {
    final controller = TextEditingController(text: initialNumber);
    int? carrierCode;
    final result = await showDialog<(String, int?)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Enter tracking number'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int?>(
                initialValue: carrierCode,
                decoration: const InputDecoration(labelText: 'Courier'),
                items: [
                  for (final entry in _carrierOptions.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                ],
                onChanged: (v) => setState(() => carrierCode = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'e.g. SG1234567890'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, (controller.text.trim(), carrierCode)),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || result.$1.isEmpty) return;
    if (!mounted) return;
    await _registerTracking(result.$1, result.$2);
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order #${order.displayNumber}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 2),
          Text(
            DateFormat.yMMMd().format(order.createdAt),
            style: const TextStyle(color: AppColors.grey, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.md),
          if (order.qxpressTrackingNo != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.local_shipping_outlined,
                        size: 15,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Tracking: ${order.qxpressTrackingNo}',
                          style: const TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (order.trackingProvider == 'easyparcel')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: const Text(
                            'via EasyParcel',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (order.trackingStatus != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      order.trackingStatusDetail ?? order.trackingStatus!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.grey,
                      ),
                    ),
                  ] else if (order.trackingRegistered) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Waiting for first carrier update…',
                      style: TextStyle(
                        fontSize: 12,
                        // Was greySoft (#9A9490, ~2.7:1 on white — fails
                        // WCAG AA) — this is a status an admin needs to
                        // actually read, not decorative fine print.
                        color: AppColors.grey,
                      ),
                    ),
                  ] else if (order.trackingProvider != 'easyparcel') ...[
                    // Manual/17TRACK path only — an EasyParcel-booked
                    // shipment with no status yet just hasn't had its
                    // first webhook update land; there's no "retry" action
                    // for it (re-typing a tracking number would overwrite
                    // a real EasyParcel booking with a manual one).
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _enterTracking(initialNumber: order.qxpressTrackingNo!),
                        icon: const Icon(Icons.track_changes, size: 16),
                        label: const Text('Retry / pick a courier'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else
            // Stacked full-width, not side-by-side: buttons wrap to 2
            // lines at this card's width while a Row split them into
            // visibly mismatched heights. Stacking also reads as intended:
            // when EasyParcel is connected it's the primary/default path
            // (ElevatedButton, themed red — the app's actual
            // primary-button style), manual entry demotes to secondary
            // (OutlinedButton, matching everything below it), and
            // hand-delivery stays the last/fallback path underneath.
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.easyParcelConnected) ...[
                  ElevatedButton.icon(
                    onPressed: _shipWithEasyParcel,
                    icon: const Icon(Icons.local_shipping_outlined, size: 17),
                    label: const Text('Ship with EasyParcel'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => _enterTracking(),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Enter Tracking Number Manually'),
                  ),
                ] else
                  ElevatedButton.icon(
                    onPressed: () => _enterTracking(),
                    icon: const Icon(Icons.local_shipping_outlined, size: 17),
                    label: const Text('Enter Tracking Number'),
                  ),
                const SizedBox(height: AppSpacing.sm),
                // For orders the shop hand-delivers itself — live fish
                // especially, which never go through a courier/tracking
                // API — this closes the order out as delivered directly,
                // with no tracking number.
                OutlinedButton(
                  onPressed: _markingDelivered ? null : _markDeliveredByShop,
                  child: _markingDelivered
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Delivered by shop'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet content for _shipWithEasyParcel — fetches rates on open,
/// lets the admin pick one (price shown so it's an informed choice, not a
/// black box), and pops the selection back for the caller to book.
class _EasyParcelRateSheet extends StatefulWidget {
  final String orderId;
  const _EasyParcelRateSheet({required this.orderId});

  @override
  State<_EasyParcelRateSheet> createState() => _EasyParcelRateSheetState();
}

class _EasyParcelRateSheetState extends State<_EasyParcelRateSheet> {
  late Future<List<EasyParcelRate>> _ratesFuture = _fetchRates();
  EasyParcelRate? _selected;

  Future<List<EasyParcelRate>> _fetchRates() {
    // Cheapest first (EasyParcel's own docs recommend this default sort) —
    // lets the admin book the cheapest option with one tap most of the time.
    return EasyParcelRepository()
        .getRates(widget.orderId)
        .then((rates) => rates..sort((a, b) => a.price.compareTo(b.price)));
  }

  void _retry() => setState(() {
        _selected = null;
        _ratesFuture = _fetchRates();
      });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose a courier',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.md),
            FutureBuilder<List<EasyParcelRate>>(
              future: _ratesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator(color: AppColors.red)),
                  );
                }
                if (snapshot.hasError) {
                  return _RateSheetMessage(
                    icon: Icons.error_outline,
                    message: 'Could not fetch rates: ${snapshot.error}',
                    color: AppColors.error,
                    onRetry: _retry,
                  );
                }
                final rates = snapshot.data ?? [];
                if (rates.isEmpty) {
                  return _RateSheetMessage(
                    icon: Icons.local_shipping_outlined,
                    message: 'No courier rates available for this address.',
                    color: AppColors.grey,
                    onRetry: _retry,
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final rate in rates)
                      RadioListTile<EasyParcelRate>(
                        contentPadding: EdgeInsets.zero,
                        value: rate,
                        groupValue: _selected,
                        onChanged: (v) => setState(() => _selected = v),
                        title: Text(rate.courierName),
                        secondary: Text(
                          '${rate.currency ?? 'S\$'} ${rate.price.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: _selected == null
                  ? null
                  : () => Navigator.of(context).pop(_selected),
              child: const Text('Book Shipment'),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared empty/error state for the rate sheet — always offers a Retry so a
/// transient failure (or fixing Settings in another tab) doesn't force the
/// admin to close and reopen the whole sheet.
class _RateSheetMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final VoidCallback onRetry;

  const _RateSheetMessage({
    required this.icon,
    required this.message,
    required this.color,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
