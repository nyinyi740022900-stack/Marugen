import 'order_parcel.dart';
import 'order_cancellation_request.dart';

enum OrderStatus {
  pending,
  paid,
  packing,
  shipped,
  delivered,
  cancelled,
  refunded,
}

OrderStatus orderStatusFromString(String value) {
  return OrderStatus.values.firstWhere(
    (e) => e.name == value,
    orElse: () => OrderStatus.pending,
  );
}

/// Statuses an order in [current] may move to next — a forward-only
/// pipeline, not a freeform set. Payment confirmation is server-owned;
/// the database guards in 0030/0055 also reject invalid client writes.
/// `paid`/`packing` can both jump
/// straight to `delivered` (skipping `shipped`) because live fish orders
/// are hand-delivered by the shop with no courier "shipped" step — see
/// admin_delivery_screen.dart's "Delivered by shop" action.
Set<OrderStatus> validNextStatuses(OrderStatus current) {
  switch (current) {
    case OrderStatus.pending:
      return {OrderStatus.cancelled};
    case OrderStatus.paid:
      return {
        OrderStatus.packing,
        OrderStatus.shipped,
        OrderStatus.delivered,
        OrderStatus.refunded,
      };
    case OrderStatus.packing:
      return {OrderStatus.shipped, OrderStatus.delivered, OrderStatus.refunded};
    case OrderStatus.shipped:
      return {OrderStatus.delivered, OrderStatus.refunded};
    case OrderStatus.delivered:
      return {OrderStatus.refunded};
    case OrderStatus.cancelled:
    case OrderStatus.refunded:
      return {};
  }
}

String orderStatusLabel(OrderStatus s) {
  switch (s) {
    case OrderStatus.pending:
      return 'Pending';
    case OrderStatus.paid:
      return 'Paid';
    case OrderStatus.packing:
      return 'Packing';
    case OrderStatus.shipped:
      return 'Shipped';
    case OrderStatus.delivered:
      return 'Delivered';
    case OrderStatus.cancelled:
      return 'Cancelled';
    case OrderStatus.refunded:
      return 'Refunded';
  }
}

class OrderItem {
  final String id;
  final String productId;
  final String productName;
  final String? productCategory;
  final int quantity;
  final double unitPrice;
  final String? variantLabel;
  final String? sizeLabel;

  /// Snapshot of the product's cover photo at order time (see
  /// migration 0023) — survives the product itself being edited/deleted.
  final String? imageUrl;

  const OrderItem({
    this.id = '',
    required this.productId,
    required this.productName,
    this.productCategory,
    required this.quantity,
    required this.unitPrice,
    this.variantLabel,
    this.sizeLabel,
    this.imageUrl,
  });

  double get subtotal => quantity * unitPrice;

  /// Weight · size caption for receipts and order detail.
  String? get optionLabel {
    final parts = <String>[
      if (variantLabel != null && variantLabel!.isNotEmpty) variantLabel!,
      if (sizeLabel != null && sizeLabel!.isNotEmpty) sizeLabel!,
    ];
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      id: map['id'] as String? ?? '',
      productId: map['product_id'] as String? ?? '',
      productName: map['product_name'] as String? ?? '',
      productCategory: map['product_category'] as String?,
      quantity: map['quantity'] as int? ?? 1,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
      variantLabel: map['variant_label'] as String?,
      sizeLabel: map['size_label'] as String?,
      imageUrl: map['image_url'] as String?,
    );
  }
}

class Order {
  final String id;
  final String? userId;

  /// Human-readable, date-based order number (e.g. "20092026-0001") —
  /// assigned server-side by a trigger on insert (see migration 0024).
  /// Null only for pre-migration rows that somehow missed the backfill;
  /// callers should prefer [displayNumber] over reading this directly.
  final String? orderNumber;
  final OrderStatus status;
  final double total;
  final DateTime createdAt;
  final List<OrderItem> items;
  final List<OrderParcel> parcels;
  final String? qxpressTrackingNo;
  final String? stripePaymentIntentId;
  final Map<String, dynamic>? shippingAddress;
  final String? customerRemarks;
  final String? promoCode;
  final double? discountAmount;

