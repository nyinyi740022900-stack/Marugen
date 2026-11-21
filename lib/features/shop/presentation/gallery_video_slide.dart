import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/press_scale.dart';
import '../../../shared/widgets/product_video_player.dart';
import '../../../shared/widgets/sized_network_image.dart';

/// The video of a live fish as a slide of the product photo gallery.
///
/// It opens as a poster (the cover photo with a play button) and nothing is
/// downloaded or played until the shopper taps it. Once playing, it pauses
/// whenever the slide is not [selected] or another screen covers this one,
/// and never resumes by itself.
class GalleryVideoSlide extends StatefulWidget {
  final String videoUrl;
  final String productName;

  /// Shown dimmed behind the play button. Null for a fish with no photos.
  final String? posterUrl;

  /// Whether this slide is the gallery's current page.
  final bool selected;

  const GalleryVideoSlide({
    super.key,
    required this.videoUrl,
    required this.productName,
    required this.selected,
    this.posterUrl,
  });

  /// Room left under the player for the gallery's page badge, so the badge
  /// never sits on the player's own controls.
  static const double badgeClearance = 44;

  @override
  State<GalleryVideoSlide> createState() => _GalleryVideoSlideState();
}

class _GalleryVideoSlideState extends State<GalleryVideoSlide> {
  bool _started = false;

  @override
  Widget build(BuildContext context) {
    // Rebuilds when a route is pushed over, or popped off, this screen.
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ColoredBox(
      color: AppColors.black,
      child: AnimatedSwitcher(
        // Reduced motion: the player simply replaces the poster.
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 200),
        child: _started
            ? Padding(
                key: const ValueKey('player'),
                // Clear of the app bar's back/share/heart buttons above and
                // the page badge below.
                padding: EdgeInsets.only(
                  top: MediaQuery.paddingOf(context).top + kToolbarHeight,
                  bottom: GalleryVideoSlide.badgeClearance,
                ),
                child: Center(
                  child: ProductVideoPlayer(
                    videoUrl: widget.videoUrl,
                    // The shopper asked for it by tapping the poster.
                    autoPlay: true,
                    active: widget.selected && routeIsCurrent,
                  ),
                ),
              )
            : _Poster(
                key: const ValueKey('poster'),
                posterUrl: widget.posterUrl,
                productName: widget.productName,
                onPlay: () => setState(() => _started = true),
              ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  final String? posterUrl;
  final String productName;
  final VoidCallback onPlay;

  const _Poster({
    super.key,
    required this.posterUrl,
    required this.productName,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Play video of $productName',
      excludeSemantics: true,
      onTap: onPlay,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPlay,
        child: PressScale(
          pressedScale: 0.98,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (posterUrl != null)
                SizedNetworkImage(
                  imageUrl: posterUrl!,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const SizedBox.shrink(),
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              // Dimmed so the play button, not the photo, is the subject and
              // the slide cannot be mistaken for another photo.
              ColoredBox(color: AppColors.black.withValues(alpha: 0.45)),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.white.withValues(alpha: 0.94),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 44,
                        color: AppColors.black,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      'Play video',
                      style: TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
