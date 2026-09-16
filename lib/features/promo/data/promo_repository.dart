import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/promo_code.dart';

class PromoRepository {
  final _client = SupabaseService.client;

  /// Looks up a code (case-insensitive) for checkout. RLS only exposes
  /// `active = true` rows to non-admins, so an inactive code simply comes
  /// back as null here — treated the same as "not found".
  Future<PromoCode?> lookupCode(String code) async {
    final data = await _client
        .from('promo_codes')
        .select()
        .ilike('code', code.trim())
        .maybeSingle();
    if (data == null) return null;
    return PromoCode.fromMap(data);
  }

  /// Admin: all promo codes (active + inactive), newest first.
  Future<List<PromoCode>> fetchAll() async {
    final data =
        await _client.from('promo_codes').select().order('created_at', ascending: false);
    return (data as List).map((e) => PromoCode.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<void> upsert(Map<String, dynamic> payload, {String? id}) async {
    if (id != null) {
      await _client.from('promo_codes').update(payload).eq('id', id);
    } else {
      await _client.from('promo_codes').insert(payload);
    }
  }

  Future<void> delete(String id) async {
    await _client.from('promo_codes').delete().eq('id', id);
  }
}
