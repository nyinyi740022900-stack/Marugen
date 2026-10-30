import '../utils/server_time.dart';

/// A cancellation decision and its payment refund are separate states.
class OrderCancellationRequest {
  final String status;
  final String? reason, reviewNote;
  final DateTime? requestedAt, reviewedAt;
  const OrderCancellationRequest({
    required this.status,
    this.reason,
    this.reviewNote,
    this.requestedAt,
    this.reviewedAt,
  });

  bool get holdsFulfillment => status == 'requested' || status == 'approved';

  static OrderCancellationRequest? fromRelation(dynamic value) {
    if (value is List) value = value.isEmpty ? null : value.first;
    if (value is! Map) return null;
    return OrderCancellationRequest(
      status: value['status'] as String? ?? 'unknown',
      reason: value['reason'] as String?,
      reviewNote: value['review_note'] as String?,
      requestedAt: tryParseServerTime(value['requested_at']),
      reviewedAt: tryParseServerTime(value['reviewed_at']),
    );
  }
}
