import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/app_notification.dart';

/// One `notifications` table serves both audiences — a customer only ever
/// sees their own rows (RLS: `user_id = auth.uid()`), and an admin viewing
/// the admin app's inbox sees their own `admin_alert` rows the same way
/// (each admin has their own `profiles` row and their own notifications,
/// written per-recipient by send-order-notification). RLS already scopes
/// every query to "mine", but every query below also filters by user_id
/// explicitly as defense-in-depth — a future RLS regression should fail
/// closed (empty result) rather than silently becoming a cross-user leak.
class NotificationRepository {
  final _client = SupabaseService.client;

  Future<List<AppNotification>> fetchMine() async {
    final user = SupabaseService.currentUser;
    if (user == null) return [];
    final data = await _client
        .from('notifications')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(100);
    return (data as List)
        .map((e) => AppNotification.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> fetchUnreadCount() async {
    final user = SupabaseService.currentUser;
    if (user == null) return 0;
    final count = await _client
        .from('notifications')
        .count()
        .eq('user_id', user.id)
        .eq('read', false);
    return count;
  }

  Future<void> markRead(String id) async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    await _client
        .from('notifications')
        .update({'read': true})
        .eq('id', id)
        .eq('user_id', user.id);
  }

  Future<void> markAllRead() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    await _client
        .from('notifications')
        .update({'read': true})
        .eq('user_id', user.id)
        .eq('read', false);
  }
}
