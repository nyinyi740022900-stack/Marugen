import 'dart:typed_data';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/service.dart';

class ServiceRepository {
  final _client = SupabaseService.client;

  /// Customer-facing fetch — RLS already restricts anon/non-admin callers
  /// to `active = true` rows.
  Future<List<Service>> fetchServices() async {
    final data =
        await _client.from('services').select().order('sort_order').order('name');
    return (data as List).map((e) => Service.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<String> upsertService(Map<String, dynamic> payload, {String? id}) async {
    if (id != null) {
      await _client.from('services').update(payload).eq('id', id);
      return id;
    }
    final row = await _client.from('services').insert(payload).select().single();
    return row['id'] as String;
  }

  Future<void> deleteService(String id) async {
    await _client.from('services').delete().eq('id', id);
  }

  /// Reuses the `product-images` bucket under a `services/` prefix — same
  /// admin-write/anyone-read policies, no new bucket needed.
  Future<String> uploadServiceImage(String serviceId, Uint8List bytes, String ext) async {
    final path =
        'services/$serviceId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('product-images').uploadBinary(path, bytes);
    return _client.storage.from('product-images').getPublicUrl(path);
  }
}
