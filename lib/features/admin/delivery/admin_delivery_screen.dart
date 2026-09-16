import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';
import '../../orders/presentation/orders_providers.dart';
import 'delivery_repository.dart';

/// Admin screen to hand paid orders off to Qxpress for delivery (or mark
/// them for store pickup — the default for live fish until Qxpress's live
/// animal shipping policy is confirmed).
class AdminDeliveryScreen extends ConsumerWidget {
  const AdminDeliveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(adminOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Delivery')),
      body: ordersAsync.when(
        data: (orders) {
          final readyToShip =
              orders.where((o) => o.status == OrderStatus.paid || o.status == OrderStatus.packing).toList();
          if (readyToShip.isEmpty) {
            return const Center(
              child: Text('No orders ready for delivery.', style: TextStyle(color: AppColors.grey)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: readyToShip.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final order = readyToShip[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Order #${order.id.substring(0, 8)}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(DateFormat.yMMMd().format(order.createdAt),
                          style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                      const SizedBox(height: 10),
                      if (order.qxpressTrackingNo != null)
                        Text('Tracking: ${order.qxpressTrackingNo}',
                            style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600))
                      else
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  // Address collection form would go here in
                                  // a full build — using a placeholder so
                                  // the flow is demonstrable end-to-end.
                                  _createShipment(context, ref, order.id);
                                },
                                child: const Text('Ship via Qxpress'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  await ref
                                      .read(orderRepositoryProvider)
                                      .updateOrderStatus(order.id, OrderStatus.packing);
                                  ref.invalidate(adminOrdersProvider);
                                },
                                child: const Text('Store Pickup'),
                              ),
                            ),
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
      ),
    );
  }

  Future<void> _createShipment(BuildContext context, WidgetRef ref, String orderId) async {
    try {
      await DeliveryRepository().createShipment(orderId: orderId, address: const {});
      ref.invalidate(adminOrdersProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Qxpress error: $e')));
      }
    }
  }
}
