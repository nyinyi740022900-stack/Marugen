import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/theme/app_theme.dart';
import '../utils/youtube_utils.dart';

/// Renders a video from `product.videoUrl` — a YouTube link (watch/
/// youtu.be/shorts) gets the YouTube embed player; anything else is
/// treated as a direct video file URL and played via video_player/chewie.
/// Loading and error states never crash the screen — a broken/unreachable
/// link just falls back to a friendly placeholder.
class ProductVideoPlayer extends StatelessWidget {
  final String videoUrl;

  /// Start playing as soon as the video is ready. Only for a player that is
  /// created because the person just asked to play (tapped a poster); a
  /// video never starts, with or without sound, on its own.
  final bool autoPlay;

  /// False while the player is not what the person is looking at (its
  /// gallery slide was swiped away, another screen covers it): playback is
  /// paused and stays paused until they press play again.
  final bool active;

  const ProductVideoPlayer({
    super.key,
    required this.videoUrl,
    this.autoPlay = false,
    this.active = true,
  });

  @override
  Widget build(BuildContext context) {
    final youtubeId = extractYoutubeId(videoUrl);
    if (youtubeId != null) {
      return _YoutubeVideoPlayer(
        videoId: youtubeId,
        autoPlay: autoPlay,
        active: active,
      );
    }
    return _DirectFileVideoPlayer(
      videoUrl: videoUrl,
      autoPlay: autoPlay,
      active: active,
    );
  }
}

class _YoutubeVideoPlayer extends StatefulWidget {
  final String videoId;
  final bool autoPlay;
  final bool active;
  const _YoutubeVideoPlayer({
    required this.videoId,
    required this.autoPlay,
    required this.active,
  });

  @override
  State<_YoutubeVideoPlayer> createState() => _YoutubeVideoPlayerState();
}

class _YoutubeVideoPlayerState extends State<_YoutubeVideoPlayer> {
  late final YoutubePlayerController _controller;
  late final StreamSubscription<YoutubePlayerValue> _states;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: widget.autoPlay && widget.active,
      params: const YoutubePlayerParams(showFullscreenButton: true),
    );
    // Also covers a player that only becomes ready, and starts, after it
    // was already swiped away.
    _states = _controller.listen((value) {
      if (!widget.active && value.playerState == PlayerState.playing) {
        _controller.pauseVideo();
      }
    });
  }

  @override
  void didUpdateWidget(_YoutubeVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) _controller.pauseVideo();
  }

  @override
  void dispose() {
    _states.cancel();
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: YoutubePlayer(controller: _controller),
      ),
    );
  }
}

class _DirectFileVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool autoPlay;
  final bool active;
  const _DirectFileVideoPlayer({
    required this.videoUrl,
    required this.autoPlay,
    required this.active,
  });

  @override
  State<_DirectFileVideoPlayer> createState() => _DirectFileVideoPlayerState();
}

class _DirectFileVideoPlayerState extends State<_DirectFileVideoPlayer> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _error = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final uri = Uri.tryParse(widget.videoUrl);
      if (uri == null || !uri.hasScheme) {
        throw Exception('Invalid video URL');
      }
      final controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      _videoController = controller;
      _chewieController = ChewieController(
        videoPlayerController: controller,
        // Not if it was swiped away while it was still loading.
        autoPlay: widget.autoPlay && widget.active,
        looping: false,
        aspectRatio: controller.value.aspectRatio == 0
            ? 16 / 9
            : controller.value.aspectRatio,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.red,
          handleColor: AppColors.red,
        ),
      );
      setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void didUpdateWidget(_DirectFileVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Chewie's own fullscreen is a route on top of this one: the video is
    // still what the person is watching, so that must not pause it.
    if (oldWidget.active &&
        !widget.active &&
        _chewieController?.isFullScreen != true) {
      _videoController?.pause();
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return _placeholder(
        icon: Icons.videocam_off_outlined,
        message: 'Video could not be loaded.',
      );
    }
    if (!_ready || _chewieController == null) {
      return _placeholder(
        icon: Icons.play_circle_outline,
        message: 'Loading video…',
        loading: true,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: AspectRatio(
        aspectRatio: _chewieController!.aspectRatio ?? 16 / 9,
        child: Chewie(controller: _chewieController!),
      ),
    );
  }

  Widget _placeholder({
    required IconData icon,
    required String message,
    bool loading = false,
  }) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.of(context).surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(icon, size: 32, color: AppPalette.of(context).textMuted),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                style: TextStyle(
                  color: AppPalette.of(context).textMuted,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
