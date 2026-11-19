import 'dart:typed_data';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/home_banner.dart';
import '../../../shared/utils/image_upload.dart';

class HomeBannerRepository {
  final _client = SupabaseService.client;

  /// Customer fetch — RLS already limits anon/non-admin callers to live
  /// slides, so no client-side schedule filter is needed (or trusted).
  Future<List<HomeBanner>> fetchLiveBanners() async {
    final data = await _client
        .from('home_banners')
        .select()
        .order('sort_order')
        .order('created_at');
    return (data as List)
        .map((e) => HomeBanner.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Admin fetch — every slide, including hidden, scheduled and ended.
  Future<List<HomeBanner>> fetchAllBanners() => fetchLiveBanners();

  Future<String> upsertBanner(
    Map<String, dynamic> payload, {
    String? id,
  }) async {
    if (id != null) {
      await _client.from('home_banners').update(payload).eq('id', id);
      return id;
    }
    final row = await _client
        .from('home_banners')
        .insert(payload)
        .select()
        .single();
    return row['id'] as String;
  }

  Future<void> deleteBanner(String id) async {
    await _client.from('home_banners').delete().eq('id', id);
  }

  /// Persists a drag-reorder: position in [ids] becomes `sort_order`.
  Future<void> saveOrder(List<String> ids) async {
    for (var i = 0; i < ids.length; i++) {
      await _client
          .from('home_banners')
          .update({'sort_order': i})
          .eq('id', ids[i]);
    }
  }

  /// Same bucket and policies as product/service photos, under its own
  /// prefix.
  Future<String> uploadBannerImage(Uint8List bytes, String ext) async {
    final upload = prepareImageUpload(bytes, ext);
    final path =
        'home-banners/${DateTime.now().millisecondsSinceEpoch}.${upload.extension}';
    await _client.storage
        .from('product-images')
        .uploadBinary(path, bytes, fileOptions: upload.fileOptions);
    return _client.storage.from('product-images').getPublicUrl(path);
  }
}