  /// Coarse status from 17TRACK (e.g. InTransit/OutForDelivery/Delivered),
  /// null until [qxpressTrackingNo] has been registered with `track-register`.
  final String? trackingStatus;

  /// Latest human-readable tracking event text from the carrier.
  final String? trackingStatusDetail;
  final DateTime? trackingUpdatedAt;
  final bool trackingRegistered;

  /// EasyParcel's numeric shipment status code (see migration 0043) — null
  /// for 17TRACK-tracked orders. Lets the UI pick a status-appropriate icon
  /// without parsing free-text courier status strings.
  final int? trackingStatusCode;

  /// Highest verified physical milestone, retained through carrier holds.
  final int trackingProgress;

  /// Which system booked/owns this shipment's tracking — 'easyparcel' or
  /// 'seventeentrack' (manual entry), null if not shipped yet. Only
  /// changes which admin actions are offered (e.g. hides "Enter Tracking
  /// Number" once EasyParcel owns it); the tracking display itself reads
  /// the same qxpressTrackingNo/trackingStatus* fields regardless.
  final String? trackingProvider;
  final String? easyparcelAwbUrl;
  final String? fulfillmentMethod;
  final String? easyparcelBookingState;
  final String? easyparcelShipmentId;
  final DateTime? easyparcelBookingStartedAt;
  final OrderCancellationRequest? cancellationRequest;

  bool get hasCancellationHold =>
      cancellationRequest?.holdsFulfillment ?? false;

  bool get canRequestCancellation =>
      cancellationRequest == null &&
      const {OrderStatus.paid, OrderStatus.packing}.contains(status) &&
      stripePaymentIntentId?.isNotEmpty == true &&
      refundStatus == null &&
      !trackingRegistered &&
      trackingProgress == 0 &&
      trackingProvider == null &&
      (qxpressTrackingNo?.trim().isEmpty ?? true) &&
      (easyparcelShipmentId?.trim().isEmpty ?? true) &&
      easyparcelBookingState == null &&
      easyparcelBookingStartedAt == null &&
      parcels.every(
        (p) =>
            p.state == 'draft' &&
            (p.trackingNumber?.isEmpty ?? true) &&
            (p.shipmentNumber?.isEmpty ?? true),
      );
  final List<String> statusHistory;
  final String? refundStatus;
  final double refundAmount;
  final double refundPendingAmount;

  String? get refundStatusLabel => switch (refundStatus) {
    'pending' => 'Refund pending',
    'requires_action' => 'Refund needs attention — contact shop',
    'failed' => 'Refund failed — contact shop',
    'canceled' => 'Refund cancelled',
    'partially_refunded' => 'Partially refunded',
    'succeeded' => 'Refunded',
    _ => null,
  };

  bool get canRequestRefund =>
      refundStatus == null &&
      const {
        OrderStatus.paid,
        OrderStatus.packing,
        OrderStatus.shipped,
        OrderStatus.delivered,
      }.contains(status);

  bool get needsRefundReview =>
      status == OrderStatus.refunded &&
      refundStatus != null &&
      refundStatus != 'succeeded';

  double get netPaidAmount =>
      (const {
            OrderStatus.paid,
            OrderStatus.packing,
            OrderStatus.shipped,
            OrderStatus.delivered,
          }.contains(status) ||
          needsRefundReview)
      ? (total - refundAmount).clamp(0, total).toDouble()
      : 0;
  final String? shippingQuoteId;
  final String? shippingCurrency;
  final int? totalShippingCents;
  final int? buyerShippingCents;
  final int? sellerShippingCents;
  final String? shippingCarrierName;
  final String? shippingCostPolicy;
  final Map<String, dynamic>? shippingParcel;

