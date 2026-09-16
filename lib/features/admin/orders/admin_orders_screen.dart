import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';
import '../../orders/presentation/orders_providers.dart';
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

class _OrdersListPane extends ConsumerWidget {
  const _OrdersListPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(adminOrdersProvider);
    final filter = ref.watch(adminOrderStatusFilterProvider);

    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: filter == null,
                  onSelected: (_) =>
                      ref.read(adminOrderStatusFilterProvider.notifier).state = null,
                ),
              ),
              for (final s in OrderStatus.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
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
        const Divider(height: 1),
        Expanded(
          child: ordersAsync.when(
            data: (orders) {
              if (orders.isEmpty) {
                return const Center(
                  child: Text('No orders.', style: TextStyle(color: AppColors.grey)),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _AdminOrderCard(order: orders[i]),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }
}

class _AdminOrderCard extends ConsumerWidget {
  final Order order;
  const _AdminOrderCard({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fulfillment = order.shippingAddress?['fulfillment'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Order #${order.id.substring(0, 8)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (fulfillment == 'pickup')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.offWhite,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: const Text('Pickup',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  )
                else if (fulfillment == 'delivery')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.offWhite,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: const Text('Delivery',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(DateFormat.yMMMd().add_jm().format(order.createdAt),
                style: const TextStyle(color: AppColors.grey, fontSize: 12)),
            const SizedBox(height: 4),
            Text('S\$${order.total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            DropdownButtonFormField<OrderStatus>(
              initialValue: order.status,
              decoration: const InputDecoration(labelText: 'Status', isDense: true),
              items: [
                for (final s in OrderStatus.values)
                  DropdownMenuItem(value: s, child: Text(orderStatusLabel(s))),
              ],
              onChanged: (s) async {
                if (s == null) return;
                await ref.read(orderRepositoryProvider).updateOrderStatus(order.id, s);
                ref.invalidate(adminOrdersProvider);
              },
            ),
          ],
        ),
      ),
    );
  }
}
