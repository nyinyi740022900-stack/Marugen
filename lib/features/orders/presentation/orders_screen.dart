import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../auth/presentation/auth_providers.dart';
import 'orders_providers.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(isLoggedInProvider);

    if (!isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Orders')),
        body: const _LoggedOutOrders(),
      );
    }

    final ordersAsync = ref.watch(myOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No orders yet',
              subtitle: 'Your placed orders will show up here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final order = orders[i];
              return Card(
                child: InkWell(
                  onTap: () => context.push('/orders/${order.id}', extra: order),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Order #${order.id.substring(0, 8)}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            _StatusBadge(status: order.status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(DateFormat.yMMMd().add_jm().format(order.createdAt),
                            style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                        const SizedBox(height: 6),
                        Text('S\$${order.total.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (order.qxpressTrackingNo != null) ...[
                          const SizedBox(height: 6),
                          Text('Tracking: ${order.qxpressTrackingNo}',
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: 4,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => const ListRowSkeleton(),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

/// Shown on the Orders tab when browsing as a guest.
class _LoggedOutOrders extends StatelessWidget {
  const _LoggedOutOrders();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.receipt_long_outlined,
      title: 'You are not logged in',
      subtitle: 'Log in to see your orders.',
      actionLabel: 'Log In',
      onAction: () => context.push('/login'),
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
      decoration: BoxDecoration(color: _color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Text(
        orderStatusLabel(status),
        style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