  bool get hasParcelPlan => parcels.isNotEmpty;
  bool get canSplitIntoParcels =>
      !hasCancellationHold &&
      canUseCourier &&
      !hasParcelPlan &&
      const {OrderStatus.paid, OrderStatus.packing}.contains(status) &&
      !trackingRegistered &&
      trackingProvider == null &&
      (qxpressTrackingNo?.isEmpty ?? true) &&
      (easyparcelShipmentId?.isEmpty ?? true) &&
      items.isNotEmpty &&
      items.every((i) => i.id.isNotEmpty) &&
      items.fold<int>(0, (sum, i) => sum + i.quantity) >= 2;
  bool get isShopDelivery => fulfillmentMethod == 'shop_delivery';
  bool get canUseCourier =>
      fulfillmentMethod == 'courier' &&
      !items.any(
        (item) =>
            item.productCategory == 'koi' || item.productCategory == 'arowana',
      );
  bool get needsDeliveryReview => !isShopDelivery && !canUseCourier;
  bool get hasSampleTracking =>
      trackingProvider == 'easyparcel' &&
      ((qxpressTrackingNo?.trim().toUpperCase().startsWith('EPSAMPLE') ??
              false) ||
          (easyparcelShipmentId?.trim().toUpperCase().startsWith('EPSAMPLE') ??
              false));
  bool get needsBookingAttention =>
      (hasParcelPlan && parcels.any((p) => p.needsAttention)) ||
      trackingProvider == 'easyparcel' &&
          (hasSampleTracking ||
              easyparcelBookingState == 'needs_attention' ||
              (trackingRegistered && (qxpressTrackingNo?.isEmpty ?? true)));
  bool get awaitingCourierPickup =>
      trackingProvider == 'easyparcel' &&
      !needsBookingAttention &&
      (trackingRegistered || qxpressTrackingNo != null) &&
      trackingProgress == 0 &&
      !const {3, 4, 5, 11}.contains(trackingStatusCode) &&
      status != OrderStatus.delivered &&
      status != OrderStatus.cancelled &&
      status != OrderStatus.refunded;
  String get deliveryMethodLabel => isShopDelivery
      ? 'Shop delivery'
      : canUseCourier
      ? 'Courier delivery'
      : 'Delivery method needs review';
  String get fulfillmentStatusLabel {
    if (needsRefundReview) return refundStatusLabel!;
    if (status == OrderStatus.delivered ||
        status == OrderStatus.cancelled ||
        status == OrderStatus.refunded) {
      return orderStatusLabel(status);
    }
    if (hasCancellationHold) {
      return cancellationRequest?.status == 'requested'
          ? 'Cancellation requested'
          : refundStatusLabel ??
                'Cancellation approved · Refund being arranged';
    }
    if (hasParcelPlan) {
      final delivered = parcels.where((p) => p.delivered).length;
      final collected = parcels.where((p) => p.collected).length;
      if (delivered > 0) {
        return '$delivered of ${parcels.length} parcels delivered';
      }
      if (parcels.any((p) => p.needsAttention)) return 'Parcel needs attention';
      if (collected > 0) {
        return '$collected of ${parcels.length} parcels collected';
      }
      return '${parcels.length} parcels · Preparing delivery';
    }
    if (needsBookingAttention) return 'Needs attention';
    if (trackingProvider == 'easyparcel' &&
        const {0, 6, 8}.contains(trackingStatusCode)) {
      return 'Delivery issue — contact shop';
    }
    if (awaitingCourierPickup) return 'Awaiting courier pickup';
    if (isShopDelivery && status == OrderStatus.shipped) {
      return 'Out for delivery';
    }
    return orderStatusLabel(status);
  }

  /// What every screen should actually show — the assigned order number,
  /// or a shortened id fallback for the rare pre-migration row without one.
  String get displayNumber => orderNumber ?? id.substring(0, 8).toUpperCase();

  const Order({
    required this.id,
    required this.userId,
    this.orderNumber,
    required this.status,
    required this.total,
    required this.createdAt,
    this.items = const [],
    this.parcels = const [],
    this.qxpressTrackingNo,
    this.stripePaymentIntentId,
    this.shippingAddress,
    this.customerRemarks,
    this.promoCode,
    this.discountAmount,
    this.trackingStatus,
    this.trackingStatusDetail,
    this.trackingUpdatedAt,
    this.trackingRegistered = false,
    this.trackingProvider,
    this.easyparcelAwbUrl,
    this.fulfillmentMethod,
    this.easyparcelBookingState,
    this.easyparcelShipmentId,
    this.easyparcelBookingStartedAt,
    this.cancellationRequest,
    this.statusHistory = const [],
    this.refundStatus,
    this.refundAmount = 0,
    this.refundPendingAmount = 0,
    this.shippingQuoteId,
    this.shippingCurrency,
    this.totalShippingCents,
    this.buyerShippingCents,
    this.sellerShippingCents,
    this.shippingCarrierName,
    this.shippingCostPolicy,
    this.shippingParcel,
    this.trackingStatusCode,
    this.trackingProgress = 0,
  });

