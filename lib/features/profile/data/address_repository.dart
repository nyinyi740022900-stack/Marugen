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

  Future<Address> createAddress(Address address) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('Not logged in');

    if (address.isDefault) {
      await _clearDefaults(user.id);
    }

    final row = await _client
        .from('addresses')
        .insert({...address.toMap(), 'user_id': user.id})
        .select()
        .single();
    return Address.fromMap(row);
  }

  Future<void> updateAddress(Address address) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('Not logged in');

    if (address.isDefault) {
      await _clearDefaults(user.id);
    }

    await _client.from('addresses').update(address.toMap()).eq('id', address.id);
  }

  Future<void> deleteAddress(String id) async {
    await _client.from('addresses').delete().eq('id', id);
  }

  Future<void> _clearDefaults(String userId) async {
    await _client.from('addresses').update({'is_default': false}).eq('user_id', userId);
  }
}
