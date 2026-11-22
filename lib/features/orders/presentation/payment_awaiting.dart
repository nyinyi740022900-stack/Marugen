import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/models/order.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../cart/domain/cart_item.dart';
import '../../cart/presentation/cart_providers.dart';
import '../utils/payment_confirmation.dart';
import 'orders_providers.dart';

/// One cart line a payment bought, by id only — enough to take it out of
/// the cart after a restart, when the full [CartItem] is no longer in memory.
class PurchasedLine {
  final String productId;
  final String? variantId;
  final String? size;

  /// How many units the payment bought. Null means the whole line: a
  /// record saved before quantities were kept.
  final int? quantity;

  const PurchasedLine({
    required this.productId,
    this.variantId,
    this.size,
    this.quantity,
  });

  factory PurchasedLine.fromCartItem(CartItem item) => PurchasedLine(
    productId: item.product.id,
    variantId: item.selectedVariant?.id,
    size: item.selectedSize,
    quantity: item.quantity,
  );

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'variant_id': variantId,
    'size_label': size,
    'quantity': ?quantity,
  };

  static PurchasedLine? fromJson(Object? json) {
    if (json is! Map) return null;
    final productId = json['product_id'];
    if (productId is! String || productId.isEmpty) return null;
    final quantity = json['quantity'];
    return PurchasedLine(
      productId: productId,
      variantId: json['variant_id'] as String?,
      size: json['size_label'] as String?,
      quantity: quantity is int && quantity > 0 ? quantity : null,
    );
  }
}

/// "The payment sheet just reported success for this order, but the server
/// has not recorded it yet" — set by checkout / Complete payment, read by the
/// order screen, which shows a confirming state and keeps re-checking (see
/// `_PaymentConfirmationPoller`). It is a display hint only: nothing here
/// marks an order paid, the order's status still comes from the server.
///
/// Saved on the device (see [PaymentAwaitingStore]) so a payment whose
/// confirmation was still outstanding when the app was closed is reconciled
/// on the next launch, and dropped from memory when the account changes.
class PaymentAwaitingConfirmation {
  final String orderId;
  final String ownerId;

  /// The cart lines this payment bought — removed from the cart once the
  /// server confirms. Empty for Buy Now, which never used the cart.
  final List<CartItem> cartLines;

  /// The same lines by id, for a record restored after a restart.
  final List<PurchasedLine>? restoredLines;

  /// True once the minute of automatic re-checking has run out (or the app
  /// was restarted) and the server still says `pending`. The order screen
  /// then says "still confirming" instead of offering to pay again.
  final bool windowElapsed;

  /// When the payment sheet reported success. Stamped by
  /// [setPaymentAwaiting]; a record older than [paymentAwaitingMaxAge]
  /// whose order is still `pending` is given up on (see [isExpired]).
  final DateTime? createdAt;

  const PaymentAwaitingConfirmation({
    required this.orderId,
    required this.ownerId,
    this.cartLines = const [],
    this.restoredLines,
    this.windowElapsed = false,
    this.createdAt,
  });

  List<PurchasedLine> get purchasedLines =>
      restoredLines ?? cartLines.map(PurchasedLine.fromCartItem).toList();

  /// True once the record has waited longer than [paymentAwaitingMaxAge].
  /// A record without a time never expires.
  bool isExpired(DateTime now) {
    final created = createdAt;
    return created != null && now.difference(created) > paymentAwaitingMaxAge;
  }

  PaymentAwaitingConfirmation withWindowElapsed() => PaymentAwaitingConfirmation(
    orderId: orderId,
    ownerId: ownerId,
    cartLines: cartLines,
    restoredLines: restoredLines,
    windowElapsed: true,
    createdAt: createdAt,
  );

  PaymentAwaitingConfirmation withCreatedAt(DateTime createdAt) =>
      PaymentAwaitingConfirmation(
        orderId: orderId,
        ownerId: ownerId,
        cartLines: cartLines,
        restoredLines: restoredLines,
        windowElapsed: windowElapsed,
        createdAt: createdAt,
      );
}

/// How long "still confirming" is believed. A payment the server has not
/// recorded after this long is not coming: the order goes back to being an
/// ordinary pending one, which can be paid or cancelled.
const paymentAwaitingMaxAge = Duration(hours: 2);

/// The clock the awaiting-payment record is stamped and aged by; replaced
/// in tests.
final paymentAwaitingClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Device storage for the one outstanding [PaymentAwaitingConfirmation] of
/// an account. Every method is best-effort: storage that cannot be read or
/// written must never break checkout or the order screen.
class PaymentAwaitingStore {
  PaymentAwaitingStore._();

  static String prefsKey(String ownerId) => 'payment_awaiting_v1::$ownerId';

