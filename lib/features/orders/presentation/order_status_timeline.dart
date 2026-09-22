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

    final showCollected = trackingProvider == 'easyparcel';

    // Build the merged step list (with "Collected" spliced in right after
    // "Packed" for EasyParcel orders), then pick a single "current"
    // position by its place IN THAT MERGED LIST — everything before it is
    // done, everything after is upcoming. This is deliberately positional
    // rather than deriving each step's done/current state from its own
    // independent signal (status-index for the base steps,
    // trackingStatusCode for Collected): those two signals disagree in the
    // common case where an order is already `shipped` in the DB (set the
    // moment it's booked) but not yet physically collected, and computing
    // each step's state independently from whichever signal it happens to
    // track could mark two steps "current" at once. Anchoring everything
    // to one merged index guarantees exactly one current step, and also
    // means "Shipped" intentionally doesn't show done until collection
    // is confirmed — a more accurate label than the raw DB status alone.
    final baseIndex = _steps.indexWhere((s) => s.$1 == status);
    final packingIndex = _steps.indexWhere((s) => s.$1 == OrderStatus.packing);
    final shippedIndex = _steps.indexWhere((s) => s.$1 == OrderStatus.shipped);
    final collected = trackingStatusCode != null && trackingStatusCode! >= 3;

    final labels = <String>[];
    final icons = <IconData>[];
    int? collectedMergedIndex;
    int? shippedMergedIndex;
    for (var i = 0; i < _steps.length; i++) {
      if (i == shippedIndex) shippedMergedIndex = labels.length;
      labels.add(_steps[i].$2);
      icons.add(_steps[i].$3);
      if (i == packingIndex && showCollected) {
        collectedMergedIndex = labels.length;
        labels.add('Collected');
        icons.add(Icons.local_shipping_outlined);
      }
    }

    final currentIndex = switch (baseIndex) {
      // Steps at or before "Packed" are never preceded by the spliced-in
      // Collected step, so their merged index still equals their original
      // index in _steps.
      _ when baseIndex <= packingIndex => baseIndex,
      _ when baseIndex == shippedIndex =>
        (showCollected && !collected) ? collectedMergedIndex! : shippedMergedIndex!,
      _ => labels.length - 1, // delivered — last step
    };

    final steps = <(String, IconData, _StepState)>[];
    for (var i = 0; i < labels.length; i++) {
      steps.add((
        labels[i],
        icons[i],
        i < currentIndex
            ? _StepState.done
            : i == currentIndex
                ? _StepState.current
                : _StepState.upcoming,
      ));
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
