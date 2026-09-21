import '../../core/supabase/supabase_client.dart';

/// Fire-and-forget analytics inserts — never awaited by callers, never
/// allowed to surface an error to the UI. Backs the admin Analytics
/// screen's "product views" and "app visits" charts.
class ViewTracker {
  static final _client = SupabaseService.client;

  static Future<void> logProductView(String productId) async {
    try {
      await _client.from('product_views').insert({
        'product_id': productId,
        'user_id': _client.auth.currentUser?.id,
      });
    } catch (_) {
      // Analytics is best-effort — never block or break the product page.
    }
  }

  static Future<void> logAppVisit() async {
    try {
      await _client.from('app_visits').insert({
        'user_id': _client.auth.currentUser?.id,
      });
    } catch (_) {
      // Best-effort — never block app startup.
    }
  }
}
