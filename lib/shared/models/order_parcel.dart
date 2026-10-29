/// Actual packed box beneath an order; customer payment remains on the order.
class OrderParcel {
  final String id;
  final int number;
  final String state;
  final List<Map<String, dynamic>> items;
  final double weightKg, lengthCm, widthCm, heightCm;
  final String collectionDate;
  final String? carrierName,
      trackingNumber,
      shipmentNumber,
      awbUrl,
      trackingStatus,
      diagnosticCode,
      /// EasyParcel's short rejection reason. Shown to staff only.
      bookingError;
  final int? quotedTotalCents;
  const OrderParcel({
    required this.id,
    required this.number,
    required this.state,
    this.items = const [],
    this.weightKg = 0,
    this.lengthCm = 0,
    this.widthCm = 0,
    this.heightCm = 0,
    this.collectionDate = '',
    this.carrierName,
    this.trackingNumber,
    this.shipmentNumber,
    this.awbUrl,
    this.trackingStatus,
    this.diagnosticCode,
    this.bookingError,
    this.quotedTotalCents,
  });
  bool get isSample =>
      (trackingNumber?.trim().toUpperCase().startsWith('EPSAMPLE') ?? false) ||
      (shipmentNumber?.trim().toUpperCase().startsWith('EPSAMPLE') ?? false);
  bool get delivered => state == 'delivered' && !isSample;
  bool get collected =>
      !isSample &&
      const {'collected', 'in_transit', 'delivered'}.contains(state);
  bool get needsAttention =>
      isSample ||
      const {
        'needs_attention',
        'payment_required',
        'cancelled',
        'returned',
        'on_hold',
      }.contains(state);

  /// EasyParcel never identified this box, so after staff confirm nothing
  /// exists there the plan can go back to draft and be booked again.
  bool get canRetryBooking =>
      state == 'needs_attention' &&
      (trackingNumber?.isEmpty ?? true) &&
      (shipmentNumber?.isEmpty ?? true) &&
      (awbUrl?.isEmpty ?? true) &&
      const {
        'submission_uncertain',
        'not_attempted_after_failure',
      }.contains(diagnosticCode);
  bool get canPrintLabel =>
      !isSample &&
      const {
        'booked',
        'collected',
        'in_transit',
        'delivered',
      }.contains(state) &&
      Uri.tryParse(awbUrl ?? '')?.scheme == 'https';
  String get statusLabel => isSample
      ? 'Live booking needs checking'
      : switch (state) {
          'draft' => 'Ready for a quote',
          'booking' => 'Booking in progress',
          'booked' => 'Awaiting pickup',
          'collected' => 'Collected',
          'in_transit' => 'On the way',
          'delivered' => 'Delivered',
          'payment_required' => 'Payment required in EasyParcel',
          'cancelled' => 'Cancelled',
          'returned' => 'Returned',
          'on_hold' => 'On hold',
          'needs_attention'
              when diagnosticCode == 'not_attempted_after_failure' =>
            'Not booked — an earlier parcel failed',
          'needs_attention' when diagnosticCode == 'submission_uncertain' =>
            'Booking not confirmed by EasyParcel',
          _ => 'Check booking in EasyParcel',
        };
  factory OrderParcel.fromMap(Map<String, dynamic> m) => OrderParcel(
    id: m['id'] as String? ?? '',
    number: (m['parcel_number'] as num?)?.toInt() ?? 1,
    state: m['state'] as String? ?? 'needs_attention',
    items:
        (m['items'] as List?)
            ?.whereType<Map>()
            .map((v) => v.cast<String, dynamic>())
            .toList() ??
        const [],
    weightKg: (m['weight_kg'] as num?)?.toDouble() ?? 0,
    lengthCm: (m['length_cm'] as num?)?.toDouble() ?? 0,
    widthCm: (m['width_cm'] as num?)?.toDouble() ?? 0,
    heightCm: (m['height_cm'] as num?)?.toDouble() ?? 0,
    collectionDate: m['collection_date'] as String? ?? '',
    carrierName: m['carrier_name'] as String?,
    trackingNumber: m['tracking_number'] as String?,
    shipmentNumber: m['shipment_number'] as String?,
    awbUrl: m['awb_url'] as String?,
    trackingStatus: m['tracking_status'] as String?,
    diagnosticCode: m['diagnostic_code'] as String?,
    bookingError: m['booking_error'] as String?,
    quotedTotalCents: (m['quoted_total_cents'] as num?)?.toInt(),
  );
}