  static Future<void> save(PaymentAwaitingConfirmation record) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        prefsKey(record.ownerId),
        jsonEncode({
          'order_id': record.orderId,
          'owner_id': record.ownerId,
          'created_at': ?record.createdAt?.toUtc().toIso8601String(),
          'lines': [for (final line in record.purchasedLines) line.toJson()],
        }),
      );
    } catch (_) {
      // The in-memory hint still covers this session.
    }
  }

  /// The saved record for [ownerId]. Always [windowElapsed]: the automatic
  /// re-checking belonged to the session that paid. A record saved before
  /// times were kept counts as created at [now], and is saved again with it.
  static Future<PaymentAwaitingConfirmation?> read(
    String ownerId, {
    DateTime Function() now = DateTime.now,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey(ownerId));
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map ||
          json['owner_id'] != ownerId ||
          json['order_id'] is! String ||
          (json['order_id'] as String).isEmpty) {
        await prefs.remove(prefsKey(ownerId));
        return null;
      }
      final lines = json['lines'];
      final savedAt = json['created_at'];
      final createdAt = savedAt is String ? DateTime.tryParse(savedAt) : null;
      final record = PaymentAwaitingConfirmation(
        orderId: json['order_id'] as String,
        ownerId: ownerId,
        restoredLines: [
          if (lines is List)
            for (final line in lines) ?PurchasedLine.fromJson(line),
        ],
        windowElapsed: true,
        createdAt: createdAt ?? now(),
      );
      if (createdAt == null) await save(record);
      return record;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String ownerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey(ownerId));
    } catch (_) {
      // Read again, and resolved again, on the next launch.
    }
  }
}

/// `ref.read` of a widget, a provider or a container.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Records that the payment sheet succeeded for [record]'s order: in memory
/// for the screens, and on the device for the next launch.
void setPaymentAwaiting(ProviderReader read, PaymentAwaitingConfirmation record) {
  final stamped = record.createdAt != null
      ? record
      : record.withCreatedAt(read(paymentAwaitingClockProvider)());
  read(paymentAwaitingConfirmationProvider.notifier).state = stamped;
  PaymentAwaitingStore.save(stamped);
}

/// The automatic re-checking ran out and the server still says `pending`.
/// The record stays (and stays saved) until the order settles.
void markPaymentAwaitingWindowElapsed(
  ProviderReader read,
  PaymentAwaitingConfirmation awaiting,
) {
  if (!identical(read(paymentAwaitingConfirmationProvider), awaiting)) return;
  read(paymentAwaitingConfirmationProvider.notifier).state = awaiting
      .withWindowElapsed();
}

/// Applies what the server says about the awaited order. [order] is the
/// freshly fetched row, or null when it no longer exists for this account.
///
/// Still `pending`: nothing changes and false is returned — unless the
/// record is older than [paymentAwaitingMaxAge], when it is given up on and
/// dropped, so the order is an ordinary pending one again. Paid: what it
/// bought leaves the cart. Anything else (cancelled, refunded, gone): the
/// record is simply dropped. In every settled case the record is cleared
/// from memory and from the device.
bool settlePaymentAwaiting(
  ProviderReader read,
  PaymentAwaitingConfirmation awaiting,
  Order? order,
) {
  if (!identical(read(paymentAwaitingConfirmationProvider), awaiting)) {
    return false;
  }
  if (read(currentUserIdProvider) != awaiting.ownerId) return false;
  final matches =
      order != null &&
      order.id == awaiting.orderId &&
      order.userId == awaiting.ownerId;
  if (matches &&
      order.status == OrderStatus.pending &&
      !awaiting.isExpired(read(paymentAwaitingClockProvider)())) {
    return false;
  }
  if (matches && paidOrderStatuses.contains(order.status)) {
    read(cartProvider.notifier).removePurchased(awaiting.purchasedLines);
  }
  read(paymentAwaitingConfirmationProvider.notifier).state = null;
  PaymentAwaitingStore.clear(awaiting.ownerId);
  return true;
}

final paymentAwaitingConfirmationProvider =
    StateProvider<PaymentAwaitingConfirmation?>((ref) {
      final userId = ref.watch(currentUserIdProvider);
      if (userId != null) {
        var disposed = false;
        ref.onDispose(() => disposed = true);
        // A payment still unconfirmed when the app was last closed: bring
        // the record back and ask the server once what became of the order.
        Future.microtask(() async {
          final saved = await PaymentAwaitingStore.read(
            userId,
            now: ref.read(paymentAwaitingClockProvider),
          );
          if (saved == null || disposed) return;
          // A payment made in this session is newer than the saved one.
          if (ref.controller.state != null) return;
          ref.controller.state = saved;
          final Order? order;
          try {
            order = await ref
                .read(orderRepositoryProvider)
                .fetchOrderById(saved.orderId);
          } catch (_) {
            // Offline: the order screen settles it on its next refresh.
            return;
          }
          if (disposed) return;
          settlePaymentAwaiting(ref.container.read, saved, order);
        });
      }
      return null;
    });

/// True while [order] is the signed-in customer's order whose payment sheet
/// succeeded and which the server has not confirmed yet.
PaymentAwaitingConfirmation? paymentAwaitingFor(
  PaymentAwaitingConfirmation? awaiting,
  Order order,
  String? currentUserId,
) =>
    awaiting != null &&
        awaiting.orderId == order.id &&
        awaiting.ownerId == order.userId &&
        awaiting.ownerId == currentUserId &&
        order.status == OrderStatus.pending
    ? awaiting
    : null;
