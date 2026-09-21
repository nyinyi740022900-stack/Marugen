import '../../../core/supabase/supabase_client.dart';

/// Talks to the `track-*` Supabase Edge Functions.
///
/// `track-register` / `track-status` hold the 17TRACK API key server-side
/// and register/refresh any courier's tracking number (admin types it in
/// after shipping with whichever courier they used) so the app shows live
/// status instead of a static tracking number — see
/// `supabase/functions/track-register/index.ts` and `track-status/index.ts`.
///
/// NOTE: live fish (koi/arowana) are never handed to a courier/tracking
/// API — the shop hand-delivers these orders itself. In the admin Delivery
/// pane, use the "Delivered by shop" action for those orders instead; it
/// advances the order's status without a courier tracking number.
class DeliveryRepository {
  final _client = SupabaseService.client;

  /// Registers a tracking number (typed in by admin after shipping with
  /// any courier) with 17TRACK so status updates start flowing in.
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
      final message = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'Tracking registration failed';
      throw Exception(message);
    }
  }

  /// Pulls the latest status for an order's tracking number on demand
  /// (rather than waiting for the next webhook push). Works for the order's
  /// own customer or any admin.
  Future<void> refreshTrackingStatus(String orderId) async {
    final res = await _client.functions.invoke(
      'track-status',
      body: {'order_id': orderId},
    );
    if (res.status >= 400) {
      final data = res.data;
      final message = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'Could not refresh tracking';
      throw Exception(message);
    }
  }
}
