import 'dart:typed_data';

import '../../../core/supabase/supabase_client.dart';

/// Reads/writes the single-row `settings` table (see migration). Holds
/// shop-wide defaults that admin can change without a redeploy.
class SettingsRepository {
  final _client = SupabaseService.client;

  /// Uploads the promo banner photo to the shared product-images bucket
  /// under its own prefix — same bucket/pattern as ProductRepository.
  /// uploadProductImage, just namespaced by upload time instead of a
  /// product id since there's only ever one current banner.
  Future<String> uploadBannerImage(Uint8List bytes, String ext) async {
    final path = 'banners/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('product-images').uploadBinary(path, bytes);
    return _client.storage.from('product-images').getPublicUrl(path);
  }

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
