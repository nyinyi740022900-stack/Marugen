import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/home_banner.dart';
import '../../../shared/widgets/sized_network_image.dart';
import 'home_banner_providers.dart';

/// The Shop tab's hero carousel, fed by [liveHomeBannersProvider].
///
/// Takes no space until there are live slides to show: nothing is reserved
/// while loading (most days there are no slides, and a skeleton that then
/// collapsed made the catalogue jump on every cold start), and a failed
/// fetch never pushes the catalogue down or blocks it. When slides arrive
/// the banner eases open; Reduce Motion shows it at once.
///
/// Slides are fetched again whenever the app returns from the background,
/// so a banner the owner just published or ended is not stale for the rest
/// of the day.
class HeroBannerCarousel extends ConsumerStatefulWidget {
  const HeroBannerCarousel({super.key});

  @override
  ConsumerState<HeroBannerCarousel> createState() => _HeroBannerCarouselState();
}

class _HeroBannerCarouselState extends ConsumerState<HeroBannerCarousel> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(liveHomeBannersProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The last good slides stay up through a refresh or a failed refetch.
    final banners =
        ref.watch(liveHomeBannersProvider).valueOrNull ?? const <HomeBanner>[];
    final Widget content = banners.isEmpty
        ? const SizedBox(key: ValueKey('no-banners'), width: double.infinity)
        : Padding(
            key: const ValueKey('banners'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: BannerCarousel(
              banners: banners,
              onOpen: (banner) => openBannerLink(context, banner),
            ),
          );
    // Reduce Motion: the banner is simply there, nothing grows or fades.
    // (AnimatedSize also cannot take a zero duration.)
    if (MediaQuery.disableAnimationsOf(context)) return content;
    return AnimatedSize(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOut,
        // Top-aligned so the slides do not slide down while the space opens.
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: content,
      ),
    );
  }
}

