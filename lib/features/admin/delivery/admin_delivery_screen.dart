import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../../shared/utils/error_message.dart';
import '../../../shared/utils/price_format.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/content_width.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shipping_cost_summary.dart';
import '../../orders/presentation/orders_providers.dart';
import '../../orders/presentation/order_pull_to_refresh.dart';
import '../../orders/utils/print_document.dart';
import '../../orders/utils/packing_slip_pdf.dart';
import 'delivery_repository.dart';
import 'easyparcel_providers.dart';
import 'easyparcel_repository.dart';
import 'pickup_diagnostics_panel.dart';
import 'parcel_fulfillment_panel.dart';

/// Every outstanding shipment remains here until delivered, regardless of the
/// All-tab filter or courier provider.
class AdminDeliveryPane extends ConsumerWidget {
  const AdminDeliveryPane({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(fulfillmentOrdersProvider);
    final connected =
        ref.watch(easyParcelConnectedProvider).valueOrNull ?? false;
    return ContentWidth(
      maxWidth: 800,
      child: ordersAsync.when(
        data: (orders) {
          final outstanding = orders
              .where(
                (o) => const {
                  OrderStatus.paid,
                  OrderStatus.packing,
                  OrderStatus.shipped,
                }.contains(o.status),
              )
              .toList();
          outstanding.sort((a, b) {
            final attention =
                (b.needsBookingAttention || b.needsDeliveryReview ? 1 : 0)
                    .compareTo(
                      a.needsBookingAttention || a.needsDeliveryReview ? 1 : 0,
                    );
            return attention != 0
                ? attention
                : a.createdAt.compareTo(b.createdAt);
          });
          return OrderPullToRefresh(
            onRefresh: () async {
              final container = ProviderScope.containerOf(
                context,
                listen: false,
              );
              container.invalidate(easyParcelConnectedProvider);
              await refreshAdminOrdersFromCarrier(container);
            },
            child: outstanding.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 80),
                      EmptyState(
                        icon: Icons.local_shipping_outlined,
                        title: 'Nothing to fulfil',
                        subtitle: 'No outstanding deliveries right now.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: outstanding.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (_, i) => _FulfillmentCard(
                      key: ValueKey(outstanding[i].id),
                      order: outstanding[i],
                      easyParcelConnected: connected,
                    ),
                  ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorState(
          onRetry: () => ref.invalidate(fulfillmentOrdersProvider),
        ),
      ),
    );
  }
}

class _FulfillmentCard extends ConsumerStatefulWidget {
  final Order order;
  final bool easyParcelConnected;
  const _FulfillmentCard({
    super.key,
    required this.order,
    required this.easyParcelConnected,
  });
  @override
  ConsumerState<_FulfillmentCard> createState() => _FulfillmentCardState();
}

class _FulfillmentCardState extends ConsumerState<_FulfillmentCard> {
  bool _working = false;
  bool _sheetOpen = false;
  bool get _busy => _working || _sheetOpen;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _working = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorMessage(
                error,
                fallback: 'Could not complete this action. Refresh the order and try again.',
                context: 'admin.delivery',
              ),
            ),
          ),
        );
      }
    } finally {
      // Failed requests can still have booked a real shipment. Always fetch truth
      // again rather than leaving a stale, enabled booking button on screen.
      if (mounted) {
        ref.invalidate(fulfillmentOrdersProvider);
        ref.invalidate(adminOrdersProvider);
        ref.invalidate(adminOrdersPagedProvider);
        ref.invalidate(orderByIdProvider(widget.order.id));
        ref.invalidate(myOrdersProvider);
        setState(() => _working = false);
      }
    }
  }

  Future<void> _shipWithEasyParcel() async {
    if (_busy) return;
    // Lock before opening the sheet so other fulfillment actions cannot race it.
    setState(() => _sheetOpen = true);
    final selection = await showModalBottomSheet<_ShipmentSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EasyParcelRateSheet(
        orderId: widget.order.id,
        acceptedParcel: widget.order.shippingParcel,
      ),
    );
    if (!mounted) return;
    setState(() => _sheetOpen = false);
    if (selection == null) return;
    await _run(
      () => ref
          .read(easyParcelRepositoryProvider)
          .bookShipment(
            orderId: widget.order.id,
            serviceId: selection.rate.serviceId,
            courierId: selection.rate.courierId,
            parcel: selection.parcel,
          ),
    );
  }

  Future<void> _moveTo(OrderStatus status) async {
    if (_busy) return;
    if (status == OrderStatus.delivered) {
      final confirmed = await confirmAction(
        context,
        title: 'Mark as delivered?',
        message:
            'Confirm that order #${widget.order.displayNumber} has actually been handed to the recipient. '
            'The customer will be notified. This cannot be undone.',
        confirmLabel: 'Mark Delivered',
      );
      if (!confirmed || !mounted) return;
    } else if (status == OrderStatus.shipped) {
      final confirmed = await confirmAction(
        context,
        title: 'Start shop delivery?',
        message:
            'Confirm order #${widget.order.displayNumber} has left the shop for delivery. '
            'The customer will be notified.',
        confirmLabel: 'Start delivery',
      );
      if (!confirmed || !mounted) return;
    }
    await _run(
      () => ref
          .read(orderRepositoryProvider)
          .updateOrderStatus(widget.order.id, status),
    );
  }

  Future<void> _enterTracking({bool recovery = false}) async {
    if (_busy) return;
    final controller = TextEditingController();
    const int? carrier = null;
    bool confirmed = false;
    final form = GlobalKey<FormState>();
    final tracking = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          scrollable: true,
          title: Text(
            recovery ? 'Recover existing shipment' : 'Add tracking number',
          ),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  recovery
                      ? 'Find this order’s existing booking in EasyParcel and copy its tracking number. Do not create another booking.'
                      : 'Only save tracking after the parcel has been handed to the courier. This marks the order as shipped.',
                ),
                const SizedBox(height: 12),
                if (!recovery)
                  const Text('Carrier detected from the tracking number.'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: controller,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Tracking number',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter the tracking number.'
                      : null,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: confirmed,
                  title: Text(
                    recovery
                        ? 'I checked this is the existing booking for this order.'
                        : 'The parcel has been handed to the courier.',
                  ),
                  onChanged: (value) =>
                      update(() => confirmed = value ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: !confirmed
                  ? null
                  : () {
                      if (form.currentState!.validate()) {
                        Navigator.pop(ctx, controller.text.trim());
                      }
                    },
              child: Text(recovery ? 'Recover shipment' : 'Confirm handover'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (tracking == null || !mounted) return;
    await _run(
      () => recovery
          ? ref
                .read(easyParcelRepositoryProvider)
                .reconcileShipment(widget.order.id, tracking)
          : DeliveryRepository().registerTracking(
              orderId: widget.order.id,
              trackingNumber: tracking,
              carrierCode: carrier,
            ),
    );
  }

  Future<void> _openLabel() => _run(
    () => previewShippingLabel(
      context,
      url: widget.order.easyparcelAwbUrl ?? '',
      orderNumber: widget.order.displayNumber,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final palette = AppPalette.of(context);
    final address = order.shippingAddress ?? {};
    final lines = [
      address['line1'],
      address['line2'],
      address['city'],
      address['postal_code'],
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');
    final hasTracking = order.qxpressTrackingNo?.isNotEmpty == true;
    final hasBooking =
        order.hasParcelPlan ||
        order.trackingRegistered ||
        hasTracking ||
        order.trackingProvider == 'easyparcel';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Order #${order.displayNumber}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            '${DateFormat.yMMMd().format(order.createdAt)} · ${order.fulfillmentStatusLabel}',
            style: TextStyle(color: palette.textMuted),
          ),
          const SizedBox(height: 12),
          Text(
            order.deliveryMethodLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          ShippingCostSummary(order: order, showAllocation: true),
          if (order.needsDeliveryReview)
            const Text(
              'Check the original items and confirm shop delivery. Courier booking is blocked.',
            ),
          const SizedBox(height: 8),
          Text(
            [
              address['recipient_name'],
              address['phone'],
            ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
          ),
          if (lines.isNotEmpty) Text(lines),
          if (lines.isEmpty)
            const Text(
              'Delivery address missing — open the order before dispatch.',
            ),
          const SizedBox(height: 12),
          for (final item in order.items)
            Text(
              '${item.quantity} × ${item.productName}${item.optionLabel == null ? '' : ' · ${item.optionLabel}'}',
            ),
          if (order.customerRemarks?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            const Text(
              'Delivery requests',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(order.customerRemarks!),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => context.push('/orders/${order.id}', extra: order),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open order'),
          ),
          if (!order.hasCancellationHold &&
              (order.hasParcelPlan || order.canSplitIntoParcels))
            ParcelFulfillmentPanel(
              order: order,
              disabled: _busy,
              onChanged: () {
                ref.invalidate(fulfillmentOrdersProvider);
                ref.invalidate(orderByIdProvider(order.id));
                ref.invalidate(adminOrdersProvider);
                ref.invalidate(myOrdersProvider);
              },
            ),
          if (!order.hasParcelPlan && order.trackingProvider == 'easyparcel')
            PickupDiagnosticsPanel(
              key: ValueKey(
                '${order.id}-${order.qxpressTrackingNo}-${order.trackingUpdatedAt}',
              ),
              order: order,
              disabled: _busy,
            ),
          if (!order.hasParcelPlan &&
              hasTracking &&
              order.trackingProvider != 'easyparcel') ...[
            const Divider(),
            SelectableText(
              'Tracking: ${order.qxpressTrackingNo}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (order.trackingStatus != null) Text(order.trackingStatus!),
            if (order.trackingProvider == 'seventeentrack' &&
                order.trackingStatus == 'Registration pending')
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => DeliveryRepository().registerTracking(
                          orderId: order.id,
                          trackingNumber: order.qxpressTrackingNo!,
                        ),
                      ),
                child: const Text('Retry tracking registration'),
              ),
            if (order.trackingStatusDetail?.isNotEmpty == true &&
                !order.trackingStatusDetail!.startsWith('booking_issue:'))
              Text(order.trackingStatusDetail!),
            if (order.trackingUpdatedAt != null)
              Text(
                'Updated ${DateFormat.yMMMd().add_jm().format(order.trackingUpdatedAt!.toLocal())}',
                style: TextStyle(color: palette.textMuted),
              ),
          ],
          const SizedBox(height: 12),
          if (!order.hasParcelPlan &&
              !order.hasSampleTracking &&
              order.easyparcelAwbUrl?.isNotEmpty == true) ...[
            OutlinedButton.icon(
              onPressed: _busy ? null : _openLabel,
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('Print shipping label'),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    final settings = await ref.read(
                      shopSettingsProvider.future,
                    );
                    if (context.mounted) {
                      await printPackingSlip(
                        order,
                        context: context,
                        settings: settings,
                      );
                    }
                  }),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Print Packing Slip'),
          ),
          const SizedBox(height: 12),
          if (order.hasCancellationHold)
            const Text(
              'Delivery paused for cancellation. Open the order to review the request and refund status.',
            )
          else if (order.needsDeliveryReview && !hasBooking) ...[
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final confirmed = await confirmAction(
                        context,
                        title: 'Use shop delivery?',
                        message:
                            'The original product category is unavailable. Confirm the shop will hand-deliver '
                            'this entire order. This does not book a courier.',
                        confirmLabel: 'Use shop delivery',
                      );
                      if (confirmed && mounted) {
                        await _run(
                          () => ref
                              .read(orderRepositoryProvider)
                              .confirmShopDelivery(order.id),
                        );
                      }
                    },
              child: const Text('Use shop delivery'),
            ),
          ] else if (order.needsBookingAttention &&
              !order.hasSampleTracking) ...[
            if (!order.hasSampleTracking)
              OutlinedButton(
                onPressed: _busy ? null : () => _enterTracking(recovery: true),
                child: const Text('Recover existing shipment'),
              ),
          ] else if (order.status == OrderStatus.paid && !hasBooking)
            ElevatedButton(
              onPressed: _busy ? null : () => _moveTo(OrderStatus.packing),
              child: const Text('Start packing'),
            )
          else if (order.status == OrderStatus.packing && !hasBooking) ...[
            if (order.canUseCourier) ...[
              if (widget.easyParcelConnected)
                ElevatedButton.icon(
                  onPressed: _busy || lines.isEmpty
                      ? null
                      : _shipWithEasyParcel,
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Ship with EasyParcel'),
                ),
              OutlinedButton(
                onPressed: _busy || lines.isEmpty
                    ? null
                    : () => _enterTracking(),
                child: const Text('Add tracking number'),
              ),
            ] else
              ElevatedButton(
                onPressed: _busy || lines.isEmpty
                    ? null
                    : () => _moveTo(OrderStatus.shipped),
                child: const Text('Start delivery'),
              ),
          ] else if (order.status == OrderStatus.shipped &&
              order.isShopDelivery)
            ElevatedButton(
              onPressed: _busy ? null : () => _moveTo(OrderStatus.delivered),
              child: const Text('Mark as delivered'),
            )
          else if (order.status == OrderStatus.shipped &&
              order.trackingProvider != 'easyparcel' &&
              !hasTracking)
            OutlinedButton(
              onPressed: _busy || !order.canUseCourier
                  ? null
                  : () => _enterTracking(),
              child: const Text('Add tracking number'),
            ),
          if (_working)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

class _ShipmentSelection {
  final EasyParcelRate rate;
  final ParcelDetails parcel;
  const _ShipmentSelection(this.rate, this.parcel);
}

class _EasyParcelRateSheet extends ConsumerStatefulWidget {
  final String orderId;
  final Map<String, dynamic>? acceptedParcel;
  const _EasyParcelRateSheet({required this.orderId, this.acceptedParcel});
  @override
  ConsumerState<_EasyParcelRateSheet> createState() =>
      _EasyParcelRateSheetState();
}

class _EasyParcelRateSheetState extends ConsumerState<_EasyParcelRateSheet> {
  final _form = GlobalKey<FormState>();
  final _weight = TextEditingController();
  final _length = TextEditingController();
  final _width = TextEditingController();
  final _height = TextEditingController();
  DateTime? _date;
  ParcelDetails? _quotedParcel;
  Future<List<EasyParcelRate>>? _rates;
  EasyParcelRate? _selected;

  @override
  void initState() {
    super.initState();
    final parcel = widget.acceptedParcel;
    if (parcel != null) {
      _weight.text = parcel['weight_kg']?.toString() ?? '';
      _length.text = parcel['length_cm']?.toString() ?? '';
      _width.text = parcel['width_cm']?.toString() ?? '';
      _height.text = parcel['height_cm']?.toString() ?? '';
      final date = DateTime.tryParse(
        parcel['collection_date']?.toString() ?? '',
      );
      final now = DateTime.now().toUtc().add(const Duration(hours: 8));
      if (date != null &&
          date.isAfter(DateTime(now.year, now.month, now.day))) {
        _date = date;
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_weight, _length, _width, _height]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {
    _rates = null;
    _selected = null;
    _quotedParcel = null;
  });
  Future<void> _chooseDate() async {
    final sgNow = DateTime.now().toUtc().add(const Duration(hours: 8));
    final tomorrow = DateTime(sgNow.year, sgNow.month, sgNow.day + 1);
    final date = await showDatePicker(
      context: context,
      initialDate: _date ?? tomorrow,
      firstDate: tomorrow,
      lastDate: tomorrow.add(const Duration(days: 30)),
    );
    if (date != null && mounted) {
      _changed();
      setState(() => _date = date);
    }
  }

  void _getRates() {
    if (!_form.currentState!.validate() || _date == null) return;
    final parcel = ParcelDetails(
      weightKg: double.parse(_weight.text.trim()),
      lengthCm: double.parse(_length.text.trim()),
      widthCm: double.parse(_width.text.trim()),
      heightCm: double.parse(_height.text.trim()),
      collectionDate: DateFormat('yyyy-MM-dd').format(_date!),
    );
    setState(() {
      _selected = null;
      _quotedParcel = parcel;
      _rates = ref
          .read(easyParcelRepositoryProvider)
          .getRates(widget.orderId, parcel: parcel)
          .then((rates) => rates..sort((a, b) => a.price.compareTo(b.price)));
    });
  }

  Widget _measurement(TextEditingController controller, String label) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: controller,
          readOnly:
              widget.acceptedParcel?[identical(controller, _weight)
                  ? 'weight_kg'
                  : identical(controller, _length)
                  ? 'length_cm'
                  : identical(controller, _width)
                  ? 'width_cm'
                  : 'height_cm'] !=
              null,
          decoration: InputDecoration(labelText: label),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _changed(),
          validator: (value) {
            final n = double.tryParse(value?.trim() ?? '');
            return n == null || !n.isFinite || n <= 0
                ? 'Enter a number greater than zero.'
                : null;
          },
        ),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Parcel and courier',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Item weight comes from checkout. Enter any missing packed dimensions and choose a future pickup date. The service and price must still match the accepted quote.',
                        ),
                        const SizedBox(height: 12),
                        _measurement(_weight, 'Weight (kg)'),
                        _measurement(_length, 'Length (cm)'),
                        _measurement(_width, 'Width (cm)'),
                        _measurement(_height, 'Height (cm)'),
                        OutlinedButton.icon(
                          onPressed: _chooseDate,
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            _date == null
                                ? 'Choose pickup date'
                                : 'Pickup: ${DateFormat.yMMMd().format(_date!)}',
                          ),
                        ),
                        const Text(
                          'Pickup date uses Singapore time. Courier availability will be checked when booking.',
                        ),
                        OutlinedButton(
                          onPressed: _getRates,
                          child: const Text('Get courier rates'),
                        ),
                        if (_rates != null)
                          FutureBuilder<List<EasyParcelRate>>(
                            future: _rates,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState !=
                                  ConnectionState.done) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              if (snapshot.hasError) {
                                return Column(
                                  children: [
                                    const Text(
                                      'Could not load courier rates. Check the parcel and address, then retry.',
                                    ),
                                    TextButton(
                                      onPressed: _getRates,
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                );
                              }
                              final rates = snapshot.data ?? [];
                              if (rates.isEmpty) {
                                return const Text(
                                  'No courier is available for this parcel and address.',
                                );
                              }
                              return RadioGroup<EasyParcelRate>(
                                groupValue: _selected,
                                onChanged: (rate) =>
                                    setState(() => _selected = rate),
                                child: Column(
                                  children: [
                                    for (final rate in rates)
                                      RadioListTile<EasyParcelRate>(
                                        contentPadding: EdgeInsets.zero,
                                        value: rate,
                                        enabled: rate.bookingAvailable,
                                        title: Text(rate.courierName),
                                        subtitle: Text(
                                          '${formatPrice(rate.price)} total delivery${rate.bookingAvailable ? '' : '\n${rate.bookingMessage ?? 'For reference only'}'}',
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _selected == null || _quotedParcel == null
                    ? null
                    : () => Navigator.pop(
                        context,
                        _ShipmentSelection(_selected!, _quotedParcel!),
                      ),
                child: const Text('Book Shipment'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
