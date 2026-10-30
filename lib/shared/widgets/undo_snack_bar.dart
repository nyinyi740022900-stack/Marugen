import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How long a removal can be undone before its snack bar closes itself.
const undoSnackBarDuration = Duration(seconds: 5);

/// Shows [message] with an Undo-style action and a visible countdown, then
/// closes itself after [duration] — shared by every remove/delete flow
/// (cart, checkout, notifications, admin stock toggle).
///
/// Flutter keeps any snack bar that has an action on screen until it is
/// swiped away unless `persist` is false, which is why these bars used to
/// stay up. With a screen reader or switch access on (accessible
/// navigation), the bar still stays until dismissed, without the countdown,
/// so there is time to reach the action.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showUndoSnackBar(
  ScaffoldMessengerState messenger, {
  required String message,
  required VoidCallback onAction,
  String actionLabel = 'Undo',
  Duration duration = undoSnackBarDuration,
}) {
  final accessibleNavigation =
      MediaQuery.maybeAccessibleNavigationOf(messenger.context) ?? false;
  messenger.clearSnackBars();
  return messenger.showSnackBar(
    SnackBar(
      content: accessibleNavigation
          ? Text(message)
          : UndoCountdownContent(message: message, duration: duration),
      duration: duration,
      persist: accessibleNavigation,
      action: SnackBarAction(label: actionLabel, onPressed: onAction),
    ),
  );
}

/// The snack bar message after a ring that empties once per second with
/// the seconds left in its centre. It ticks with a timer rather than a
/// continuous animation, and the ring is hidden from screen readers: the
/// snack bar is a live region, so a changing number would be re-announced.
class UndoCountdownContent extends StatefulWidget {
  final String message;
  final Duration duration;

  const UndoCountdownContent({
    super.key,
    required this.message,
    this.duration = undoSnackBarDuration,
  });

  @override
  State<UndoCountdownContent> createState() => _UndoCountdownContentState();
}

class _UndoCountdownContentState extends State<UndoCountdownContent> {
  late final int _total = math.max(1, widget.duration.inSeconds);
  late int _remaining = _total;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining <= 1) {
        timer.cancel();
        return;
      }
      setState(() => _remaining--);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = DefaultTextStyle.of(context).style.color ?? Colors.white;
    return Row(
      children: [
        ExcludeSemantics(
          child: SizedBox.square(
            dimension: 28,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: _remaining / _total),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              builder: (context, fraction, child) => CustomPaint(
                painter: _CountdownRingPainter(
                  fraction: fraction,
                  color: color,
                ),
                child: child,
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: FittedBox(
                  child: Text(
                    '$_remaining',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(widget.message)),
      ],
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  final double fraction;
  final Color color;

  const _CountdownRingPainter({required this.fraction, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.5;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      paint..color = color.withValues(alpha: 0.25),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0, 1),
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_CountdownRingPainter old) =>
      old.fraction != fraction || old.color != color;
}
