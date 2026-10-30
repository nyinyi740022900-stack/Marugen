/// Supabase returns `timestamptz` columns as UTC ISO strings, and intl's
/// DateFormat prints a DateTime's own fields without converting — so a UTC
/// value showed Singapore users times 8 hours early (and the previous day
/// before 08:00). Models parse server timestamps through these helpers so
/// every screen, notification and invoice shows device-local time.
///
/// Going the other way, always send `.toUtc().toIso8601String()`: a local
/// DateTime serializes without an offset, which the database reads as UTC.
DateTime parseServerTime(String value) => DateTime.parse(value).toLocal();

/// [parseServerTime] for optional columns; null for a missing or invalid
/// value.
DateTime? tryParseServerTime(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}
