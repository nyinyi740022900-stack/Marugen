import 'package:intl/intl.dart';

/// Formats the shop's configured delivery lead time (`settings.
/// delivery_lead_days_min/max`, migration 0013) into the "Delivery by
/// 22–25 Sep" label shown on shop grid cards.
String formatDeliveryEstimate({
  required int minDays,
  required int maxDays,
  DateTime? from,
}) {
  final now = from ?? DateTime.now();
  final start = now.add(Duration(days: minDays));
  final end = now.add(Duration(days: maxDays));
  final formatter = DateFormat('d MMM');
  if (start.month == end.month && start.day == end.day) {
    return 'Delivery by ${formatter.format(end)}';
  }
  if (start.month == end.month) {
    return 'Delivery ${DateFormat('d').format(start)}–${formatter.format(end)}';
  }
  return 'Delivery ${formatter.format(start)} – ${formatter.format(end)}';
}
