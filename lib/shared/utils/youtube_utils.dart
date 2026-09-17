/// Extracts the 11-character video id from a YouTube URL (watch, youtu.be,
/// shorts, or embed links) — used by [ProductVideoPlayer] to decide
/// whether `product.videoUrl` needs the YouTube embed player instead of a
/// direct video file. Returns null for anything that isn't recognizably a
/// YouTube link.
String? extractYoutubeId(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  final isYoutubeHost = host == 'youtu.be' ||
      host.endsWith('youtube.com') ||
      host.endsWith('youtube-nocookie.com');
  if (!isYoutubeHost) return null;

  if (host == 'youtu.be') {
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  }
  if (uri.pathSegments.isNotEmpty) {
    if (uri.pathSegments.first == 'watch') {
      return uri.queryParameters['v'];
    }
    if (uri.pathSegments.first == 'shorts' || uri.pathSegments.first == 'embed') {
      return uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
    }
  }
  return uri.queryParameters['v'];
}
