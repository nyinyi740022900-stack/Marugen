import '../utils/server_time.dart';

/// One row from `public.notifications` — the in-app inbox counterpart to
/// a push notification (see supabase/functions/send-order-notification
/// and 0016_notifications.sql). Written for every recipient regardless of
/// whether a push was actually delivered, so this list is the reliable
/// source of truth, not the transient SnackBar
/// PushNotificationService shows for a foreground push.
class AppNotification {
  final String id;
  final String title;
  final String body;
  final String? orderId;

  /// 'order_status' (sent to the customer who owns the order) or
  /// 'admin_alert' (sent to every staff/owner, e.g. out-for-delivery).
  final String type;
  final bool read;
  final DateTime createdAt;
  final DateTime? dismissedAt;

  /// The server's de-duplication key. Ops monitoring alerts (migration
  /// 0080) carry `ops:<finding>...` for an order and
  /// `ops-daily:<finding>:<day>` for the shop as a whole.
  final String? key;

  /// A monitoring alert for staff: something is wrong, as opposed to an
  /// ordinary "new order" / "out for delivery" notice.
  bool get isOpsAlert =>
      type == 'admin_alert' &&
      (key?.startsWith('ops:') == true ||
          key?.startsWith('ops-daily:') == true);

  /// The finding of a shop-wide alert (`easyparcel_disconnected`,
  /// `reconcile_failing`), or null for anything else.
  String? get shopWideFinding {
    final parts = key?.split(':');
    return parts != null && parts.length >= 2 && parts.first == 'ops-daily'
        ? parts[1]
        : null;
  }

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.orderId,
    required this.type,
    required this.read,
    required this.createdAt,
    this.dismissedAt,
    this.key,
  });

  AppNotification copyWith({bool? read}) => AppNotification(
    id: id,
    title: title,
    body: body,
    orderId: orderId,
    type: type,
    read: read ?? this.read,
    createdAt: createdAt,
    dismissedAt: dismissedAt,
    key: key,
  );

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as String,
      title: map['title'] as String,
      body: map['body'] as String,
      orderId: map['order_id'] as String?,
      type: map['type'] as String? ?? 'order_status',
      read: map['read'] as bool? ?? false,
      createdAt: parseServerTime(map['created_at'] as String),
      dismissedAt: tryParseServerTime(map['dismissed_at']),
      key: map['key'] as String?,
    );
  }
}