/// In-app paths (`/product/…`) push a route; anything else opens outside
/// the app. A slide with no link is just a picture.
Future<void> openBannerLink(BuildContext context, HomeBanner banner) async {
  final url = banner.linkUrl;
  if (url == null) return;
  if (banner.linksInsideApp) {
    context.push(url);
    return;
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
    return;
  }
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Auto-advancing, swipeable slides with pagination dots.
///
/// Motion follows the app's Apple-style rules: the finger drives the page
/// 1:1 (PageView), auto-advance pauses the moment a finger lands and for
/// [resumeAfterTouch] after it lifts, and Reduce Motion turns auto-advance
/// off entirely (the dots and swipe still work).
class BannerCarousel extends StatefulWidget {
  final List<HomeBanner> banners;
  final ValueChanged<HomeBanner>? onOpen;
  final Duration interval;
  final Duration resumeAfterTouch;

  static const aspectRatio = 16 / 8.5;

  const BannerCarousel({
    super.key,
    required this.banners,
    this.onOpen,
    this.interval = const Duration(seconds: 4),
    this.resumeAfterTouch = const Duration(seconds: 6),
  });

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  final _controller = PageController();
  Timer? _timer;
  Timer? _resume;
  int _page = 0;
  bool _touching = false;

  bool get _autoPlays =>
      widget.banners.length > 1 && !MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(BannerCarousel old) {
    super.didUpdateWidget(old);
    if (old.banners.length != widget.banners.length) {
      if (_page >= widget.banners.length) {
        _page = 0;
        if (_controller.hasClients) _controller.jumpToPage(0);
      }
      _schedule();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _resume?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_autoPlays || _touching) return;
    _timer = Timer.periodic(widget.interval, (_) => _advance());
  }

  void _advance() {
    if (!mounted || !_controller.hasClients || _touching) return;
    final next = (_page + 1) % widget.banners.length;
    // Wrapping from the last slide back to the first flies across every
    // page; jump straight there with a quick fade-free hop instead.
    if (next == 0) {
      _controller.jumpToPage(0);
      return;
    }
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _onTouchStart() {
    _touching = true;
    _timer?.cancel();
    _resume?.cancel();
  }

  void _onTouchEnd() {
    _touching = false;
    _resume?.cancel();
    // Give the reader time with the slide they chose before moving on.
    _resume = Timer(widget.resumeAfterTouch, _schedule);
  }

  @override
  Widget build(BuildContext context) {
    final banners = widget.banners;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AspectRatio(
            aspectRatio: BannerCarousel.aspectRatio,
            child: Listener(
              onPointerDown: (_) => _onTouchStart(),
              onPointerUp: (_) => _onTouchEnd(),
              onPointerCancel: (_) => _onTouchEnd(),
              child: PageView.builder(
                controller: _controller,
                itemCount: banners.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => Semantics(
                  label: bannerSemanticsLabel(banners[i], i, banners.length),
                  button: banners[i].linkUrl != null,
                  child: BannerSlide(
                    banner: banners[i],
                    // Already in the label above: not read a second time.
                    headlineInSemantics: false,
                    onTap: banners[i].linkUrl == null
                        ? null
                        : () => widget.onOpen?.call(banners[i]),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (banners.length > 1) ...[
          _PaginationDots(
            count: banners.length,
            index: _page,
            onSelect: (i) {
              _onTouchStart();
              _controller.animateToPage(
                i,
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutCubic,
              );
              _onTouchEnd();
            },
          ),
        ],
      ],
    );
  }
}

/// What a screen reader says for a slide: its position, headline and, when
/// the slide leads somewhere, the button label that names the action.
String bannerSemanticsLabel(HomeBanner banner, int index, int count) {
  final parts = [
    'Banner ${index + 1} of $count',
    if (banner.title != null) ': ${banner.title}',
    if (banner.showsCta) '. ${banner.ctaLabel}',
  ];
  return parts.join();
}

/// One slide: photo, scrim, headline/subtitle and a CTA pill. Also the
/// admin form's live preview, where [localImage] shows a photo that has
/// not been uploaded yet.
class BannerSlide extends StatelessWidget {
  final HomeBanner banner;
  final VoidCallback? onTap;
  final Uint8List? localImage;

  /// False where a parent's semantics label already says the headline (the
  /// carousel), so a screen reader does not read it twice.
  final bool headlineInSemantics;
  const BannerSlide({
    super.key,
    required this.banner,
    this.onTap,
    this.localImage,
    this.headlineInSemantics = true,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final Widget image;
    if (localImage != null) {
      image = Image.memory(
        localImage!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else if (banner.imageUrl.isEmpty) {
      image = ColoredBox(
        color: palette.surfaceMuted,
        child: Icon(
          Icons.add_a_photo_outlined,
          size: 36,
          color: palette.textMuted,
        ),
      );
    } else {
      image = SizedNetworkImage(
        imageUrl: banner.imageUrl,
        fit: BoxFit.cover,
        placeholder: (_, _) => ColoredBox(color: palette.surfaceMuted),
        errorWidget: (_, _, _) => ColoredBox(
          color: palette.surfaceMuted,
          child: Icon(
            Icons.image_not_supported_outlined,
            color: palette.textMuted,
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          image,
          if (banner.hasText || banner.showsCta)
            // Legibility over any photo: a scrim that is darkest where the
            // text sits and clear at the top so the image still reads.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.25, 1],
                  colors: [Colors.transparent, Color(0xB3000000)],
                ),
              ),
            ),
          if (banner.hasText || banner.showsCta)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (banner.title != null)
                    ExcludeSemantics(
                      excluding: !headlineInSemantics,
                      child: Text(
                        banner.title!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          letterSpacing: -0.3,
                          shadows: const [
                            Shadow(color: Color(0x66000000), blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  if (banner.subtitle != null && scaler.scale(14) <= 20) ...[
                    const SizedBox(height: 4),
                    Text(
                      banner.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xE6FFFFFF),
                        fontSize: 13.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                  // A button with nowhere to go is never drawn.
                  if (banner.showsCta) ...[
                    const SizedBox(height: 10),
                    // Visual only: the whole slide is the tap target.
                    ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          banner.ctaLabel!,
                          style: const TextStyle(
                            color: AppColors.black,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PaginationDots extends StatelessWidget {
  final int count;
  final int index;
  final ValueChanged<int> onSelect;
  const _PaginationDots({
    required this.count,
    required this.index,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Banner ${index + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            // 44pt square target per dot (the dots stay visually small);
            // Flexible lets a long row of slides still fit a narrow phone.
            Flexible(
              child: Semantics(
                button: true,
                selected: i == index,
                label: 'Go to banner ${i + 1}',
                onTap: () => onSelect(i),
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: AnimatedContainer(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        width: i == index ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == index ? palette.accent : palette.border,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
