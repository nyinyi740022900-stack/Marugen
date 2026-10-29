import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';
import '../../../shared/widgets/content_width.dart';
import '../../../shared/utils/price_format.dart';
import '../../shop/presentation/shell_tab_provider.dart';
import 'orders_providers.dart';

/// Shown right after a successful Stripe payment instead of dumping the
/// customer back on the shop grid with only a snackbar. Confirms the order
/// number and total, and offers the two next steps every marketplace
/// offers: view the order, or keep shopping.
///
/// Reached with `context.go` so the back gesture cannot return to the
/// (now empty-cart) checkout screen.
class OrderSuccessScreen extends ConsumerWidget {
  final String orderId;
  const OrderSuccessScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderByIdProvider(orderId));
    final shortId = orderId.length >= 8 ? orderId.substring(0, 8) : orderId;

    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 560,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppSpacing.xl),
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: AppPalette.of(context).success
                                .withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 48,
                            color: AppPalette.of(context).success,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Order placed!',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Thank you for shopping with Marugen Fish Farm.\nWe will notify you as your order moves through each stage.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppPalette.of(context).textMuted,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppPalette.of(context).surface,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          boxShadow: AppShadows.card,
                        ),
                        child: Column(
                          children: [
                            _SummaryRow(
                              label: 'Order number',
                              value: '#$shortId',
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            orderAsync.maybeWhen(
                              data: (order) => order == null
                                  ? const SizedBox.shrink()
                                  : Column(
                                      children: [
                                        _SummaryRow(
                                          label: 'Items',
                                          value:
                                              '${order.items.fold<int>(0, (s, i) => s + i.quantity)}',
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                        _SummaryRow(
                                          label: 'Total paid',
                                          value: formatPrice(order.total),
                                          emphasize: true,
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                        _SummaryRow(
                                          label: 'Status',
                                          value:
                                              (order.refundStatusLabel ??
                                              orderStatusLabel(order.status)),
                                        ),
                                      ],
                                    ),
                              orElse: () => const Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm,
                                ),
                                child: SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      ElevatedButton(
                        onPressed: () {
                          ref.read(customerTabIndexProvider.notifier).state =
                              2; // Orders tab
                          context.go('/');
                          context.push('/orders/$orderId');
                        },
                        child: const Text('View Order'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton(
                        onPressed: () {
                          ref.read(customerTabIndexProvider.notifier).state =
                              0; // Shop tab
                          context.go('/');
                        },
                        child: const Text('Continue Shopping'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      label,
      style: TextStyle(fontSize: 13.5, color: AppPalette.of(context).textMuted),
    );
    final valueText = Text(
      value,
      style: TextStyle(
        fontSize: emphasize ? 17 : 13.5,
        fontWeight: FontWeight.w700,
        color: emphasize
            ? AppPalette.of(context).accent
            : AppPalette.of(context).text,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [labelText, const SizedBox(height: 4), valueText],
          );
        }
        return Row(
          children: [
            Expanded(child: labelText),
            const SizedBox(width: 12),
            Flexible(
              child: Align(alignment: Alignment.centerRight, child: valueText),
            ),
          ],
        );
      },
    );
  }
}
