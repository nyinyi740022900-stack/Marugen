import 'package:flutter/widgets.dart';

/// Shrinks [child] slightly the instant a finger lands on it, and springs
/// back on release — the touch-down feedback iOS uses on cards and tiles.
///
/// Feedback starts on pointer-down (not on tap-up), and a finger that moves
/// more than [slop] (the start of a scroll) releases the press so cards in a
/// scrolling grid don't stay pressed while the list moves.
///
/// Uses a [Listener], so it never competes with the child's own gesture
/// recognizers (InkWell, buttons, scroll views).
class PressScale extends StatefulWidget {
  final Widget child;
  final double pressedScale;
  final double slop;

  const PressScale({
    super.key,
    required this.child,
    this.pressedScale = 0.97,
    this.slop = 10,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;
  Offset? _downPosition;

  void _set(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: (e) {
        _downPosition = e.position;
        _set(true);
      },
      onPointerMove: (e) {
        final start = _downPosition;
        if (start != null && (e.position - start).distance > widget.slop) {
          _downPosition = null;
          _set(false);
        }
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed && !reduceMotion ? widget.pressedScale : 1,
        // Fast in, slightly slower out — press feels immediate, release
        // settles instead of snapping.
        duration: Duration(milliseconds: _pressed ? 100 : 200),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
