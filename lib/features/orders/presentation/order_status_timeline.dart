import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';

/// A simple horizontal stepper for the order lifecycle: Placed → Paid →
/// Packed → Shipped → Delivered. Cancelled/refunded orders get a distinct
/// terminal-state banner instead, since they never reach "Delivered".
class OrderStatusTimeline extends StatelessWidget {
  final OrderStatus status;
  const OrderStatusTimeline({super.key, required this.status});

  static const _steps = [
    (OrderStatus.pending, 'Placed', Icons.receipt_long_outlined),
    (OrderStatus.paid, 'Paid', Icons.payments_outlined),
    (OrderStatus.packing, 'Packed', Icons.inventory_2_outlined),
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
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: AppColors.error, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Text(
              isCancelled ? 'This order was cancelled.' : 'This order was refunded.',
              style: const TextStyle(
                  color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
          ],
        ),
      );
    }

    final currentIndex = _steps.indexWhere((s) => s.$1 == status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: StepDotRow(
        steps: [for (final s in _steps) (s.$2, s.$3)],
        currentIndex: currentIndex,
      ),
    );
  }
}

/// The always-visible expected-journey path (booked → collected → in
/// transit → delivered) for an EasyParcel shipment. Shown alongside the
/// free-text tracking status card so the customer sees the whole route and
/// roughly where they are even between refreshes/webhook pushes, instead of
/// only ever a single current-status line with no sense of what's next.
/// Codes per migration 0043 / EasyParcel's Shipment Status Codes.
class EasyParcelStageTimeline extends StatelessWidget {
  final int? statusCode;
  const EasyParcelStageTimeline({super.key, required this.statusCode});

  static const _stages = [
    ('Booked', Icons.schedule),
    ('Collected', Icons.inventory_2_outlined),
    ('In Transit', Icons.local_shipping_outlined),
    ('Delivered', Icons.check_circle_outline),
  ];

  int _stageIndexForCode(int? code) {
    switch (code) {
      case 3: // Collected
        return 1;
      case 4: // Delivery In Transit
      case 11: // Drop Off
        return 2;
      case 5: // Delivered
        return 3;
      default: // null, 2 To Be Collected, 7 Schedule In Arrangement, 8 On Hold
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (statusCode == 0 || statusCode == 6) {
      final isCancelled = statusCode == 0;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            const Icon(Icons.assignment_return_outlined, color: AppColors.error, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Text(
              isCancelled ? 'This shipment was cancelled.' : 'This shipment was returned.',
              style: const TextStyle(
                  color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 13.5),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: StepDotRow(steps: _stages, currentIndex: _stageIndexForCode(statusCode)),
    );
  }
}

/// Shared horizontal stepper row used by [OrderStatusTimeline] and
/// [EasyParcelStageTimeline] — a list of (label, icon) steps with the one
/// at [currentIndex] highlighted and everything before it marked done.
class StepDotRow extends StatelessWidget {
  final List<(String, IconData)> steps;
  final int currentIndex;
  const StepDotRow({super.key, required this.steps, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: _StepDot(
              label: steps[i].$1,
              icon: steps[i].$2,
              state: i < currentIndex
                  ? _StepState.done
                  : i == currentIndex
                      ? _StepState.current
                      : _StepState.upcoming,
            ),
          ),
          if (i != steps.length - 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Container(
                width: 14,
                height: 2,
                color: i < currentIndex ? AppColors.red : AppColors.lightGrey,
              ),
            ),
        ],
      ],
    );
  }
}

enum _StepState { done, current, upcoming }

class _StepDot extends StatelessWidget {
  final String label;
  final IconData icon;
  final _StepState state;
  const _StepDot({required this.label, required this.icon, required this.state});

  @override
  Widget build(BuildContext context) {
    final active = state != _StepState.upcoming;
    final color = active ? AppColors.red : AppColors.greySoft;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: active ? AppColors.red : AppColors.offWhite,
            shape: BoxShape.circle,
            border: active ? null : Border.all(color: AppColors.lightGrey),
          ),
          child: Icon(
            state == _StepState.done ? Icons.check : icon,
            size: 16,
            color: active ? AppColors.white : AppColors.greySoft,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: state == _StepState.current ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}
