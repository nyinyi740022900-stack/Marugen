/// Where a home banner leads when tapped, as the owner chooses it in the
/// admin form. Stored in `home_banners.link_url` as an in-app path
/// (`/product/<id>`, `/faq`) or an `https://` address; null is no link.
enum BannerLinkKind {
  none('Nothing'),
  product('A product'),
  faq('FAQ'),
  web('Web address'),

  /// A hand-typed in-app path saved before the choices existed. Only
  /// offered when a banner already has one.
  appPage('App page');

  final String label;
  const BannerLinkKind(this.label);
}

const faqBannerLink = '/faq';

String productBannerLink(String productId) => '/product/$productId';

/// The product id in a `/product/<id>` link, else null.
String? productIdFromBannerLink(String? link) {
  if (link == null) return null;
  final uri = Uri.tryParse(link.trim());
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  final segments = uri.pathSegments;
  if (!link.trim().startsWith('/') ||
      segments.length != 2 ||
      segments[0] != 'product' ||
      segments[1].isEmpty) {
    return null;
  }
  return segments[1];
}

/// Which choice a saved value belongs to, so old banners open on the right
/// one.
BannerLinkKind bannerLinkKindOf(String? saved) {
  final value = saved?.trim() ?? '';
  if (value.isEmpty) return BannerLinkKind.none;
  if (value == faqBannerLink) return BannerLinkKind.faq;
  if (productIdFromBannerLink(value) != null) return BannerLinkKind.product;
  final lower = value.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return BannerLinkKind.web;
  }
  return BannerLinkKind.appPage;
}

/// Customer pages a banner may open, as route patterns from
/// `app_router.dart` (a test keeps the two in step). Sign-in, checkout,
/// single orders and the admin app are left out on purpose: a banner is
/// shown to everyone, guests included. `/` is left out because the banner
/// already sits on it.
const bannerLinkRoutePatterns = [
  '/product/:id',
  '/faq',
  '/cart',
  '/wishlist',
  '/notifications',
  '/terms',
  '/privacy',
];

/// True when [path] is an in-app path that matches one of
/// [bannerLinkRoutePatterns]. A query string is allowed and ignored.
bool isKnownBannerRoute(String path) {
  final value = path.trim();
  if (!value.startsWith('/') || value.startsWith('//')) return false;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return false;
  final segments = uri.pathSegments;
  for (final pattern in bannerLinkRoutePatterns) {
    final parts = Uri.parse(pattern).pathSegments;
    if (parts.length != segments.length) continue;
    var matches = true;
    for (var i = 0; i < parts.length; i++) {
      final ok = parts[i].startsWith(':')
          ? segments[i].isNotEmpty
          : parts[i] == segments[i];
      if (!ok) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

/// Null when [value] is a usable `https://` address.
String? bannerWebAddressError(String value) {
  final text = value.trim();
  if (text.isEmpty) return 'Enter a web address starting with https://';
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) {
    return 'The web address must start with https://';
  }
  return null;
}

/// Null when [value] is an in-app path the router knows.
String? bannerAppPageError(String value) {
  final text = value.trim();
  if (text.isEmpty) return 'Enter an app page, or choose another link.';
  if (!isKnownBannerRoute(text)) {
    return 'That page does not exist in the app. Choose a product or FAQ '
        'instead.';
  }
  return null;
}
