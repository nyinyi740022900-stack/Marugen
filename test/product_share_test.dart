import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marugen_app/features/shop/presentation/product_share.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  const variant = ProductVariant(
    id: 'v1',
    productId: 'food',
    label: '5 kg',
    price: 98.8,
  );
  const food = Product(
    id: 'food',
    name: 'JPD Koi Food',
    category: ProductCategory.fishFood,
    price: 12,
    variants: [variant],
    sizeOptions: ['Small'],
    imageUrls: ['https://images.example.com/food.jpg'],
  );
  const origin = Rect.fromLTWH(20, 20, 48, 48);
  const done = ShareResult('', ShareResultStatus.dismissed);

  test('shares selected option price and encoded product enquiry, not parent price', () {
    final details = ProductShareDetails.fromProduct(
      food,
      variant: variant,
      size: 'Small',
    );
    final text = details.message(shopPhone: '+65 9123 4567');
    expect(text, contains('Option: 5 kg'));
    expect(text, contains('Size: Small'));
    expect(text, contains('S\$98.80'));
    expect(text, isNot(contains('S\$12.00')));
    final link = RegExp(r'https://wa\.me/\S+').firstMatch(text)!.group(0)!;
    final enquiry = Uri.parse(link);
    expect(enquiry.path, '/6591234567');
    expect(enquiry.queryParameters['text'], contains('JPD Koi Food'));
    expect(enquiry.queryParameters['text'], contains('food'));
    expect(enquiry.queryParameters['text'], contains('5 kg'));
    expect(
      text,
      contains(
        'https://play.google.com/store/apps/details?id=com.marugen.marugen_app',
      ),
    );
  });

  test('unselected variants never advertise the unrelated parent price', () {
    final text = ProductShareDetails.fromProduct(food).message();
    expect(text, contains('Select an option for price'));
    expect(text, isNot(contains('S\$12.00')));
  });

  test(
    'hidden or missing prices remain contact for price, with no fake zero',
    () {
      for (final product in [
        const Product(id: 'koi', name: 'Kohaku', category: ProductCategory.koi),
        const Product(
          id: 'food',
          name: 'Food',
          category: ProductCategory.fishFood,
          showPrice: false,
          price: 50,
          variants: [variant],
        ),
      ]) {
        final text = ProductShareDetails.fromProduct(
          product,
          variant: variant,
        ).message();
        expect(text, contains('Contact for price'));
        expect(text, isNot(contains('S\$')));
      }
    },
  );

  test(
    'sale price is shared and invalid phone numbers never become enquiry links',
    () {
      const product = Product(
        id: 'net',
        name: 'Net',
        category: ProductCategory.accessories,
        price: 20,
        salePrice: 15,
      );
      for (final phone in [
        '',
        'abc91234567',
        '+65',
        '000000000',
        '+65 9123 4567 ext 2',
      ]) {
        final text = ProductShareDetails.fromProduct(product)
            .message(shopPhone: phone);
        expect(text, contains('S\$15.00'));
        expect(text, isNot(contains('wa.me')));
        expect(text, contains('Marugen Android app'));
      }
    },
  );

  test(
    'stale selections and invalid prices are never presented as current offers',
    () {
      const stale = ProductVariant(
        id: 'v1',
        productId: 'food',
        label: 'Old label',
        price: 1,
      );
      final current = ProductShareDetails.fromProduct(
        food,
        variant: stale,
      ).message();
      expect(current, contains('Option: 5 kg'));
      expect(current, contains('S\$98.80'));
      expect(current, isNot(contains('Old label')));
      const negative = Product(
        id: 'net',
        name: 'Net',
        category: ProductCategory.accessories,
        price: -10,
      );
      expect(
        ProductShareDetails.fromProduct(negative).message(),
        contains('Contact for price'),
      );
    },
  );

  test('native sheet receives photo bytes, text and iPad anchor', () async {
    ShareParams? payload;
    final service = ProductShareService(
      loadImage: (_) async =>
          ProductShareImage(Uint8List.fromList([1, 2, 3]), 'image/jpeg'),
      nativeShare: (params) async {
        payload = params;
        return done;
      },
    );
    await service.share(
      ProductShareDetails.fromProduct(food, variant: variant),
      origin: origin,
    );
    expect(payload!.text, contains('S\$98.80'));
    expect(payload!.sharePositionOrigin, origin);
    expect(await payload!.files!.single.readAsBytes(), [1, 2, 3]);
    expect(payload!.fileNameOverrides, ['marugen-product.jpg']);
  });

  test('image download errors gracefully share text', () async {
    ShareParams? payload;
    final service = ProductShareService(
      loadImage: (_) async => throw Exception('offline'),
      nativeShare: (params) async {
        payload = params;
        return done;
      },
    );
    await service.share(ProductShareDetails.fromProduct(food), origin: origin);
    expect(payload!.files, isNull);
    expect(payload!.text, contains('JPD Koi Food'));
  });

  test('native sharing errors remain recoverable by the screen', () async {
    final service = ProductShareService(
      loadImage: (_) async => null,
      nativeShare: (_) async => throw StateError('unavailable'),
    );
    await expectLater(
      service.share(ProductShareDetails.fromProduct(food), origin: origin),
      throwsStateError,
    );
  });

  test(
    'leaving during the photo download cancels the pending native sheet',
    () async {
      var shares = 0;
      final service = ProductShareService(
        loadImage: (_) async => null,
        nativeShare: (_) async {
          shares++;
          return done;
        },
      );
      await service.share(
        ProductShareDetails.fromProduct(food),
        origin: origin,
        isActive: () => false,
      );
      expect(shares, 0);
    },
  );

  test(
    'image loader refuses local URLs, oversized downloads and non-images',
    () async {
      var requests = 0;
      final loader = ProductShareImageLoader(
        createClient: () => MockClient((request) async {
          requests++;
          return http.Response(
            'not an image',
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );
      for (final value in [
        'file:///secret',
        'http://images.example.com/a.jpg',
        'https://127.0.0.1/a.jpg',
        'https://192.168.1.1/a.jpg',
        'https://localhost/a.jpg',
      ]) {
        expect(await loader.load(value), isNull);
      }
      expect(requests, 0);
      expect(await loader.load('https://images.example.com/a.jpg'), isNull);
      final oversized = ProductShareImageLoader(
        createClient: () => MockClient.streaming((request, body) async {
          return http.StreamedResponse(
            Stream.value([0xff, 0xd8, 0xff]),
            200,
            contentLength: 6 * 1024 * 1024,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );
      expect(await oversized.load('https://images.example.com/a.jpg'), isNull);
      final oversizedStream = ProductShareImageLoader(
        createClient: () => MockClient.streaming((request, body) async {
          return http.StreamedResponse(
            Stream.fromIterable([
              [0xff, 0xd8, 0xff],
              List.filled(5 * 1024 * 1024, 1),
            ]),
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );
      expect(
        await oversizedStream.load('https://images.example.com/a.jpg'),
        isNull,
      );
    },
  );

  test(
    'image loader accepts a bounded image and rejects redirect responses',
    () async {
      final loader = ProductShareImageLoader(
        createClient: () => MockClient((request) async {
          expect(request.followRedirects, isFalse);
          return http.Response.bytes(
            [0xff, 0xd8, 0xff, 0xe0],
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );
      expect(
        (await loader.load('https://images.example.com/a.jpg'))!.mimeType,
        'image/jpeg',
      );
      final redirect = ProductShareImageLoader(
        createClient: () => MockClient(
          (_) async => http.Response(
            '',
            302,
            headers: {'location': 'https://127.0.0.1/private'},
          ),
        ),
      );
      expect(await redirect.load('https://images.example.com/a.jpg'), isNull);
    },
  );
}
