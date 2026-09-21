import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';
import '../../../shared/utils/price_format.dart';
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

    final rawOrdersAsync = ref.watch(myOrdersProvider);
    final visibleOrdersAsync = ref.watch(visibleMyOrdersProvider);
    final hasQuery = ref.watch(myOrdersSearchQueryProvider).trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: Column(
        children: [
          if (rawOrdersAsync.valueOrNull?.isNotEmpty ?? false)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: _OrderSearchField(),
            ),
          Expanded(
            child: visibleOrdersAsync.when(
              data: (orders) {
                if (orders.isEmpty) {
                  return hasQuery
                      ? const EmptyState(
                          icon: Icons.search_off_outlined,
                          title: 'No matching orders',
                          subtitle: 'Try a different order number, status, or item name.',
                        )
                      : const EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No orders yet',
                          subtitle: 'Your placed orders will show up here.',
                        );
                }
                // Pull-to-refresh — standard on every major shopping app's
                // order list (Amazon/Shopee/Lazada) so a customer can
                // manually confirm a just-placed order landed, rather than
                // only ever seeing whatever was cached on first load.
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(myOrdersProvider),
                  child: ListView.separated(
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
                                    Text('Order #${order.displayNumber}',
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                    _StatusBadge(status: order.status),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(DateFormat.yMMMd().add_jm().format(order.createdAt),
                                    style: const TextStyle(color: AppColors.grey, fontSize: 12)),
                                const SizedBox(height: 6),
                                Text(formatPrice(order.total),
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
                  ),
                );
              },
              loading: () => ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: 4,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => const ListRowSkeleton(),
              ),
              error: (e, _) => ErrorState(onRetry: () => ref.invalidate(myOrdersProvider)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Search field with its own stable [TextEditingController] so the cursor
/// and focus survive provider-driven rebuilds — same pattern as
/// shop_screen.dart's `_SearchField`.
class _OrderSearchField extends ConsumerStatefulWidget {
  const _OrderSearchField();

  @override
  ConsumerState<_OrderSearchField> createState() => _OrderSearchFieldState();
}

class _OrderSearchFieldState extends ConsumerState<_OrderSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(myOrdersSearchQueryProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(myOrdersSearchQueryProvider);
    if (query != _controller.text) {
      _controller.value = _controller.value.copyWith(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
    return TextField(
      controller: _controller,
      onChanged: (v) => ref.read(myOrdersSearchQueryProvider.notifier).state = v,
      decoration: InputDecoration(
        hintText: 'Search order #, status, or item…',
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => ref.read(myOrdersSearchQueryProvider.notifier).state = '',
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
