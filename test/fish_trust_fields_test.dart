import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/products/admin_product_edit_screen.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/reviews/presentation/review_providers.dart';
import 'package:marugen_app/features/shop/presentation/product_detail_screen.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_providers.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:marugen_app/shared/widgets/discard_changes_guard.dart';
import 'package:marugen_app/shared/widgets/fullscreen_image_gallery.dart';
import 'package:marugen_app/shared/widgets/sized_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const certificateUrl = 'https://example.com/certificate.jpg';

/// A valid 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

class _EmptyCart extends CartNotifier {
  @override
  List<CartItem> build() => const [];
}

class _EmptyWishlist extends WishlistIdsNotifier {
  @override
  AsyncValue<Set<String>> build() => const AsyncData({});
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

void main() {
  group('FishDetails', () {
    test('reads and writes age and the certificate photo', () {
      final fish = FishDetails.fromMap({
        'variety': 'Kohaku',
        'size_cm': 45,
        'gender': 'Female',
        'breeder': 'Dainichi',
        'has_certificate': true,
        'age': ' 2 years ',
        'certificate_image_url': certificateUrl,
      });
      expect(fish.age, '2 years');
      expect(fish.certificateImageUrl, certificateUrl);
      expect(fish.viewableCertificateUrl, certificateUrl);
      expect(fish.toMap(), {
        'variety': 'Kohaku',
        'size_cm': 45.0,
        'gender': 'Female',
        'breeder': 'Dainichi',
        'has_certificate': true,
        'age': '2 years',
        'certificate_image_url': certificateUrl,
      });
    });

    test('missing, blank or mistyped values stay null and are not '
        'written', () {
      for (final stored in [
        <String, dynamic>{'variety': 'Showa'},
        <String, dynamic>{
          'variety': 'Showa',
          'age': '  ',
          'certificate_image_url': '',
        },
        <String, dynamic>{
          'variety': 'Showa',
          'age': 2,
          'certificate_image_url': ['x'],
        },
      ]) {
        final fish = FishDetails.fromMap(stored);
        expect(fish.age, isNull);
        expect(fish.certificateImageUrl, isNull);
        expect(fish.toMap().containsKey('age'), isFalse);
        expect(fish.toMap().containsKey('certificate_image_url'), isFalse);
        expect(fish.toMap().containsKey('gender'), isFalse);
      }
    });

    test('keys this app does not know survive a round trip', () {
      final fish = FishDetails.fromMap({
        'variety': 'Sanke',
        'lineage': 'Matsunosuke',
        'tank': {'no': 4},
      });
      expect(fish.toMap()['lineage'], 'Matsunosuke');
      expect(fish.toMap()['tank'], {'no': 4});
    });

    test('a certificate photo is only viewable while the fish has a '
        'certificate', () {
      const fish = FishDetails(certificateImageUrl: certificateUrl);
      expect(fish.viewableCertificateUrl, isNull);
    });

    test('age alone gives a single fish a details section, not a batch', () {
      const fish = FishDetails(age: 'Tosai');
      expect(fish.hasAnyDetail(singleFish: true), isTrue);
      expect(fish.hasAnyDetail(singleFish: false), isFalse);
    });
  });

  group('product page', () {
    Product koi({
      FishDetails? fish,
      List<ProductVariant> variants = const [],
    }) => Product(
      id: 'p',
      name: 'Kohaku',
      category: ProductCategory.koi,
      price: 300,
      stockQuantity: 1,
      fishDetails: fish,
      variants: variants,
    );

    Future<void> show(
      WidgetTester tester,
      Product product, {
      double scale = 1,
    }) async {
      tester.view.physicalSize = const Size(400, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWith((ref) => null),
            isLoggedInProvider.overrideWith((ref) => false),
            cartProvider.overrideWith(_EmptyCart.new),
            wishlistProductIdsProvider.overrideWith(_EmptyWishlist.new),
            shopSettingsProvider.overrideWith((ref) async => {}),
            productDetailProvider('p').overrideWith((ref) async => product),
            relatedProductsProvider((
              id: 'p',
              category: product.category,
            )).overrideWith((ref) async => []),
            productReviewsProvider('p').overrideWith((ref) async => []),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const ProductDetailScreen(productId: 'p'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets('a single fish shows its age, and the certificate row opens '
          'the photo (text scale $scale)', (tester) async {
        final handle = tester.ensureSemantics();
        await show(
          tester,
          koi(
            fish: const FishDetails(
              variety: 'Kohaku',
              hasCertificate: true,
              age: '2 years',
              certificateImageUrl: certificateUrl,
            ),
          ),
          scale: scale,
        );
        expect(find.text('Age'), findsOneWidget);
        expect(find.text('2 years'), findsOneWidget);
        expect(find.text('Included'), findsOneWidget);
        expect(find.text('View certificate'), findsOneWidget);
        final row = find.bySemanticsLabel(
          'Certificate included. View certificate photo',
        );
        expect(row, findsOneWidget);
        expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('View certificate'));
        // The viewer's loading spinner never settles without a network.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final gallery = tester.widget<FullscreenImageGallery>(
          find.byType(FullscreenImageGallery),
        );
        expect(gallery.imageUrls, [certificateUrl]);
        handle.dispose();
      });
    }

    testWidgets('without a photo the certificate row is the plain text it '
        'was', (tester) async {
      await show(
        tester,
        koi(fish: const FishDetails(variety: 'Kohaku', hasCertificate: true)),
      );
      expect(find.text('Included'), findsOneWidget);
      expect(find.text('View certificate'), findsNothing);
      expect(find.text('Age'), findsNothing);
      await tester.tap(find.text('Included'));
      await tester.pumpAndSettle();
      expect(find.byType(FullscreenImageGallery), findsNothing);
    });

    testWidgets('a photo left behind on a fish with no certificate is not '
        'offered', (tester) async {
      await show(
        tester,
        koi(
          fish: const FishDetails(
            variety: 'Kohaku',
            certificateImageUrl: certificateUrl,
          ),
        ),
      );
      expect(find.text('Certificate'), findsNothing);
      expect(find.text('View certificate'), findsNothing);
    });

    testWidgets('a batch listing shows neither the age nor the certificate '
        'photo', (tester) async {
      const option = ProductVariant(
        id: 'v1',
        productId: 'p',
        label: 'Kohaku A',
        price: 300,
        stockQuantity: 1,
      );
      await show(
        tester,
        koi(
          fish: const FishDetails(
            variety: 'Mixed',
            hasCertificate: true,
            age: '2 years',
            certificateImageUrl: certificateUrl,
          ),
          variants: const [option],
        ),
      );
      expect(find.text('CHOOSE FISH'), findsOneWidget);
      expect(find.text('Variety'), findsOneWidget);
      expect(find.text('Age'), findsNothing);
      expect(find.text('2 years'), findsNothing);
      expect(find.text('Included'), findsOneWidget);
      expect(find.text('View certificate'), findsNothing);
    });

    testWidgets('age alone does not leave an empty details card on a batch '
        'listing', (tester) async {
      await show(
        tester,
        koi(
          fish: const FishDetails(age: '2 years'),
          variants: const [
            ProductVariant(
              id: 'v1',
              productId: 'p',
              label: 'Kohaku A',
              price: 300,
              stockQuantity: 1,
            ),
          ],
        ),
      );
      expect(find.text('CHOOSE FISH'), findsOneWidget);
      expect(find.text('DETAILS'), findsNothing);
      expect(find.text('2 years'), findsNothing);
    });
  });

  group('admin product editor', () {
    late Map<String, dynamic> storedFish;
    late List<Map<String, dynamic>> storedVariants;
    late bool failUpload;
    late List<http.Request> uploads;
    late List<Map<String, dynamic>> productWrites;
    late File pngFile;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      pngFile = File(
        '${Directory.systemTemp.createTempSync('fish_cert').path}/cert.png',
      )..writeAsBytesSync(_png);
      await Supabase.initialize(
        url: 'https://fish.invalid',
        publishableKey: 'test-key',
        httpClient: MockClient((request) async {
          http.Response json(Object body, [int status = 200]) => http.Response(
            jsonEncode(body),
            status,
            headers: {'content-type': 'application/json'},
            request: request,
          );
          final path = request.url.path;
          if (path.startsWith('/storage/v1/object/')) {
            uploads.add(request);
            return failUpload
                ? json({'message': 'boom', 'statusCode': '500'}, 500)
                : json({'Key': path, 'Id': '1'});
          }
          if (request.method == 'GET') {
            if (path.endsWith('/products')) {
              return json({
                'id': 'fish-1',
                'name': 'Kohaku 45cm',
                'category': 'koi',
                'stock_quantity': 1,
                'price': 300,
                'fish_details': storedFish,
              });
            }
            if (path.endsWith('/product_variants')) return json(storedVariants);
            return json([]);
          }
          if (path.endsWith('/products')) {
            productWrites.add(
              (jsonDecode(request.body) as Map).cast<String, dynamic>(),
            );
          }
          return json([]);
        }),
        authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      );
    });
    tearDownAll(() => Supabase.instance.dispose());

    setUp(() {
      storedFish = {
        'variety': 'Kohaku',
        'size_cm': 45,
        'gender': 'Female',
        'breeder': 'Dainichi',
        'has_certificate': true,
        'age': '2 years',
        'certificate_image_url': certificateUrl,
        'lineage': 'Matsunosuke',
      };
      storedVariants = [];
      failUpload = false;
      uploads = [];
      productWrites = [];
    });

    Future<void> open(WidgetTester tester, {XFile? picked}) async {
      tester.view.physicalSize = const Size(500, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => context.push('/edit'),
                child: const Text('open editor'),
              ),
            ),
          ),
          GoRoute(
            path: '/edit',
            builder: (_, _) => AdminProductEditScreen(
              productId: 'fish-1',
              certificatePicker: () async => picked,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.tap(find.text('open editor'));
      await tester.pumpAndSettle();
    }

    // The product photo strip has the same add tile, above this one.
    final addCertificate = find.byIcon(Icons.add_a_photo_outlined).last;

    bool dirty(WidgetTester tester) => tester
        .widget<DiscardChangesGuard>(find.byType(DiscardChangesGuard))
        .dirty;

    /// Saves and returns the fish details of the last product write.
    Future<Map<String, dynamic>> save(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();
      return (productWrites.last['fish_details'] as Map)
          .cast<String, dynamic>();
    }

    testWidgets('editing the age keeps every other stored key, including '
        'ones the form has no field for', (tester) async {
      await open(tester);
      expect(tester.widget<TextField>(field('Age')).controller!.text, '2 years');
      expect(find.text('Certificate photo'), findsOneWidget);
      expect(dirty(tester), isFalse);

      await tester.enterText(field('Age'), 'Tosai');
      await tester.pump();
      expect(dirty(tester), isTrue);

      expect(await save(tester), {
        'variety': 'Kohaku',
        'size_cm': 45.0,
        'gender': 'Female',
        'breeder': 'Dainichi',
        'has_certificate': true,
        'age': 'Tosai',
        'certificate_image_url': certificateUrl,
        'lineage': 'Matsunosuke',
      });
      // Saved: back on the screen the editor was opened from.
      expect(find.text('open editor'), findsOneWidget);
      expect(uploads, isEmpty);
    });

    testWidgets('age is limited to ${FishDetails.maxAgeLength} characters '
        'and clearing it removes the key', (tester) async {
      await open(tester);
      await tester.enterText(field('Age'), 'x' * 50);
      await tester.pump();
      expect(
        tester.widget<TextField>(field('Age')).controller!.text.length,
        FishDetails.maxAgeLength,
      );
      await tester.enterText(field('Age'), '');
      await tester.pump();
      expect((await save(tester)).containsKey('age'), isFalse);
    });

    testWidgets('removing the certificate photo clears its key and counts '
        'as an unsaved change', (tester) async {
      await open(tester);
      await tester.tap(find.byType(SizedNetworkImage));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      expect(find.byType(SizedNetworkImage), findsNothing);
      expect(find.text('Optional. Customers can open it from the product page.'), findsOneWidget);
      expect(dirty(tester), isTrue);

      final fish = await save(tester);
      expect(fish.containsKey('certificate_image_url'), isFalse);
      expect(fish['has_certificate'], isTrue);
      expect(fish['age'], '2 years');
    });

    testWidgets('switching the certificate off hides the picker and drops '
        'the photo on save', (tester) async {
      await open(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Has certificate'));
      await tester.pumpAndSettle();
      expect(find.text('Certificate photo'), findsNothing);
      expect(dirty(tester), isTrue);

      final fish = await save(tester);
      expect(fish['has_certificate'], isFalse);
      expect(fish.containsKey('certificate_image_url'), isFalse);
    });

    testWidgets('a picked certificate photo uploads on save as an image and '
        'its link is stored', (tester) async {
      storedFish = {'variety': 'Kohaku', 'has_certificate': true};
      await open(
        tester,
        picked: XFile.fromData(
          Uint8List.fromList(_png),
          name: 'cert.png',
          path: pngFile.path,
        ),
      );
      expect(field('Age'), findsOneWidget);
      Finder labelled(String label) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == label,
      );
      expect(labelled('Add certificate photo'), findsOneWidget);
      await tester.tap(addCertificate);
      await tester.pumpAndSettle();
      expect(labelled('Certificate photo'), findsOneWidget);
      expect(find.text('Uploads when you save.'), findsOneWidget);
      expect(dirty(tester), isTrue);
      expect(uploads, isEmpty);

      final fish = await save(tester);
      final upload = uploads.single;
      expect(
        upload.url.path,
        startsWith('/storage/v1/object/product-images/products/fish-1/'),
      );
      expect(upload.url.path, endsWith('.png'));
      // Sent as an image (the bucket refuses anything else), not as
      // application/octet-stream.
      final sent = latin1.decode(upload.bodyBytes).toLowerCase();
      expect(sent, contains('content-type: image/png'));
      expect(sent, isNot(contains('octet-stream')));
      expect(
        fish['certificate_image_url'],
        contains('/product-images/products/fish-1/'),
      );
      expect(find.text('open editor'), findsOneWidget);
    });

    testWidgets('a failed certificate upload keeps the form open, says so '
        'and stores no link', (tester) async {
      storedFish = {'variety': 'Kohaku', 'has_certificate': true};
      failUpload = true;
      await open(
        tester,
        picked: XFile.fromData(
          Uint8List.fromList(_png),
          name: 'cert.png',
          path: pngFile.path,
        ),
      );
      await tester.tap(addCertificate);
      await tester.pumpAndSettle();

      final fish = await save(tester);
      expect(fish.containsKey('certificate_image_url'), isFalse);
      expect(
        find.text(
          "The certificate photo didn't upload. Tap it to retry, then Save.",
        ),
        findsOneWidget,
      );
      expect(find.text("Didn't upload. Tap the photo to retry."), findsOneWidget);
      expect(find.text('open editor'), findsNothing);
      expect(find.textContaining('boom'), findsNothing);

      // Retry from the photo's own menu, then save again.
      failUpload = false;
      await tester.tap(find.byType(Image).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry upload'));
      await tester.pumpAndSettle();
      expect(uploads, hasLength(2));
      expect(
        (await save(tester))['certificate_image_url'],
        contains('/product-images/products/fish-1/'),
      );
    });

    testWidgets('a batch listing hides both fields and leaves what is '
        'stored alone', (tester) async {
      storedVariants = [
        {
          'id': 'v1',
          'product_id': 'fish-1',
          'label': 'Kohaku A',
          'price': 300,
          'stock_quantity': 1,
        },
      ];
      await open(tester);
      expect(field('Age'), findsNothing);
      expect(find.text('Certificate photo'), findsNothing);
      expect(
        find.textContaining('are not used for a listing with fish options'),
        findsOneWidget,
      );
      expect(field('Size (cm)'), findsOneWidget);

      await tester.enterText(field('Breeder / Farm'), 'Sakai');
      await tester.pump();
      final fish = await save(tester);
      expect(fish['breeder'], 'Sakai');
      expect(fish['age'], '2 years');
      expect(fish['certificate_image_url'], certificateUrl);
      expect(fish['lineage'], 'Matsunosuke');
    });
  });
}
