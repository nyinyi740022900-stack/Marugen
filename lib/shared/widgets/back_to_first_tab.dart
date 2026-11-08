import 'package:flutter/material.dart';

/// Android back on any tab but the first returns to the first tab instead
/// of closing the app — what shoppers expect from Shopee/Lazada-style tab
/// bars. On the first tab back behaves as usual.
class BackToFirstTab extends StatelessWidget {
  final int index;
  final VoidCallback onBackToFirst;
  final Widget child;

  const BackToFirstTab({
    super.key,
    required this.index,
    required this.onBackToFirst,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBackToFirst();
      },
      child: child,
    );
  }
}
