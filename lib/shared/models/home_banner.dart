import '../utils/server_time.dart';

/// One slide of the Shop tab's hero carousel (migration 0076). The server
/// only returns live slides to customers; [isLiveAt] mirrors that rule for
/// the admin list's status label.
class HomeBanner {
  final String id;
  final String imageUrl;
  final String? title;
  final String? subtitle;
  final String? ctaLabel;
  final String? linkUrl;
  final int sortOrder;
  final bool active;
  final DateTime? startsAt;
  final DateTime? endsAt;

  const HomeBanner({
    required this.id,
    required this.imageUrl,
    this.title,
    this.subtitle,
    this.ctaLabel,
    this.linkUrl,
    this.sortOrder = 0,
    this.active = true,
    this.startsAt,
    this.endsAt,
  });

  factory HomeBanner.fromMap(Map<String, dynamic> map) => HomeBanner(
    id: map['id'] as String,
    imageUrl: map['image_url'] as String? ?? '',
    title: _blankToNull(map['title']),
    subtitle: _blankToNull(map['subtitle']),
    ctaLabel: _blankToNull(map['cta_label']),
    linkUrl: _blankToNull(map['link_url']),
    sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    active: map['active'] as bool? ?? true,
    startsAt: tryParseServerTime(map['starts_at']),
    endsAt: tryParseServerTime(map['ends_at']),
  );

  static String? _blankToNull(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  bool get hasText => title != null || subtitle != null;

  /// An in-app path (`/product/<id>`, `/faq`) rather than a web address.
  bool get linksInsideApp => linkUrl != null && linkUrl!.startsWith('/');

  bool isLiveAt(DateTime now) =>
      active &&
      (startsAt == null || !startsAt!.isAfter(now)) &&
      (endsAt == null || endsAt!.isAfter(now));

  BannerSchedule scheduleAt(DateTime now) {
    if (!active) return BannerSchedule.hidden;
    if (startsAt != null && startsAt!.isAfter(now)) {
      return BannerSchedule.scheduled;
    }
    if (endsAt != null && !endsAt!.isAfter(now)) return BannerSchedule.ended;
    return BannerSchedule.live;
  }
}

enum BannerSchedule { live, scheduled, ended, hidden }
