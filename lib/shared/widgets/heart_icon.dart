import 'package:flutter/material.dart';

/// Wishlist heart that gives a small spring "pop" the moment it fills.
///
/// Pops only on a false → true change while on screen, never on first
/// build — a grid of already-saved products must not all bounce as it
/// scrolls in. Reduced motion: the icon just swaps.
class HeartIcon extends StatefulWidget {
  final bool filled;
  final double size;
  final Color color;

  const HeartIcon({
    super.key,
    required this.filled,
    required this.color,
    this.size = 24,
  });

  @override
  State<HeartIcon> createState() => _HeartIconState();
}

class _HeartIconState extends State<HeartIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1,
  );

  // Dips slightly, then overshoots a touch and settles — the tap carried
  // intent, so a little bounce is earned here.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0.7), weight: 25),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.7,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 75,
    ),
  ]).animate(_pop);

  @override
  void didUpdateWidget(HeartIcon old) {
    super.didUpdateWidget(old);
    if (widget.filled &&
        !old.filled &&
        !MediaQuery.disableAnimationsOf(context)) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _scale,
    child: Icon(
      widget.filled ? Icons.favorite : Icons.favorite_border,
      size: widget.size,
      color: widget.color,
    ),
  );
}
