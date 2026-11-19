import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/order.dart';
import '../../../shared/utils/price_format.dart';
import '../../../shared/widgets/section_label.dart';
import '../utils/order_payment_line.dart';

/// Staff-only "PAYMENT" block on the order screen: how the order was paid,
/// what was collected and refunded, and the Stripe PaymentIntent id to copy
/// when matching a payout. Replaces the old Orders > Payments ledger row.
class AdminOrderPaymentSection extends StatelessWidget {
  final Order order;
  const AdminOrderPaymentSection({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final paymentId = order.stripePaymentIntentId?.trim() ?? '';
    final line = orderPaymentLine(order);
    final statusColor = switch (line.tone) {
      PaymentLineTone.problem => palette.error,
      PaymentLineTone.pending => palette.warning,
      PaymentLineTone.neutral => palette.text,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('PAYMENT'),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: AppShadows.card,
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.sm),
                _Row(
                  label: 'Method',
                  value: paymentId.isEmpty ? 'No online payment' : 'Stripe',
                ),
                _Row(label: 'Order total', value: formatPrice(order.total)),
                _Row(label: 'Payment', value: line.text, color: statusColor),
                if (order.refundAmount > 0)
                  _Row(
                    label: 'Refunded',
                    value: formatPrice(order.refundAmount),
                  ),
                if (order.refundPendingAmount > 0)
                  _Row(
                    label: 'Refund awaiting confirmation',
                    value: formatPrice(order.refundPendingAmount),
                  ),
                if (order.netPaidAmount > 0 && order.refundAmount > 0)
                  _Row(
                    label: 'Kept after refunds',
                    value: formatPrice(order.netPaidAmount),
                  ),
                if (paymentId.isEmpty)
                  const SizedBox(height: AppSpacing.sm)
                else ...[
                  const Divider(height: AppSpacing.md, indent: 16, endIndent: 16),
                  _PaymentIdRow(paymentId: paymentId),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Row({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      // A Wrap, so a long value drops under its label at large text sizes
      // instead of being squeezed beside it.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: AppSpacing.md,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12.5, color: palette.textMuted),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color ?? palette.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentIdRow extends StatelessWidget {
  final String paymentId;
  const _PaymentIdRow({required this.paymentId});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: paymentId));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Payment ID copied')));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      button: true,
      label: 'Copy payment ID $paymentId',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => _copy(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kMinInteractiveDimension,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment ID',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // The whole id, wrapped: staff paste it into Stripe.
                      Text(
                        paymentId,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: palette.text,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Icon(Icons.copy_rounded, size: 18, color: palette.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
