import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';
import '../../orders/presentation/orders_providers.dart';

/// Payments ledger pane embedded in the Orders hub (no Scaffold).
class AdminPaymentsPane extends ConsumerWidget {
  const AdminPaymentsPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(adminOrdersProvider);

    return ordersAsync.when(
      data: (orders) {
        final transactions = orders
            .where((o) =>
                o.stripePaymentIntentId != null &&
                o.stripePaymentIntentId!.isNotEmpty)
            .toList();
        if (transactions.isEmpty) {
          return const Center(
            child:
                Text('No transactions yet.', style: TextStyle(color: AppColors.grey)),
          );
        }
        final totalRevenue = transactions
            .where((o) =>
                o.status != OrderStatus.refunded &&
                o.status != OrderStatus.cancelled)
            .fold<double>(0, (sum, o) => sum + o.total);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                color: AppColors.black,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Revenue',
                          style: TextStyle(color: AppColors.white)),
                      Text('S\$${totalRevenue.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: AppColors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18)),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: transactions.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, i) {
                  final o = transactions[i];
                  final rawId = o.stripePaymentIntentId ?? '';
                  final shortId =
                      rawId.length > 20 ? '${rawId.substring(0, 20)}…' : rawId;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('S\$${o.total.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '$shortId\n${DateFormat.yMMMd().add_jm().format(o.createdAt)}'),
                    isThreeLine: true,
                    trailing: Text(orderStatusLabel(o.status),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.red)),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class AdminPaymentsScreen extends StatelessWidget {
  const AdminPaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payments')),
      body: const AdminPaymentsPane(),
    );
  }
}
