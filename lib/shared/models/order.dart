enum OrderStatus { pending, paid, packing, shipped, delivered, cancelled, refunded }

OrderStatus orderStatusFromString(String value) {
  return OrderStatus.values.firstWhere(
    (e) => e.name == value,
    orElse: () => OrderStatus.pending,
  );
}

/// Statuses an order in [current] may move to next — a forward-only
/// pipeline, not a freeform set. Mirrored exactly by the DB trigger in
/// `0030_order_status_forward_only.sql` so the same rule holds even if a
/// client bypasses this UI-level check. `paid`/`packing` can both jump
/// straight to `delivered` (skipping `shipped`) because live fish orders
/// are hand-delivered by the shop with no courier "shipped" step — see
/// admin_delivery_screen.dart's "Delivered by shop" action.
Set<OrderStatus> validNextStatuses(OrderStatus current) {
  switch (current) {
    case OrderStatus.pending:
      return {OrderStatus.paid, OrderStatus.cancelled};
    case OrderStatus.paid:
      return {
        OrderStatus.packing,
        OrderStatus.shipped,
        OrderStatus.delivered,
        OrderStatus.cancelled,
        OrderStatus.refunded,
      };
    case OrderStatus.packing:
      return {
        OrderStatus.shipped,
        OrderStatus.delivered,
        OrderStatus.cancelled,
        OrderStatus.refunded,
      };
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
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final String? variantLabel;
  final String? sizeLabel;

  /// Snapshot of the product's cover photo at order time (see
  /// migration 0023) — survives the product itself being edited/deleted.
  final String? imageUrl;

  const OrderItem({
    required this.productId,
    required this.productName,
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
      productId: map['product_id'] as String? ?? '',
      productName: map['product_name'] as String? ?? '',
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
  final String userId;

  /// Human-readable, date-based order number (e.g. "20092026-0001") —
  /// assigned server-side by a trigger on insert (see migration 0024).
  /// Null only for pre-migration rows that somehow missed the backfill;
  /// callers should prefer [displayNumber] over reading this directly.
  final String? orderNumber;
  final OrderStatus status;
  final double total;
  final DateTime createdAt;
  final List<OrderItem> items;
  final String? qxpressTrackingNo;
  final String? stripePaymentIntentId;
  final Map<String, dynamic>? shippingAddress;
  final String? promoCode;
  final double? discountAmount;

  /// Coarse status from 17TRACK (e.g. InTransit/OutForDelivery/Delivered),
  /// null until [qxpressTrackingNo] has been registered with `track-register`.
  final String? trackingStatus;

  /// Latest human-readable tracking event text from the carrier.
  final String? trackingStatusDetail;
  final DateTime? trackingUpdatedAt;
  final bool trackingRegistered;

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
    this.qxpressTrackingNo,
    this.stripePaymentIntentId,
    this.shippingAddress,
    this.promoCode,
    this.discountAmount,
    this.trackingStatus,
    this.trackingStatusDetail,
    this.trackingUpdatedAt,
    this.trackingRegistered = false,
  });

  factory Order.fromMap(Map<String, dynamic> map) {
    return Order(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      orderNumber: map['order_number'] as String?,
      status: orderStatusFromString(map['status'] as String? ?? 'pending'),
      total: (map['total'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      items: (map['items'] as List?)
              ?.map((e) => OrderItem.fromMap(e as Map<String, dynamic>))
              .toList() ??
          const [],
      qxpressTrackingNo: map['qxpress_tracking_no'] as String?,
      stripePaymentIntentId: map['stripe_payment_intent_id'] as String?,
      shippingAddress: (map['shipping_address'] as Map?)?.cast<String, dynamic>(),
      promoCode: map['promo_code'] as String?,
      discountAmount: (map['discount_amount'] as num?)?.toDouble(),
      trackingStatus: map['tracking_status'] as String?,
      trackingStatusDetail: map['tracking_status_detail'] as String?,
      trackingUpdatedAt: map['tracking_updated_at'] != null
          ? DateTime.tryParse(map['tracking_updated_at'] as String)
          : null,
      trackingRegistered: map['tracking_registered'] as bool? ?? false,
    );
  }
}
