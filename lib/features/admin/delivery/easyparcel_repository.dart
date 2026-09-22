import '../../../core/supabase/supabase_client.dart';

/// Talks to the `easyparcel-*` Supabase Edge Functions — the automated
/// shipment-booking path that replaces manually typing a tracking number
/// (see [DeliveryRepository] for the manual/17TRACK fallback, which stays
/// available for orders shipped outside EasyParcel).
///
/// The OAuth tokens for the connected EasyParcel account never reach this
/// app — only a connected/not-connected boolean via [connectionStatus].
/// The actual sender/receiver/rate-quote payload building happens
/// server-side in the Edge Functions.
class EasyParcelRepository {
  final _client = SupabaseService.client;

  Future<EasyParcelStatus> connectionStatus() async {
    final res = await _client.functions.invoke('easyparcel-status');
    if (res.status >= 400) {
      throw Exception('Could not check EasyParcel connection status');
    }
    final data = res.data as Map;
    return EasyParcelStatus(
      connected: data['connected'] as bool? ?? false,
      connectedAt: data['connected_at'] != null
          ? DateTime.tryParse(data['connected_at'].toString())
          : null,
    );
  }

  /// Rate quotes for an order's shipping address, using the shop's sender
  /// address + default parcel weight from Settings.
  Future<List<EasyParcelRate>> getRates(String orderId) async {
    final res = await _client.functions.invoke(
      'easyparcel-get-rates',
      body: {'order_id': orderId},
    );
    if (res.status >= 400) {
      final data = res.data;
      final message = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'Could not fetch shipping rates';
      throw Exception(message);
    }
    final rawRates = (res.data as Map)['rates'];
    final list = rawRates is List ? rawRates : (rawRates as Map)['result'] as List? ?? [];
    return list
        .map((e) => EasyParcelRate.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Books the shipment with the courier/service the admin picked from
  /// [getRates]. On success the order's tracking number is set server-side
  /// (same columns 17TRACK uses) and its status advances to `shipped`.
  Future<void> bookShipment({
    required String orderId,
    required String serviceId,
    String? courierId,
  }) async {
    final res = await _client.functions.invoke(
      'easyparcel-book-shipment',
      body: {
        'order_id': orderId,
        'service_id': serviceId,
        'courier_id': ?courierId,
      },
    );
    if (res.status >= 400) {
      final data = res.data;
      final message = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'Could not book the shipment';
      throw Exception(message);
    }
  }

  /// Pulls the shipment's current status straight from EasyParcel (pickup,
  /// in transit, delivered, returned, ...) and writes it onto the order —
  /// the EasyParcel equivalent of [DeliveryRepository.refreshTrackingStatus]
  /// for 17TRACK. Needed because easyparcel-webhook's push can't be relied
  /// on alone (unverified signature — see its file header) and doesn't fire
  /// at all in the EasyParcel sandbox.
  Future<void> refreshStatus(String orderId) async {
    final res = await _client.functions.invoke(
      'easyparcel-refresh-status',
      body: {'order_id': orderId},
    );
    if (res.status >= 400) {
      final data = res.data;
      final message = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'Could not refresh tracking status';
      throw Exception(message);
    }
  }
}

class EasyParcelStatus {
  final bool connected;
  final DateTime? connectedAt;
  const EasyParcelStatus({required this.connected, this.connectedAt});
}

/// One courier/service option returned by a rate quote, with the price
/// shown so the admin picks knowingly rather than a black box.
class EasyParcelRate {
  final String serviceId;
  final String? courierId;
  final String courierName;
  final double price;
  final String? currency;

  const EasyParcelRate({
    required this.serviceId,
    this.courierId,
    required this.courierName,
    required this.price,
    this.currency,
  });

  factory EasyParcelRate.fromMap(Map<String, dynamic> map) {
    return EasyParcelRate(
      serviceId: (map['service_id'] ?? '').toString(),
      courierId: map['courier_id']?.toString(),
      courierName: (map['courier_name'] ?? 'Courier').toString(),
      price: double.tryParse((map['price'] ?? 0).toString()) ?? 0,
      currency: map['currency']?.toString(),
    );
  }
}
