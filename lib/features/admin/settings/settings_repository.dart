import '../../../core/supabase/supabase_client.dart';

/// Reads/writes the single-row `settings` table (see migration). Holds
/// shop-wide defaults that admin can change without a redeploy.
class SettingsRepository {
  final _client = SupabaseService.client;

  Future<Map<String, dynamic>> fetchSettings() async {
    final data = await _client.from('settings').select().eq('id', 1).maybeSingle();
    return data ??
        {
          'shop_name': 'Marugen Koi Farm',
          'shop_phone': '',
          'shop_address': '',
          'currency': 'SGD',
          'gst_percent': 9,
          'gst_included_in_price': true,
          'show_price_default': true,
          'low_stock_threshold': 5,
        };
  }

  Future<void> updateSettings(Map<String, dynamic> payload) async {
    await _client.from('settings').upsert({'id': 1, ...payload});
  }
}
