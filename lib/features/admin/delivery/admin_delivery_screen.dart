import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';
import '../../orders/presentation/orders_providers.dart';
import 'delivery_repository.dart';

/// Fulfillment pane embedded in the Orders hub (no Scaffold).
class AdminDeliveryPane extends ConsumerWidget {
  const AdminDeliveryPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(adminOrdersProvider);

    return ordersAsync.when(
      data: (orders) {
        final readyToShip = orders
            .where((o) =>
                o.status == OrderStatus.paid || o.status == OrderStatus.packing)
            .toList();
        if (readyToShip.isEmpty) {
          return const Center(
            child: Text('No orders ready for delivery.',
                style: TextStyle(color: AppColors.grey)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: readyToShip.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final order = readyToShip[i];
            final fulfillment =
                order.shippingAddress?['fulfillment'] as String? ?? 'delivery';
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order #${order.id.substring(0, 8)}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                        '${DateFormat.yMMMd().format(order.createdAt)} · ${fulfillment == 'pickup' ? 'Pickup' : 'Delivery'}',
                        style:
                            const TextStyle(color: AppColors.grey, fontSize: 12)),
                    const SizedBox(height: 10),
                    if (order.qxpressTrackingNo != null) ...[
                      Row(
                        children: [
                          const Icon(Icons.local_shipping_outlined,
                              size: 15, color: AppColors.success),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text('Tracking: ${order.qxpressTrackingNo}',
                                style: const TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      if (order.trackingStatus != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          order.trackingStatusDetail ?? order.trackingStatus!,
                          style: const TextStyle(fontSize: 12, color: AppColors.grey),
                        ),
                      ] else if (order.trackingRegistered) ...[
                        const SizedBox(height: 4),
                        const Text('Waiting for first carrier update…',
                            style: TextStyle(fontSize: 12, color: AppColors.greySoft)),
                      ] else ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _registerTracking(
                                context, ref, order.id, order.qxpressTrackingNo!),
                            icon: const Icon(Icons.track_changes, size: 16),
                            label: const Text('Track with 17TRACK'),
                          ),
                        ),
                      ],
                    ] else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              if (fulfillment != 'pickup')
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        _createShipment(context, ref, order.id),
                                    child: const Text('Ship via Qxpress'),
                                  ),
                                ),
                              if (fulfillment != 'pickup') const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () async {
                                    await ref
                                        .read(orderRepositoryProvider)
                                        .updateOrderStatus(
                                            order.id, OrderStatus.packing);
                                    ref.invalidate(adminOrdersProvider);
                                  },
                                  child: Text(fulfillment == 'pickup'
                                      ? 'Ready for pickup'
                                      : 'Store Pickup'),
                                ),
                              ),
                            ],
                          ),
                          if (fulfillment != 'pickup') ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => _enterTrackingManually(context, ref, order.id),
                              icon: const Icon(Icons.edit_outlined, size: 15),
                              label: const Text('Or enter another courier\'s tracking #'),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Future<void> _createShipment(
      BuildContext context, WidgetRef ref, String orderId) async {
    final repo = DeliveryRepository();
    try {
      final result = await repo.createShipment(orderId: orderId, address: const {});
      // Auto-register the fresh tracking number with 17TRACK so status
      // updates start flowing in without a second manual step.
      final trackingNumber = result['tracking_number'] as String?;
      if (trackingNumber != null && trackingNumber.isNotEmpty) {
        try {
          await repo.registerTracking(orderId: orderId, trackingNumber: trackingNumber);
        } catch (_) {
          // Shipment itself succeeded — tracking registration can be retried
          // from the "Track with 17TRACK" button that now appears.
        }
      }
      ref.invalidate(adminOrdersProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Qxpress error: $e')));
      }
    }
  }

  Future<void> _registerTracking(
      BuildContext context, WidgetRef ref, String orderId, String trackingNumber) async {
    try {
      await DeliveryRepository().registerTracking(orderId: orderId, trackingNumber: trackingNumber);
      ref.invalidate(adminOrdersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Registered with 17TRACK')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('17TRACK error: $e')));
      }
    }
  }

  /// For orders shipped via a courier other than Qxpress — admin types the
  /// tracking number in by hand and it's registered with 17TRACK the same
  /// way (17TRACK auto-detects the carrier from the number format).
  Future<void> _enterTrackingManually(
      BuildContext context, WidgetRef ref, String orderId) async {
    final controller = TextEditingController();
    final trackingNumber = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter tracking number'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. SG1234567890'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (trackingNumber == null || trackingNumber.isEmpty) return;
    if (!context.mounted) return;
    await _registerTracking(context, ref, orderId, trackingNumber);
  }
}
