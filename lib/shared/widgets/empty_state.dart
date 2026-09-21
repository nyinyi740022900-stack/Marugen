import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shared "nothing here yet" layout — icon in a soft red-tinted circle,
/// title, subtitle and an optional action button — used across the shop,
/// cart, orders, wishlist and knowledge screens instead of each rolling
/// its own bespoke empty state.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    AppColors.redSoft,
                    AppColors.redSoft.withValues(alpha: 0.35),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.card,
                  ),
                  child: Icon(icon, size: 28, color: AppColors.red),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.grey, fontSize: 13.5, height: 1.4),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standard "something went wrong" state for an `AsyncValue.error` branch —
/// a friendly, non-technical message plus a Retry button that re-runs
/// [onRetry] (typically `() => ref.invalidate(someProvider)`), instead of
/// each screen showing the raw exception text (`'Error: $e'`) with no way
/// to recover short of leaving the screen.
class ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final String? subtitle;

  const ErrorState({super.key, required this.onRetry, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.wifi_off_outlined,
      title: 'Something went wrong',
      subtitle: subtitle ?? "We couldn't load this right now. Check your connection and try again.",
      actionLabel: 'Retry',
      onAction: onRetry,
    );
  }
}
