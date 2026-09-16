import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_theme.dart';

/// Renders a video from a direct URL (`product.videoUrl`) with loading and
/// error states that never crash the screen — a broken/unreachable link
/// just falls back to a friendly placeholder.
class ProductVideoPlayer extends StatefulWidget {
  final String videoUrl;
  const ProductVideoPlayer({super.key, required this.videoUrl});

  @override
  State<ProductVideoPlayer> createState() => _ProductVideoPlayerState();
}

class _ProductVideoPlayerState extends State<ProductVideoPlayer> {
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
        autoPlay: false,
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

  Widget _placeholder({required IconData icon, required String message, bool loading = false}) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.offWhite,
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
                Icon(icon, size: 32, color: AppColors.grey),
              const SizedBox(height: AppSpacing.sm),
              Text(message, style: const TextStyle(color: AppColors.grey, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}
