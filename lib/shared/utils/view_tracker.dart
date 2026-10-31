import 'package:flutter/foundation.dart';

import '../../core/supabase/supabase_client.dart';

/// Fire-and-forget analytics inserts — never awaited by callers, never
/// allowed to surface an error to the UI. Backs the admin Analytics
/// screen's "product views" and "app visits" charts.
///
/// Only release builds count: debug and profile runs (development, QA,
/// screenshots) reach the production project too and used to inflate the
/// owner's numbers.
class ViewTracker {
  static bool get _enabled => kReleaseMode;

  static Future<void> logProductView(String productId) async {
    if (!_enabled) return;
    try {
      final client = SupabaseService.client;
      await client.from('product_views').insert({
        'product_id': productId,
        'user_id': client.auth.currentUser?.id,
      });
    } catch (_) {
      // Analytics is best-effort — never block or break the product page.
    }
  }

  static Future<void> logAppVisit() async {
    if (!_enabled) return;
    try {
      final client = SupabaseService.client;
      await client.from('app_visits').insert({
        'user_id': client.auth.currentUser?.id,
      });
    } catch (_) {
      // Best-effort — never block app startup.
    }
  }
}
