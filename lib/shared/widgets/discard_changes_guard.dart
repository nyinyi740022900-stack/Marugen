import 'package:flutter/material.dart';

import 'confirm_dialog.dart';

/// Keeps a form's [DiscardChangesGuard] in step with typed text.
///
/// Typing in a field does not rebuild the form's State, so a guard built
/// with `dirty: false` stays that way and a text-only edit can be closed
/// without the "Discard changes?" question. Mix this in, return the form's
/// own comparison from [formDirty], pass [guardDirty] to the guard, and
/// [trackDirty] every controller: the State then rebuilds exactly when the
/// answer flips.
mixin DirtyFormState<T extends StatefulWidget> on State<T> {
  /// Whether the form differs from what it loaded.
  bool get formDirty;

  bool _guardDirty = false;

  /// For `DiscardChangesGuard(dirty: ...)`; call it from build.
  bool get guardDirty => _guardDirty = formDirty;

  /// Listens to [source] (a TextEditingController) for edits. The listener
  /// goes when the controller is disposed.
  void trackDirty(Listenable source) => source.addListener(_onEdited);

  void _onEdited() {
    if (!mounted) return;
    if (formDirty != _guardDirty) setState(() {});
  }
}

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
