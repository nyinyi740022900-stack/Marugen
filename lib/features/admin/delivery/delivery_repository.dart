import '../../../core/supabase/supabase_client.dart';

/// Talks to the `qxpress-shipment` Supabase Edge Function, which holds the
/// Qxpress API key server-side and creates a shipment + tracking number for
/// a paid order. See `supabase/functions/qxpress-shipment/index.ts`.
///
/// NOTE: confirm with Qxpress whether live fish (koi/arowana) are an
/// accepted parcel type before wiring this up for those categories — until
/// then, keep "Store Pickup" as the delivery option for live fish orders.
class DeliveryRepository {
  final _client = SupabaseService.client;

  Future<Map<String, dynamic>> createShipment({
    required String orderId,
    required Map<String, dynamic> address,
  }) async {
    final res = await _client.functions.invoke(
      'qxpress-shipment',
      body: {'order_id': orderId, 'address': address},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }
}
