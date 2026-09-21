import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Standard destructive-action confirmation — matches the dialog already
/// used for product delete (admin_product_edit_screen.dart). Returns true
/// only if the user tapped the destructive action; use this before any
/// delete/cancel/refund-style call so a single mis-tap on a list icon
/// can't silently destroy data with no way back.
Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel, style: const TextStyle(color: AppColors.error)),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Confirmation for a final-but-not-destructive action (e.g. "Delivered by
/// shop") — same shape as [confirmDestructiveAction] but the confirm
/// button reads as a normal primary action (brand red fill) rather than a
/// warning, since the action itself isn't harmful, just irreversible.
/// Every major platform (Shopify's "Fulfill order", Amazon Seller
/// Central's "Confirm shipment", Shopee/Lazada's shipment flows) puts a
/// confirmation step in front of "mark this order delivered/shipped"
/// rather than firing it on a single tap — a stray tap here immediately
/// notifies the customer and (per 0030_order_status_forward_only.sql)
/// can never be walked back to `shipped`/`packing` afterwards.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Branded log-out confirmation — an icon-circle + full-width action
/// button matching [EmptyState]'s visual language, instead of the default
/// plain-text `AlertDialog` (title + two `TextButton`s) that felt out of
/// place next to the rest of the app's rounded, icon-led screens.
Future<bool> confirmLogout(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xxl,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [AppColors.redSoft, AppColors.redSoft.withValues(alpha: 0.35)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout, size: 30, color: AppColors.error),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Log out?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 6),
            const Text(
              'You can log back in anytime.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.grey, fontSize: 13.5),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: AppColors.white,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Log Out'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
  return confirmed == true;
}
