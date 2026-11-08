import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../core/theme/app_theme.dart';

/// Full-screen, pinch-to-zoom photo viewer — swipe between every image in
/// [imageUrls], starting at [initialIndex].
///
/// When the caller wraps its thumbnails in [Hero]s tagged with
/// [heroTag] (`heroTag(heroTagPrefix, index)`), the photo grows out of the
/// thumbnail it was opened from and returns to it on close. Drag a photo
/// up or down to dismiss: it follows the finger 1:1, the backdrop fades
/// with the distance, and on release the momentum decides whether it
/// closes or springs back.
class FullscreenImageGallery extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final String? heroTagPrefix;
  final ValueChanged<int>? onIndexChanged;

  const FullscreenImageGallery({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    this.heroTagPrefix,
    this.onIndexChanged,
  });

  /// Shared tag format so the thumbnail and gallery heroes always match.
  static String heroTag(String prefix, int index) => '$prefix-$index';

  /// [onIndexChanged] lets the opener follow the gallery's page while it
  /// is open, so the photo flies back to the matching thumbnail on close.
  static void open(
    BuildContext context, {
    required List<String> imageUrls,
    int initialIndex = 0,
    String? heroTagPrefix,
    ValueChanged<int>? onIndexChanged,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        // Transparent so the page underneath shows through while the
        // photo is dragged away.
        opaque: false,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) => FullscreenImageGallery(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
          heroTagPrefix: heroTagPrefix,
          onIndexChanged: onIndexChanged,
        ),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  State<FullscreenImageGallery> createState() => _FullscreenImageGalleryState();
}

class _FullscreenImageGalleryState extends State<FullscreenImageGallery>
    with SingleTickerProviderStateMixin {
  late final PageController _controller;
  late final AnimationController _drag;
  final _zoom = <int, TransformationController>{};
  late int _index;
  bool _dragging = false;
  bool _closing = false;

  // Critically damped (no overshoot), ~0.35s response — Apple's default
  // for repositioning something the user let go of.
  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 322,
    ratio: 1,
  );

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
    _drag = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    _drag.dispose();
    for (final c in _zoom.values) {
      c.dispose();
    }
    super.dispose();
  }

  TransformationController _zoomFor(int i) =>
      _zoom.putIfAbsent(i, TransformationController.new);

  bool _isZoomed(int i) => (_zoom[i]?.value.getMaxScaleOnAxis() ?? 1) > 1.01;

  void _onStart(int i, ScaleStartDetails d) {
    if (_closing || d.pointerCount != 1 || _isZoomed(i)) return;
    // Grab the photo mid-spring from wherever it is right now.
    _drag.stop();
    _dragging = true;
  }

  void _onUpdate(ScaleUpdateDetails d) {
    if (!_dragging) return;
    if (d.pointerCount > 1) {
      // A second finger means a pinch, not a dismiss.
      _dragging = false;
      _settle(0);
      return;
    }
    _drag.value += d.focalPointDelta.dy;
  }

  void _onEnd(ScaleEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final velocity = d.velocity.pixelsPerSecond.dy;
    // Project where the flick would come to rest (Apple's scroll-style
    // deceleration) instead of judging by the release point alone.
    const decelerationRate = 0.998;
    final projected =
        _drag.value +
        (velocity / 1000) * decelerationRate / (1 - decelerationRate);
    final height = MediaQuery.sizeOf(context).height;
    if (projected.abs() > height * 0.25) {
      _closing = true;
      Navigator.of(context).pop();
    } else {
      _settle(velocity);
    }
  }

  void _settle(double velocity) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _drag.value = 0;
      return;
    }
    // Hand the finger's velocity to the spring so there's no seam
    // between dragging and animating.
    _drag.animateWith(SpringSimulation(_spring, _drag.value, 0, velocity));
  }

  Widget _image(int i) {
    Widget image = CachedNetworkImage(
      imageUrl: widget.imageUrls[i],
      fit: BoxFit.contain,
      placeholder: (_, _) => const Center(
        child: CircularProgressIndicator(color: AppColors.white),
      ),
      errorWidget: (_, _, _) => const Icon(
        Icons.image_not_supported_outlined,
        color: AppColors.greySoft,
        size: 40,
      ),
    );
    final prefix = widget.heroTagPrefix;
    if (prefix != null) {
      image = Hero(
        tag: FullscreenImageGallery.heroTag(prefix, i),
        child: image,
      );
    }
    return image;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final height = MediaQuery.sizeOf(context).height;
    // Transparency Material gives the chrome text its theme style without
    // painting over the page underneath.
    return Material(
      type: MaterialType.transparency,
      child: HeroMode(
        // Reduced motion: the route's plain cross-fade, no flying photo.
        enabled: !reduceMotion,
        child: AnimatedBuilder(
          animation: _drag,
          builder: (context, child) {
            final offset = _drag.value;
            final progress = (offset.abs() / (height * 0.4)).clamp(0.0, 1.0);
            return Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: AppColors.black.withValues(alpha: 1 - progress),
                  ),
                ),
                Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(0, offset),
                    child: Transform.scale(
                      scale: 1 - 0.2 * progress,
                      child: child,
                    ),
                  ),
                ),
                // Chrome gets out of the way as soon as a dismiss starts.
                Opacity(
                  opacity: (1 - progress * 3).clamp(0.0, 1.0),
                  child: _chrome(context),
                ),
              ],
            );
          },
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.imageUrls.length,
            onPageChanged: (i) {
              setState(() => _index = i);
              widget.onIndexChanged?.call(i);
            },
            itemBuilder: (context, i) => InteractiveViewer(
              transformationController: _zoomFor(i),
              minScale: 1,
              maxScale: 4,
              onInteractionStart: (d) => _onStart(i, d),
              onInteractionUpdate: _onUpdate,
              onInteractionEnd: _onEnd,
              child: Center(child: _image(i)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chrome(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CircleIconButton(
            icon: Icons.close,
            tooltip: 'Close',
            onTap: () => Navigator.of(context).pop(),
          ),
          if (widget.imageUrls.length > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '${_index + 1} / ${widget.imageUrls.length}',
                style: const TextStyle(color: AppColors.white, fontSize: 13),
              ),
            )
          else
            const SizedBox.shrink(),
          const SizedBox(width: 40),
        ],
      ),
    ),
  );
}

/// Small circular icon button (translucent black, white icon) used for
/// "close" affordances floating over photo content — the fullscreen
/// gallery's close button and the promo banner popup's dismiss button
/// (see promo_banner_dialog.dart) both use this.
class CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Color? backgroundColor;
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor ?? AppColors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // 13px padding + 22px icon = a 48px native touch target.
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Icon(icon, color: AppColors.white, size: 22),
          ),
        ),
      ),
    );
  }
}
