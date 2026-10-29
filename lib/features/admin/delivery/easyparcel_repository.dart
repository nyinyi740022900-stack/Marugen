import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

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

  /// Server-generates and stores a single-use OAuth `state` value for the
  /// connect flow (see 0047_easyparcel_oauth_state.sql / easyparcel-oauth-
  /// callback) — the caller embeds this in the `oauth/login` URL it opens.
  /// Doing this server-side (rather than generating `state` locally and
  /// never persisting it, as this used to) is what lets the callback
  /// actually verify the request came from a real admin session instead of
  /// accepting any code for any EasyParcel account.
  Future<String> startOAuth() async {
    final res = await _client.functions.invoke('easyparcel-oauth-start');
    if (res.status >= 400) {
      throw Exception('Could not start EasyParcel connection');
    }
    return (res.data as Map)['state'] as String;
  }

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
  Future<List<EasyParcelRate>> getRates(
    String orderId, {
    required ParcelDetails parcel,
  }) async {
    final res = await _client.functions.invoke(
      'easyparcel-get-rates',
      body: {'order_id': orderId, 'parcel': parcel.toJson()},
    );
    if (res.status >= 400) {
      final data = res.data;
      final message = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'Could not fetch shipping rates';
      throw Exception(message);
    }
    final rawRates = (res.data as Map)['rates'];
    final list = rawRates is List
        ? rawRates
        : (rawRates as Map)['result'] as List? ?? [];
    return list
        .map((e) => EasyParcelRate.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Books the shipment with the courier/service the admin picked from
  /// [getRates]. On success the order's tracking number is set server-side
  /// (same columns 17TRACK uses). The order awaits pickup until collection is confirmed.
  Future<void> bookShipment({
    required String orderId,
    required String serviceId,
    required ParcelDetails parcel,
    String? courierId,
  }) async {
    final res = await _client.functions.invoke(
      'easyparcel-book-shipment',
      body: {
        'order_id': orderId,
        'service_id': serviceId,
        'parcel': parcel.toJson(),
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

  /// Attaches an existing booking's verified AWB; never creates another shipment.
  Future<void> reconcileShipment(String orderId, String trackingNumber) async {
    final res = await _client.functions.invoke(
      'easyparcel-reconcile-shipment',
      body: {
        'order_id': orderId,
        'tracking_number': trackingNumber,
        'confirmed_existing_shipment': true,
      },
    );
    if (res.status >= 400) {
      final data = res.data;
      throw Exception(
        data is Map && data['error'] != null
            ? data['error'].toString()
            : 'Could not recover the existing shipment',
      );
    }
  }

  /// Parcel planning/booking is owner-only; the backend owns all prices and claims.
  Future<Map<String, dynamic>> parcelAction(
    String action,
    String orderId, {
    Map<String, dynamic> data = const {},
  }) async {
    final dynamic response;
    try {
      response = await _client.functions
          .invoke(
            'order-parcels',
            body: {...data, 'action': action, 'order_id': orderId},
          )
          .timeout(Duration(seconds: action == 'book' ? 90 : 45));
    } on FunctionException catch (error) {
      final details = error.details;
      throw StateError(
        details is Map && details['error'] is String
            ? details['error'] as String
            : 'Could not update parcels. Refresh and try again.',
      );
    }
    if (response.status >= 400 || response.data is! Map) {
      final body = response.data;
      throw StateError(
        body is Map && body['error'] is String
            ? body['error'] as String
            : 'Could not update parcels. Refresh and try again.',
      );
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Read-only owner check: never pays, submits or retries a shipment.
  Future<Map<String, dynamic>> pickupDiagnostics(String orderId) async {
    final res = await _client.functions.invoke(
      'easyparcel-pickup-diagnostics',
      body: {'order_id': orderId},
    );
    if (res.status >= 400 || res.data is! Map) {
      throw StateError('Could not verify pickup. Check EasyParcel.');
    }
    return Map<String, dynamic>.from(res.data as Map);
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
  final bool bookingAvailable;
  final String? bookingMessage;

  const EasyParcelRate({
    required this.serviceId,
    this.courierId,
    required this.courierName,
    required this.price,
    this.currency,
    this.bookingAvailable = true,
    this.bookingMessage,
  });

  factory EasyParcelRate.fromMap(Map<String, dynamic> map) {
    final price = double.tryParse((map['price'] ?? '').toString());
    if (map['currency'] != 'SGD' ||
        price == null ||
        !price.isFinite ||
        price < 0 ||
        (map['courier_name'] is! String ||
            (map['courier_name'] as String).trim().isEmpty)) {
      throw const FormatException(
        'Could not verify the SGD courier rate. Refresh shipping rates.',
      );
    }
    return EasyParcelRate(
      serviceId: (map['service_id'] ?? '').toString(),
      courierId: map['courier_id']?.toString(),
      courierName: (map['courier_name'] ?? 'Courier').toString(),
      price: price,
      currency: map['currency']?.toString(),
      bookingAvailable: map['booking_available'] == true,
      bookingMessage: map['booking_message']?.toString(),
    );
  }
}

/// The same measurements and pickup date are used for both quoting and booking.
class ParcelDetails {
  final double weightKg;
  final double lengthCm;
  final double widthCm;
  final double heightCm;
  final String collectionDate;
  const ParcelDetails({
    required this.weightKg,
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
    required this.collectionDate,
  });
  Map<String, dynamic> toJson() => {
    'weight_kg': weightKg,
    'length_cm': lengthCm,
    'width_cm': widthCm,
    'height_cm': heightCm,
    'collection_date': collectionDate,
  };
}
