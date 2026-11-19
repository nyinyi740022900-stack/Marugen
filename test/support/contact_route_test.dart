import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/reviews/presentation/review_providers.dart';
import 'package:marugen_app/features/services/presentation/service_providers.dart';
import 'package:marugen_app/features/services/presentation/services_tab.dart';
import 'package:marugen_app/features/shop/presentation/product_detail_screen.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/models/service.dart';
import 'package:marugen_app/shared/models/support_contact.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:marugen_app/shared/widgets/product_card.dart';
import 'package:marugen_app/shared/widgets/support_contact_picker.dart';

const directory = {
  'shop_phone': '+6561110000',
  'support_contacts': [
    {
      'id': 'sales',
      'name': 'Sales desk',
      'category': 'Fish and product enquiries',
      'whatsapp': '+6588889999',
      'phone': '+6562223333',
    },
  ],
};

final koi = Product.fromMap({
  'id': 'koi',
  'name': 'Kohaku 45cm',
  'category': 'live_fish',
  'price': 500,
  'show_price': false,
  'stock_quantity': 1,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Every URL handed to the platform launcher.
  late List<String> launched;
  setUp(() {
    launched = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            if (call.method == 'launch') {
              launched.add((call.arguments as Map)['url'] as String);
            }
            return true;
          },
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          null,
        );
  });

  Future<void> show(
    WidgetTester tester,
    Widget screen, {
    Map<String, dynamic> settings = directory,
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // A guest: nothing in these messages is personal.
          currentUserIdProvider.overrideWith((ref) => null),
          isLoggedInProvider.overrideWithValue(false),
          shopSettingsProvider.overrideWith((ref) async => settings),
          ...overrides,
        ],
        child: MaterialApp(theme: AppTheme.light, home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('shop number fallback', () {
    test('an 8-digit Singapore number gets its country code', () {
      final shop = legacyShopContact({'shop_phone': '8888 9999'})!;
      expect(shop.phone, '+6588889999');
      expect(shop.whatsapp, '+6588889999');
      expect(
        supportDirectoryFromSettings({'shop_phone': '6222 3333'}).single.phone,
        '+6562223333',
      );
    });

    test('a number already in international form is kept', () {
      expect(
        legacyShopContact({'shop_phone': '+60 12-345 6789'})!.phone,
        '+60123456789',
      );
    });

    test('a missing or unusable number is no contact at all', () {
      expect(legacyShopContact({}), isNull);
      expect(legacyShopContact({'shop_phone': '  '}), isNull);
      expect(legacyShopContact({'shop_phone': 'call us'}), isNull);
    });

    testWidgets('an empty directory still reaches the shop number', (
      tester,
    ) async {
      await show(
        tester,
        const Scaffold(body: SupportContactPicker()),
        settings: {'support_contacts': <dynamic>[], 'shop_phone': '88889999'},
      );
      expect(find.text('Shop support'), findsOneWidget);
      await tester.tap(find.text('Phone'));
      await tester.pumpAndSettle();
      expect(launched.single, 'tel:+6588889999');
    });

    testWidgets('a directory that cannot be read still reaches the shop '
        'number', (tester) async {
      await show(
        tester,
        const Scaffold(body: SupportContactPicker()),
        settings: {'support_contacts': 'corrupt', 'shop_phone': '+6588889999'},
      );
      expect(find.text('Shop support'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.textContaining('unavailable'), findsNothing);
    });

    testWidgets('no directory and no number says so, with Retry', (
      tester,
    ) async {
      await show(
        tester,
        const Scaffold(body: SupportContactPicker()),
        settings: const {},
      );
      expect(find.textContaining('No support contacts'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  testWidgets('a service opens the support picker with its own message', (
    tester,
  ) async {
    await show(
      tester,
      const Scaffold(body: ServicesTab()),
      overrides: [
        servicesProvider.overrideWith(
          (ref) async => const [Service(id: 's1', name: 'Pond boarding')],
        ),
      ],
    );
    await tester.tap(find.text('Contact to book'));
    await tester.pumpAndSettle();

    // The directory picker, not a sheet built from shop_phone.
    expect(find.text('Contact Support'), findsOneWidget);
    expect(find.text('Sales desk'), findsOneWidget);
    await tester.tap(find.text('WhatsApp'));
    await tester.pumpAndSettle();
    final uri = Uri.parse(launched.single);
    expect(uri.host, 'wa.me');
    expect(uri.path, '/6588889999');
    expect(
      uri.queryParameters['text'],
      'Hi, I\'d like to ask about "Pond boarding".',
    );
  });

  testWidgets('a product card opens the support picker about that product', (
    tester,
  ) async {
    await show(
      tester,
      Scaffold(
        body: Center(
          child: SizedBox(
            width: 220,
            height: 420,
            child: ProductCard(product: koi, onTap: () {}),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Contact shop about Kohaku 45cm'));
    await tester.pumpAndSettle();
    expect(find.text('Sales desk'), findsOneWidget);
    await tester.tap(find.text('WhatsApp'));
    await tester.pumpAndSettle();
    expect(
      Uri.parse(launched.single).queryParameters['text'],
      "Hi, I'm interested in Kohaku 45cm",
    );
  });

  testWidgets('the product page opens the support picker about that product', (
    tester,
  ) async {
    await show(
      tester,
      const ProductDetailScreen(productId: 'koi'),
      overrides: [
        productDetailProvider('koi').overrideWith((ref) async => koi),
        relatedProductsProvider((
          id: 'koi',
          category: koi.category,
        )).overrideWith((ref) async => []),
        productReviewsProvider('koi').overrideWith((ref) async => []),
      ],
    );
    await tester.tap(find.text('Contact Us for Price'));
    await tester.pumpAndSettle();
    expect(find.text('Contact Support'), findsOneWidget);
    expect(find.text('Sales desk'), findsOneWidget);
    await tester.tap(find.text('WhatsApp'));
    await tester.pumpAndSettle();
    final uri = Uri.parse(launched.single);
    expect(uri.path, '/6588889999');
    expect(uri.queryParameters['text'], "Hi, I'm interested in Kohaku 45cm");
  });
}
