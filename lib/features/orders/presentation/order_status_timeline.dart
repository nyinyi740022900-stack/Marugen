import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';

/// A simple horizontal stepper for the order lifecycle: Placed → Paid →
/// Packed → (Collected, EasyParcel orders only) → Shipped → Delivered.
/// Cancelled/refunded orders get a distinct terminal-state banner instead,
/// since they never reach "Delivered".
///
/// "Collected" is a single extra step layered onto the same row rather than
/// a second row: it reflects [trackingStatusCode] (the courier having
/// physically picked up the parcel), which is a finer-grained signal than
/// [status] alone — [status] already flips to `shipped` the moment the shop
/// books/dispatches it (same as the manual 17TRACK path), which can be
/// before the courier actually collects it, so "Shipped" can legitimately
/// show done slightly ahead of "Collected".
class OrderStatusTimeline extends StatelessWidget {
  final OrderStatus status;

  /// Pass 'easyparcel' to show the extra "Collected" step; omit for manual
  /// 17TRACK orders and orders with no tracking yet, which have no
  /// per-pickup signal to show it from.
  final String? trackingProvider;

  /// EasyParcel's numeric shipment status code (migration 0043) — 3+ means
  /// the courier has collected the parcel. Only meaningful alongside
  /// trackingProvider == 'easyparcel'.
  final int? trackingStatusCode;

  const OrderStatusTimeline({
    super.key,
    required this.status,
    this.trackingProvider,
    this.trackingStatusCode,
  });

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
    final showCollected = trackingProvider == 'easyparcel';

    // Whether the parcel has actually been collected — true either once
    // EasyParcel reports it (code 3+), or implicitly once the order has
    // moved past "shipped" (delivered), even if that particular refresh
    // never landed.
    final collected =
        (trackingStatusCode != null && trackingStatusCode! >= 3) ||
            currentIndex > _steps.indexWhere((s) => s.$1 == OrderStatus.shipped);
    final collectedState = collected
        ? _StepState.done
        : status == OrderStatus.shipped
            ? _StepState.current
            : _StepState.upcoming;

    final steps = <(String, IconData, _StepState)>[];
    for (var i = 0; i < _steps.length; i++) {
      steps.add((
        _steps[i].$2,
        _steps[i].$3,
        i < currentIndex
            ? _StepState.done
            : i == currentIndex
                ? _StepState.current
                : _StepState.upcoming,
      ));
      if (_steps[i].$1 == OrderStatus.packing && showCollected) {
        steps.add(('Collected', Icons.local_shipping_outlined, collectedState));
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Expanded(
              child: _StepDot(label: steps[i].$1, icon: steps[i].$2, state: steps[i].$3),
            ),
            if (i != steps.length - 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Container(
                  width: 10,
                  height: 2,
                  color: steps[i].$3 == _StepState.done ? AppColors.red : AppColors.lightGrey,
                ),
              ),
          ],
        ],
      ),
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
