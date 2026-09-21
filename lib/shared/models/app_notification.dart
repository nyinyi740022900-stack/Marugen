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

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.orderId,
    required this.type,
    required this.read,
    required this.createdAt,
  });

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        title: title,
        body: body,
        orderId: orderId,
        type: type,
        read: read ?? this.read,
        createdAt: createdAt,
      );

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as String,
      title: map['title'] as String,
      body: map['body'] as String,
      orderId: map['order_id'] as String?,
      type: map['type'] as String? ?? 'order_status',
      read: map['read'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
