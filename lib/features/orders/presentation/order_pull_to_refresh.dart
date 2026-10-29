import 'package:flutter/material.dart';

/// One consistent gesture for order lists and details. Keep the last verified
/// data visible when a carrier is temporarily unavailable.
class OrderPullToRefresh extends StatelessWidget {
  const OrderPullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });
  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    notificationPredicate: (notification) =>
        notification.depth == 0 && notification.metrics.axis == Axis.vertical,
    onRefresh: () async {
      try {
        await onRefresh();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Some delivery updates are unavailable. Pull down to try again.',
              ),
            ),
          );
        }
      }
    },
    child: child,
  );
}
