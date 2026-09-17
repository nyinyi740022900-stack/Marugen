import '../../../core/supabase/supabase_client.dart';

/// Talks to the `qxpress-shipment` and `track-*` Supabase Edge Functions.
///
/// `qxpress-shipment` holds the Qxpress API key server-side and creates a
/// shipment + tracking number for a paid order (see
/// `supabase/functions/qxpress-shipment/index.ts`).
///
/// `track-register` / `track-status` hold the 17TRACK API key server-side
/// and register/refresh **any** courier's tracking number (Qxpress or a
/// manually-entered one from another carrier) so the app shows live status
/// instead of a static tracking number — see
/// `supabase/functions/track-register/index.ts` and `track-status/index.ts`.
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

  /// Registers a tracking number (from Qxpress or typed in manually for
  /// any other courier) with 17TRACK so status updates start flowing in.
  /// Admin-only — enforced server-side by the Edge Function.
  Future<void> registerTracking({
    required String orderId,
    required String trackingNumber,
    int? carrierCode,
  }) async {
    final res = await _client.functions.invoke(
      'track-register',
      body: {
        'order_id': orderId,
        'tracking_number': trackingNumber,
        'carrier_code': ?carrierCode,
      },
    );
    if (res.status >= 400) {
      final data = res.data;
      final message =
          data is Map && data['error'] != null ? data['error'].toString() : 'Tracking registration failed';
      throw Exception(message);
    }
  }

  /// Pulls the latest status for an order's tracking number on demand
  /// (rather than waiting for the next webhook push). Works for the order's
  /// own customer or any admin.
  Future<void> refreshTrackingStatus(String orderId) async {
    final res = await _client.functions.invoke('track-status', body: {'order_id': orderId});
    if (res.status >= 400) {
      final data = res.data;
      final message =
          data is Map && data['error'] != null ? data['error'].toString() : 'Could not refresh tracking';
      throw Exception(message);
    }
  }
}
