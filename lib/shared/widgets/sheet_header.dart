import 'package:flutter/material.dart';

/// Title row for a non-dismissible form sheet: the close button is the one
/// way out, so a back gesture or tap outside can't throw the form away;
/// `maybePop` lets a [DiscardChangesGuard] above ask first.
class SheetHeader extends StatelessWidget {
  final String title;
  const SheetHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      IconButton(
        tooltip: 'Close',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    ],
  );
}
