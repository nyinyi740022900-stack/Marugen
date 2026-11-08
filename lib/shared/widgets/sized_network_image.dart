import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Longest side, in pixels, of photos picked for upload. Phone cameras take
/// ~4000px photos; 1600px still looks sharp full-screen on a phone at a
/// fraction of the upload, the download and the memory to decode it.
const double uploadImageMaxSide = 1600;

/// The same for profile pictures, which only ever show as a small avatar.
const double avatarImageMaxSide = 512;

/// A [CachedNetworkImage] decoded at about the size it is shown. Photos
/// uploaded before [uploadImageMaxSide] were decoded at full size into every
/// grid tile and thumbnail, which made scrolling slow and risked running
/// low-end Android phones out of memory. The cached file stays full size for
/// the zoomable gallery.
class SizedNetworkImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit? fit;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;

  const SizedNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => CachedNetworkImage(
        imageUrl: imageUrl,
        fit: fit,
        placeholder: placeholder,
        errorWidget: errorWidget,
        memCacheWidth: decodeWidth(context, constraints.maxWidth),
      ),
    );
  }
}

/// Pixel width to decode an image shown [logicalWidth] wide. The extra half
/// keeps landscape photos sharp when they are cropped to cover a square.
int? decodeWidth(BuildContext context, double logicalWidth) {
  if (!logicalWidth.isFinite || logicalWidth <= 0) return null;
  return (logicalWidth * MediaQuery.devicePixelRatioOf(context) * 1.5).ceil();
}
