import 'package:flutter/material.dart';

import '../utils/error_message.dart';

/// Runs the write passed to it, unless one is already running.
typedef GuardedRun = Future<void> Function(Future<void> Function() write);

/// The busy-flag + try/catch + snackbar pattern for a button that writes,
/// for rows that have no State of their own (list tiles built by a
/// ConsumerWidget). [builder] gets `busy` to disable its buttons and `run`
/// to wrap the write: a second tap while one write is in flight does
/// nothing, and a failure is shown with [friendlyErrorMessage] instead of
/// vanishing as an unhandled exception.
class GuardedWrite extends StatefulWidget {
  /// Shown when the error has no user-safe message of its own.
  final String errorFallback;

  /// Log / crash-report tag, e.g. `admin.services`.
  final String errorContext;
  final Widget Function(BuildContext context, bool busy, GuardedRun run)
  builder;

  const GuardedWrite({
    super.key,
    required this.errorFallback,
    required this.errorContext,
    required this.builder,
  });

  @override
  State<GuardedWrite> createState() => _GuardedWriteState();
}

class _GuardedWriteState extends State<GuardedWrite> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() write) async {
    if (_busy) return;
    // Captured first: a successful delete removes this row, and a failure
    // must still be reported after the list has rebuilt.
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      await write();
    } catch (e, st) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: widget.errorFallback,
              context: widget.errorContext,
              stackTrace: st,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // While busy the taps are swallowed here, not just ignored: a tap on a
  // disabled button otherwise goes to whatever is underneath it (the list
  // tile, which opens the edit form in the middle of the save).
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    onTap: _busy ? () {} : null,
    child: AbsorbPointer(
      absorbing: _busy,
      child: widget.builder(context, _busy, _run),
    ),
  );
}
