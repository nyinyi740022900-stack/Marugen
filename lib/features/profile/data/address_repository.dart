import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/address.dart';

/// CRUD for the customer's saved delivery addresses.
/// See `supabase/migrations/0002_addresses.sql`.
class AddressRepository {
  final _client = SupabaseService.client;

  Future<List<Address>> fetchMyAddresses() async {
    final user = SupabaseService.currentUser;
    if (user == null) return [];
    final data = await _client
        .from('addresses')
        .select()
        .eq('user_id', user.id)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);
    return (data as List).map((e) => Address.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Read-only lookup of another user's saved addresses — for the admin
  /// "view customer" screen. Relies on the admin-only RLS policy added in
  /// 0046_admin_view_addresses.sql.
  Future<List<Address>> fetchAddressesForUser(String userId) async {
    final data = await _client
        .from('addresses')
        .select()
        .eq('user_id', userId)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);
    return (data as List).map((e) => Address.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<Address> createAddress(Address address) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('Not logged in');

    // The insert itself is a single new row, so it's safe to set its real
    // is_default value directly. The atomic flip below is only needed
    // when it's the new default, to guarantee every other address the
    // user owns is un-defaulted in the same statement — see
    // set_default_address (0027_atomic_default_address.sql).
    final row = await _client
        .from('addresses')
        .insert({...address.toMap(), 'user_id': user.id})
        .select()
        .single();
    final created = Address.fromMap(row);

    if (address.isDefault) {
      await _setDefault(created.id);
    }
    return created;
  }

  Future<void> updateAddress(Address address) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('Not logged in');

    // A single-row update is safe on its own for turning the default OFF
    // (it only ever touches this row) — the atomic flip below is only
    // needed when turning it ON, to guarantee every other address the
    // user owns is un-defaulted in the same statement. .eq('user_id', ...)
    // here is defense-in-depth on top of RLS (0002_addresses.sql) — not
    // load-bearing today, but keeps this query failing closed instead of
    // silently becoming a cross-user write if a future migration ever
    // weakens that policy.
    await _client
        .from('addresses')
        .update(address.toMap())
        .eq('id', address.id)
        .eq('user_id', user.id);

    if (address.isDefault) {
      await _setDefault(address.id);
    }
  }

  Future<void> deleteAddress(String id) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('Not logged in');
    await _client.from('addresses').delete().eq('id', id).eq('user_id', user.id);
  }

  /// Atomically makes [addressId] the caller's one default address and
  /// un-defaults every other address they own, in a single DB statement —
  /// see set_default_address in 0027_atomic_default_address.sql.
  Future<void> _setDefault(String addressId) async {
    await _client.rpc('set_default_address', params: {'p_address_id': addressId});
  }
}
