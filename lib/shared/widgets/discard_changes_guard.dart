import 'package:flutter/material.dart';

import 'confirm_dialog.dart';

/// Stops a back swipe or AppBar back from silently throwing away a form.
///
/// Wrap the form's Scaffold; pass [dirty] from the form's own comparison of
/// current values against what it loaded. While [dirty] is false (or
/// [busy], mid-save) the route pops as usual; otherwise the user is asked
/// to confirm, and only "Discard" pops.
class DiscardChangesGuard extends StatelessWidget {
  final bool dirty;
  final bool busy;
  final String message;
  final Widget child;

  const DiscardChangesGuard({
    super.key,
    required this.dirty,
    required this.child,
    this.busy = false,
    this.message = 'Your unsaved edits will be lost.',
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty || busy,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final discard = await confirmDestructiveAction(
        context,
        title: 'Discard changes?',
        message: message,
        confirmLabel: 'Discard',
      );
      if (discard && context.mounted) Navigator.of(context).pop();
    },
    child: child,
  );
}