  factory Order.fromMap(Map<String, dynamic> map) {
    return Order(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      orderNumber: map['order_number'] as String?,
      status: orderStatusFromString(map['status'] as String? ?? 'pending'),
      refundStatus: map['refund_status'] as String?,
      refundAmount: (map['refund_amount'] as num?)?.toDouble() ?? 0,
      refundPendingAmount:
          (map['refund_pending_amount'] as num?)?.toDouble() ?? 0,
      total: (map['total'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      items:
          (map['items'] as List?)
              ?.map((e) => OrderItem.fromMap(e as Map<String, dynamic>))
              .toList() ??
          const [],
      parcels:
          ((map['parcels'] as List?)
                    ?.whereType<Map>()
                    .map((p) => OrderParcel.fromMap(p.cast<String, dynamic>()))
                    .toList() ??
                <OrderParcel>[])
            ..sort((a, b) => a.number.compareTo(b.number)),
      qxpressTrackingNo: map['qxpress_tracking_no'] as String?,
      stripePaymentIntentId: map['stripe_payment_intent_id'] as String?,
      shippingAddress: (map['shipping_address'] as Map?)
          ?.cast<String, dynamic>(),
      customerRemarks: map['customer_remarks'] as String?,
      promoCode: map['promo_code'] as String?,
      discountAmount: (map['discount_amount'] as num?)?.toDouble(),
      trackingStatus: map['tracking_status'] as String?,
      trackingStatusDetail:
          ((map['tracking_status_detail'] as String?)?.startsWith(
                'booking_issue:',
              ) ??
              false)
          ? 'The shop is checking a shipping booking issue.'
          : map['tracking_status_detail'] as String?,
      trackingUpdatedAt: map['tracking_updated_at'] != null
          ? DateTime.tryParse(map['tracking_updated_at'] as String)
          : null,
      trackingRegistered: map['tracking_registered'] as bool? ?? false,
      trackingProvider: map['tracking_provider'] as String?,
      easyparcelAwbUrl: map['easyparcel_awb_url'] as String?,
      fulfillmentMethod: map['fulfillment_method'] as String?,
      shippingQuoteId: map['shipping_quote_id'] as String?,
      shippingCurrency: map['shipping_currency'] as String?,
      totalShippingCents: (map['total_shipping_cents'] as num?)?.toInt(),
      buyerShippingCents: (map['buyer_shipping_cents'] as num?)?.toInt(),
      sellerShippingCents: (map['seller_shipping_cents'] as num?)?.toInt(),
      shippingCarrierName: map['shipping_carrier_name'] as String?,
      shippingCostPolicy: map['shipping_cost_policy'] as String?,
      shippingParcel: (map['shipping_parcel'] as Map?)?.cast<String, dynamic>(),
      easyparcelBookingState: map['easyparcel_booking_state'] as String?,
      easyparcelShipmentId: map['easyparcel_shipment_id'] as String?,
      easyparcelBookingStartedAt: DateTime.tryParse(
        map['easyparcel_booking_started_at']?.toString() ?? '',
      ),
      cancellationRequest: OrderCancellationRequest.fromRelation(
        map['order_cancellation_requests'],
      ),
      statusHistory:
          (map['status_history'] as List?)
              ?.whereType<Map>()
              .map((row) => row['to_status'])
              .whereType<String>()
              .toList() ??
          const [],
      trackingStatusCode: map['tracking_status_code'] as int?,
      trackingProgress: (map['tracking_progress'] as num?)?.toInt() ?? 0,
    );
  }
}
