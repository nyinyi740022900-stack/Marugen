import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../../../shared/models/product.dart';
import '../../../shared/utils/price_format.dart';

final productShareServiceProvider = Provider<ProductShareService>(
  (_) => ProductShareService(),
);

/// Captured at the tap, before settings or a photo are loaded. A subsequent
/// option change must not change the product description being shared.
class ProductShareDetails {
  final String productId;
  final String name;
  final String? option;
  final String? size;
  final double? price;
  final bool needsOption;
  final String? imageUrl;

  const ProductShareDetails._({
    required this.productId,
    required this.name,
    required this.option,
    required this.size,
    required this.price,
    required this.needsOption,
    required this.imageUrl,
  });

  factory ProductShareDetails.fromProduct(
    Product product, {
    ProductVariant? variant,
    String? size,
    int imageIndex = 0,
  }) {
    // Match against the current product so a stale option never leaks a
    // different product's price into a share.
    ProductVariant? selected;
    if (variant != null) {
      for (final candidate in product.variants) {
        if (candidate.id == variant.id && candidate.productId == product.id) {
          selected = candidate;
          break;
        }
      }
    }
    final needsOption =
        product.showPrice && product.hasVariants && selected == null;
    final rawPrice = !product.showPrice
        ? null
        : product.hasVariants
        ? selected?.price
        : product.effectivePrice;
    return ProductShareDetails._(
      productId: product.id,
      name: product.name,
      option: selected?.label,
      size: product.sizeOptions.contains(size) ? size : null,
      price: rawPrice != null && rawPrice.isFinite && rawPrice >= 0
          ? rawPrice
          : null,
      needsOption: needsOption,
      imageUrl: product.imageUrls.isEmpty
          ? null
          : product.imageUrls[imageIndex.clamp(
              0,
              product.imageUrls.length - 1,
            )],
    );
  }

  String message({String? shopPhone}) {
    final description = [
      name,
      if (option != null) 'Option: $option',
      if (size != null) 'Size: $size',
      if (price != null)
        formatPrice(price!)
      else if (needsOption)
        'Select an option for price'
      else
        'Contact for price',
    ];
    final rawPhone = shopPhone?.trim() ?? '';
    // Only accept a complete international number, with optional visual
    // separators. Do not silently turn letters/extensions into another number.
    final digits = rawPhone.replaceAll(RegExp(r'[+\s().-]'), '');
    final validPhone =
        RegExp(r'^\+?[0-9\s().-]+$').hasMatch(rawPhone) &&
        RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(digits);
    final enquiry = Uri.https('wa.me', '/$digits', {
      'text':
          "Hi, I'm interested in ${description.take(3).join(', ')} (Product ID: $productId).",
    });
    return [
      'Marugen · ${description.join('\n')}',
      if (validPhone) 'Enquire with the shop: $enquiry',
      'Shop in the Marugen Android app: '
          'https://play.google.com/store/apps/details?id=com.marugen.marugen_app',
    ].join('\n\n');
  }
}

class ProductShareImage {
  final Uint8List bytes;
  final String mimeType;
  const ProductShareImage(this.bytes, this.mimeType);

  String get filename => switch (mimeType) {
    'image/png' => 'marugen-product.png',
    'image/webp' => 'marugen-product.webp',
    'image/gif' => 'marugen-product.gif',
    _ => 'marugen-product.jpg',
  };
}

/// Downloads only a small, public HTTPS image. Redirects are intentionally
/// disabled so a public catalog URL cannot redirect to a private endpoint.
class ProductShareImageLoader {
  static const _maxBytes = 5 * 1024 * 1024;
  static const _timeout = Duration(seconds: 5);
  final http.Client Function() _createClient;

  ProductShareImageLoader({http.Client Function()? createClient})
    : _createClient = createClient ?? http.Client.new;

  Future<ProductShareImage?> load(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !_isPublicHttps(uri)) return null;
    final client = _createClient();
    try {
      return await _download(client, uri).timeout(_timeout);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<ProductShareImage?> _download(http.Client client, Uri uri) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await client.send(request);
    if (response.statusCode != 200 ||
        (response.contentLength != null &&
            response.contentLength! > _maxBytes)) {
      return null;
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > _maxBytes) return null;
      bytes.add(chunk);
    }
    final data = bytes.takeBytes();
    // Check file signatures rather than trusting a content-type from a server.
    final String? mime;
    if (data.length >= 3 &&
        data[0] == 0xff &&
        data[1] == 0xd8 &&
        data[2] == 0xff) {
      mime = 'image/jpeg';
    } else if (data.length >= 8 &&
        data[0] == 137 &&
        data[1] == 80 &&
        data[2] == 78 &&
        data[3] == 71 &&
        data[4] == 13 &&
        data[5] == 10 &&
        data[6] == 26 &&
        data[7] == 10) {
      mime = 'image/png';
    } else if (data.length >= 6 &&
        String.fromCharCodes(data.sublist(0, 6))
            .startsWith(RegExp(r'GIF8[79]a'))) {
      mime = 'image/gif';
    } else if (data.length >= 12 &&
        String.fromCharCodes(data.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(data.sublist(8, 12)) == 'WEBP') {
      mime = 'image/webp';
    } else {
      mime = null;
    }
    return mime == null ? null : ProductShareImage(data, mime);
  }

  bool _isPublicHttps(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return false;
    }
    final host = uri.host.toLowerCase();
    // Public catalog images use DNS hosts. Exclude IP literals (including IPv6)
    // and single-label/local names rather than sharing private media.
    return host.contains('.') &&
        !host.contains(':') &&
        !RegExp(r'^[0-9.]+$').hasMatch(host) &&
        !host.endsWith('.localhost') &&
        !host.endsWith('.local') &&
        !host.endsWith('.internal');
  }
}

class ProductShareService {
  final Future<ProductShareImage?> Function(String) _loadImage;
  final Future<ShareResult> Function(ShareParams) _nativeShare;

  ProductShareService({
    Future<ProductShareImage?> Function(String)? loadImage,
    Future<ShareResult> Function(ShareParams)? nativeShare,
  }) : _loadImage = loadImage ?? ProductShareImageLoader().load,
       _nativeShare = nativeShare ?? SharePlus.instance.share;

  Future<void> share(
    ProductShareDetails details, {
    required Rect origin,
    String? shopPhone,
    bool Function()? isActive,
  }) async {
    ProductShareImage? image;
    if (details.imageUrl != null) {
      try {
        image = await _loadImage(details.imageUrl!);
      } catch (_) {
        // A missing/offline image must still leave a useful text share.
      }
    }
    if (isActive != null && !isActive()) return;
    await _nativeShare(
      ShareParams(
        title: details.name,
        subject: '${details.name} · Marugen',
        text: details.message(shopPhone: shopPhone),
        sharePositionOrigin: origin,
        files: image == null
            ? null
            : [XFile.fromData(image.bytes, mimeType: image.mimeType)],
        fileNameOverrides: image == null ? null : [image.filename],
      ),
    );
  }
}
