import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';

/// Shows recorded milestones and the next stages without inventing completed
/// packing/dispatch events for orders that skipped them.
class OrderStatusTimeline extends StatelessWidget {
  final OrderStatus status;

  final String? trackingProvider;
  final int? trackingStatusCode;
  final int trackingProgress;
  final String? fulfillmentMethod;
  final List<String> statusHistory;

  const OrderStatusTimeline({
    super.key,
    required this.status,
    this.trackingProvider,
    this.trackingStatusCode,
    this.trackingProgress = 0,
    this.fulfillmentMethod,
    this.statusHistory = const [],
  });

  static const _steps = [
    (OrderStatus.pending, 'Placed', Icons.receipt_long_outlined),
    (OrderStatus.paid, 'Paid', Icons.payments_outlined),
    (OrderStatus.packing, 'Packing', Icons.inventory_2_outlined),
    (OrderStatus.shipped, 'Shipped', Icons.local_shipping_outlined),
    (OrderStatus.delivered, 'Delivered', Icons.home_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    if (status == OrderStatus.cancelled || status == OrderStatus.refunded) {
      final isCancelled = status == OrderStatus.cancelled;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppPalette.of(context).error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(
              Icons.cancel_outlined,
              color: AppPalette.of(context).error,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                isCancelled
                    ? 'This order was cancelled.'
                    : 'This order was refunded.',
                style: TextStyle(
                  color: AppPalette.of(context).error,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final courier = trackingProvider == 'easyparcel';
    final shop = fulfillmentMethod == 'shop_delivery';
    final collected =
        trackingProgress > 0 ||
        const {3, 4, 5, 11}.contains(trackingStatusCode);
    final booked = courier && !collected && status != OrderStatus.delivered;
    final current = booked ? 3 : _steps.indexWhere((s) => s.$1 == status);
    final all = courier
        ? <(OrderStatus, String, IconData)>[
            _steps[0],
            _steps[1],
            _steps[2],
            (OrderStatus.packing, 'Awaiting pickup', Icons.schedule),
            (OrderStatus.shipped, 'In transit', Icons.local_shipping_outlined),
            _steps.last,
          ]
        : <(OrderStatus, String, IconData)>[
            _steps[0],
            _steps[1],
            _steps[2],
            (
              OrderStatus.shipped,
              shop ? 'Out for delivery' : 'Shipped',
              Icons.local_shipping_outlined,
            ),
            _steps.last,
          ];
    final currentIndex = courier && !booked && current >= 3
        ? current + 1
        : current;
    final steps = <(String, IconData, _StepState)>[];
    for (var i = 0; i < all.length; i++) {
      final stage = all[i];
      final recorded =
          i == 0 ||
          (i == 1 && status.index >= OrderStatus.paid.index) ||
          statusHistory.contains(stage.$1.name);
      // A booked label is not proof of pickup. Earlier booking stages are
      // omitted once moving if no event recorded them.
      if (i < currentIndex && (!recorded || (courier && i == 3))) continue;
      steps.add((
        stage.$2,
        stage.$3,
        i < currentIndex
            ? _StepState.done
            : i == currentIndex
            ? _StepState.current
            : _StepState.upcoming,
      ));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: AppPalette.of(context).surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 600 ||
              MediaQuery.textScalerOf(context).scale(14) > 18) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  _StepDot(
                    label: steps[i].$1,
                    icon: steps[i].$2,
                    state: steps[i].$3,
                    horizontal: true,
                  ),
                  if (i != steps.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 15,
                        top: 4,
                        bottom: 4,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 2,
                          height: 12,
                          color: steps[i].$3 == _StepState.done
                              ? AppPalette.of(context).accent
                              : AppPalette.of(context).border,
                        ),
                      ),
                    ),
                ],
              ],
            );
          }
          return Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                Expanded(
                  child: _StepDot(
                    label: steps[i].$1,
                    icon: steps[i].$2,
                    state: steps[i].$3,
                  ),
                ),
                if (i != steps.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Container(
                      width: 10,
                      height: 2,
                      color: steps[i].$3 == _StepState.done
                          ? AppPalette.of(context).accent
                          : AppPalette.of(context).border,
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

enum _StepState { done, current, upcoming }

class _StepDot extends StatelessWidget {
  final String label;
  final IconData icon;
  final _StepState state;
  final bool horizontal;
  const _StepDot({
    required this.label,
    required this.icon,
    required this.state,
    this.horizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    final active = state != _StepState.upcoming;
    final color = active
        ? AppPalette.of(context).accent
        : AppPalette.of(context).textMuted;
    final dot = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: active ? AppColors.red : AppPalette.of(context).background,
        shape: BoxShape.circle,
        border: active
            ? null
            : Border.all(color: AppPalette.of(context).border),
      ),
      child: Icon(
        state == _StepState.done ? Icons.check : icon,
        size: 16,
        color: active ? AppColors.white : AppPalette.of(context).textMuted,
      ),
    );
    final text = Text(
      label,
      textAlign: horizontal ? TextAlign.start : TextAlign.center,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: state == _StepState.current
            ? FontWeight.w700
            : FontWeight.w500,
        color: color,
      ),
    );
    if (horizontal) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          dot,
          const SizedBox(width: AppSpacing.md),
          Expanded(child: text),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [dot, const SizedBox(height: 6), text],
    );
  }
}
