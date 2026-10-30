import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/promo_code.dart';

class PromoRepository {
  final SupabaseClient _client;

  PromoRepository({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  /// Checks one exact code (case-insensitive) for checkout through the
  /// `check_promo_code` RPC (0071_private_promo_codes.sql). Customers can no
  /// longer read the `promo_codes` table, and the RPC never treats `%`, `_`
  /// or `*` as wildcards. An inactive or unknown code comes back as null.
  Future<PromoCode?> lookupCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;
    // A plain list (the RPC returns at most one row) rather than
    // maybeSingle(), whose zero-row handling for POST requests depends on
    // the PostgREST error wording.
    final rows = await _client.rpc(
      'check_promo_code',
      params: {'p_code': trimmed},
    ) as List;
    if (rows.isEmpty) return null;
    return PromoCode.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  /// Admin: all promo codes (active + inactive), newest first.
  Future<List<PromoCode>> fetchAll() async {
    final data = await _client
        .from('promo_codes')
        .select()
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => PromoCode.fromMap(e as Map<String, dynamic>))
        .toList();
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
