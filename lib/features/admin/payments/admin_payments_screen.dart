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
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.black,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: AppShadows.card,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined,
                        color: AppColors.red, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Revenue',
                            style: TextStyle(
                                color: AppColors.white.withValues(alpha: 0.7),
                                fontSize: 12.5)),
                        const SizedBox(height: 2),
                        Text('S\$${totalRevenue.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: AppColors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 22)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text('TRANSACTIONS',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.8,
                    color: AppColors.grey)),
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
                  for (var i = 0; i < transactions.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                    _TransactionRow(order: transactions[i]),
                  ],
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.red)),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final Order order;
  const _TransactionRow({required this.order});

  Color get _statusColor {
    switch (order.status) {
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
    final rawId = order.stripePaymentIntentId ?? '';
    final shortId = rawId.length > 20 ? '${rawId.substring(0, 20)}…' : rawId;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.offWhite,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.credit_card_outlined, size: 17, color: AppColors.grey),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shortId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.grey)),
                const SizedBox(height: 2),
                Text(DateFormat.yMMMd().add_jm().format(order.createdAt),
                    style: const TextStyle(fontSize: 11.5, color: AppColors.greySoft)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('S\$${order.total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  orderStatusLabel(order.status).toUpperCase(),
                  style: TextStyle(
                      fontSize: 10, color: _statusColor, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
