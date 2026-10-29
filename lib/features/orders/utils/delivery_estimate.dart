import 'package:intl/intl.dart';

/// Calendar-day estimate from the shop's configured lead time in Singapore.
/// This is an estimate, not a carrier guarantee or a confirmed shop time slot.
String? deliveryArrivalRange(DateTime now, int minimumDays, int maximumDays) {
  if (minimumDays < 0 || maximumDays < minimumDays) return null;
  final singapore = now.toUtc().add(const Duration(hours: 8));
  final today = DateTime.utc(singapore.year, singapore.month, singapore.day);
  final first = today.add(Duration(days: minimumDays));
  final last = today.add(Duration(days: maximumDays));
  final withYear = first.year != last.year || first.year != today.year;
  final full = DateFormat(withYear ? 'd MMM yyyy' : 'd MMM', 'en_US');
  if (first == last) return full.format(first);
  if (first.month == last.month && first.year == last.year) {
    return '${first.day}–${full.format(last)}';
  }
  return '${full.format(first)} – ${full.format(last)}';
}
