import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/products/admin_product_edit_screen.dart';
import 'package:marugen_app/features/admin/orders/admin_orders_screen.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/admin/delivery/easyparcel_providers.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/orders/presentation/order_detail_screen.dart';
import 'package:marugen_app/features/orders/presentation/order_status_timeline.dart';

import 'delivery_workflow_test.dart' show DeliveryOrders, deliveryOrder;

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
final capture = Platform.environment['FINAL_PRODUCT_CAPTURE'] == '1';
Future<void> shot(WidgetTester tester, String name) async {
  if (!capture) return;
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ImageByteFormat.png);
    final file = File('output/ui-final-product-order/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

ThemeData captureTheme(Brightness brightness) {
  final theme = brightness == Brightness.dark ? AppTheme.dark : AppTheme.light;
  if (!capture) return theme;
  return theme.copyWith(
    chipTheme: theme.chipTheme.copyWith(
      labelStyle: theme.chipTheme.labelStyle?.copyWith(
        fontFamily: '.SF Pro Text',
      ),
      secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
        fontFamily: '.SF Pro Text',
      ),
    ),
  );
}

Future<void> host(
  WidgetTester tester,
  Widget screen,
  Brightness brightness, {
  double keyboard = 0,
  double width = 320,
  double textScale = 2,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          theme: captureTheme(brightness),
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: child!,
          ),
          home: screen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  double delta = 180,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    maxScrolls: 100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

class _FailingOrders extends DeliveryOrders {
  _FailingOrders(super.orders);
  @override
  Future<void> updateOrderStatus(String id, OrderStatus status) async {
    writes++;
    throw StateError('offline');
  }
}

void main() {
  var failRead = false;
  var missing = false;
  var writes = 0;
  Completer<void>? heldWrite;
  setUp(() {
    failRead = false;
    missing = false;
    writes = 0;
    heldWrite = null;
  });
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://forms.invalid',
      publishableKey: 'test-key',
      httpClient: MockClient((request) async {
        final product = request.url.path.endsWith('/products');
        if (request.method != 'GET') {
          writes++;
          if (heldWrite != null && product) {
            await heldWrite!.future;
            return http.Response(
              '{"id":"saved-product"}',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response(
            '{"message":"Unavailable"}',
            503,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          product
              ? failRead
                    ? '{"message":"Unavailable"}'
                    : missing
                    ? 'null'
                    : jsonEncode({
                        'id': 'product-1',
                        'name': 'Premium koi food with a long product title',
                        'category': 'fish_food',
                        'stock_quantity': 10,
                        'price': 20,
                      })
              : '[]',
          product && failRead ? 503 : 200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
    if (capture) {
      await (FontLoader('.SF Pro Text')..addFont(
            File('/System/Library/Fonts/SFNS.ttf')
                .readAsBytes()
                .then((b) => ByteData.sublistView(b)),
          ))
          .load();
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          ))
          .load();
    }
  });
  tearDownAll(() => Supabase.instance.dispose());
  testWidgets('product initial failure offers recovery instead of spinner', (
    tester,
  ) async {
    failRead = true;
    await host(
      tester,
      const AdminProductEditScreen(productId: 'product-1'),
      Brightness.light,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Retry'), findsOneWidget);
    await shot(tester, 'product-load-retry');
    failRead = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(field('Name'), findsOneWidget);
    expect(
      tester.widget<TextField>(field('Name')).controller!.text,
      contains('Premium'),
    );
    expect(writes, 0);
  });
  testWidgets('missing product never exposes a blank existing-product editor', (
    tester,
  ) async {
    missing = true;
    await host(
      tester,
      const AdminProductEditScreen(productId: 'missing'),
      Brightness.dark,
    );
    expect(find.text('Product not found'), findsOneWidget);
    expect(find.byType(Form), findsNothing);
    expect(writes, 0);
  });
  testWidgets(
    'product save prevents edits and stops follow-up writes after disposal',
    (tester) async {
      heldWrite = Completer<void>();
      await host(tester, const AdminProductEditScreen(), Brightness.light);
      await tester.enterText(field('Name'), 'Fixture fish');
      await reveal(tester, find.text('Add Fish Option'));
      await tester.tap(find.text('Add Fish Option'));
      await tester.pumpAndSettle();
      await reveal(tester, field('Label'));
      await tester.enterText(field('Label'), 'Fixture option');
      await tester.enterText(field('Price'), '120');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await reveal(tester, find.widgetWithText(ElevatedButton, 'Save'));
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(writes, 1);
      final formBlock = find.ancestor(
        of: find.byType(Form),
        matching: find.byWidgetPredicate(
          (w) => w is AbsorbPointer && w.child is Form,
        ),
      );
      expect(formBlock, findsOneWidget);
      expect(tester.widget<AbsorbPointer>(formBlock).absorbing, isTrue);
      await tester.pumpWidget(const SizedBox());
      heldWrite!.complete();
      await tester.pumpAndSettle();
      expect(
        writes,
        1,
        reason: 'Disposed editor must not start variant writes',
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets('owner status failure preserves retry action $brightness', (
      tester,
    ) async {
      final order = deliveryOrder(status: 'paid');
      final repository = _FailingOrders([order]);
      await host(
        tester,
        const AdminOrdersScreen(),
        brightness,
        overrides: [
          orderRepositoryProvider.overrideWithValue(repository),
          adminOrdersProvider.overrideWith((ref) async => [order]),
          easyParcelConnectedProvider.overrideWith((ref) async => false),
        ],
      );
      final packing = find.widgetWithText(OutlinedButton, 'Packing');
      await reveal(tester, packing);
      await tester.tap(packing);
      await tester.pumpAndSettle();
      expect(repository.writes, 1);
      expect(find.text('Could not update the order status.'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(packing).onPressed, isNotNull);
      expect(find.text('Paid'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact timeline keeps pickup words readable $brightness', (
      tester,
    ) async {
      await host(
        tester,
        const Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: OrderStatusTimeline(
                status: OrderStatus.packing,
                trackingProvider: 'easyparcel',
                trackingStatusCode: 2,
              ),
            ),
          ),
        ),
        brightness,
      );
      final label = tester.renderObject<RenderParagraph>(
        find.text('Awaiting pickup'),
      );
      expect(
        label.size.height,
        lessThan(70),
        reason: 'Pickup label must use at most two readable lines, not single-letter columns',
      );
      expect(tester.takeException(), isNull);
      await shot(tester, 'timeline-pickup-$brightness');
      await host(
        tester,
        const Scaffold(
          body: OrderStatusTimeline(status: OrderStatus.cancelled),
        ),
        brightness,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'product validation long variants and keyboard save $brightness',
      (tester) async {
        await host(
          tester,
          const AdminProductEditScreen(),
          brightness,
          keyboard: 250,
        );
        final category = tester
            .widget<DropdownButtonFormField<ProductCategory>>(
              find.byType(DropdownButtonFormField<ProductCategory>),
            );
        category.onChanged!(ProductCategory.fishFood);
        await tester.pumpAndSettle();
        await tester.enterText(field('Name'), 'Premium koi food');
        await reveal(
          tester,
          find.text('Weight of one item. Example: 500g = 0.5 kg.'),
        );
        expect(
          tester
              .renderObject<RenderParagraph>(
                find.text('Weight of one item. Example: 500g = 0.5 kg.'),
              )
              .didExceedMaxLines,
          isFalse,
        );

        await reveal(tester, find.text('Add Weight'));
        await tester.tap(find.text('Add Weight'));
        await tester.pumpAndSettle();
        await reveal(tester, field('Label'));
        await tester.enterText(
          field('Label'),
          'Premium growth formula – extra large sinking pellets',
        );
        await tester.enterText(field('kg').last, '-1');
        await shot(tester, 'product-variant-fields-$brightness');

        await reveal(tester, field('Length (cm)').last);
        await tester.enterText(field('Length (cm)').last, '20');
        final form = tester.state<FormState>(find.byType(Form));
        expect(form.validate(), isFalse);
        await tester.pumpAndSettle();
        expect(find.text('Enter a positive weight in kg.'), findsOneWidget);
        expect(find.text('Enter a positive size.'), findsNWidgets(2));
        await reveal(tester, field('kg').last);
        await tester.enterText(field('kg').last, '0.5');
        await reveal(tester, field('Width (cm)').last);
        await tester.enterText(field('Width (cm)').last, '10');
        await reveal(tester, field('Height (cm)').last);
        await tester.enterText(field('Height (cm)').last, '8');
        // A labelled weight option needs its own price (no more S$0.00).
        expect(form.validate(), isFalse);
        await tester.pumpAndSettle();
        expect(find.text('Enter a price'), findsOneWidget);
        await reveal(tester, field('Price'));
        await tester.enterText(field('Price'), '18.90');
        expect(form.validate(), isTrue);
        await tester.pumpAndSettle();
        await shot(tester, 'product-variant-$brightness');
        await reveal(tester, find.widgetWithText(ElevatedButton, 'Save'));
        expect(find.text('Save').hitTestable(), findsOneWidget);
        expect(
          tester.getBottomRight(find.widgetWithText(ElevatedButton, 'Save')).dy,
          lessThanOrEqualTo(650),
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(writes, 1);
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Save'),
              )
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
        await reveal(tester, field('Label'), delta: -180);
        expect(
          tester.widget<TextField>(field('Label')).controller!.text,
          startsWith('Premium growth'),
        );
      },
    );
    testWidgets('shared owner detail pickup AWB and actions fit $brightness', (
      tester,
    ) async {
      var carrierRefreshes = 0;
      final order = Order.fromMap({
        'id': 'fixture-order',
        'order_number': 'TEST-001',
        'user_id': 'fixture-customer',
        'status': 'packing',
        'total': 20,
        'created_at': '2026-10-23T01:00:00Z',
        'fulfillment_method': 'courier',
        'tracking_provider': 'easyparcel',
        'qxpress_tracking_no': 'QSP223261096',
        'tracking_registered': true,
        'easyparcel_booking_state': 'booked',
        'tracking_status': 'To Be Collected',
        'tracking_status_code': 2,
        'tracking_status_detail': 'Waiting for courier pickup',
        'easyparcel_awb_url': 'https://example.invalid/fixture-awb.pdf',
        'shipping_address': {
          'recipient_name': 'Fixture Customer',
          'phone': '80000000',
          'line1': '12 Fixture Road',
          'city': 'Singapore',
          'postal_code': '123456',
        },
        'items': [
          {
            'product_id': 'fixture-food',
            'product_name':
                'Premium growth formula extra large sinking pellets',
            'quantity': 1,
            'unit_price': 20,
            'product_category': 'fish_food',
          },
        ],
      });
      await host(
        tester,
        const OrderDetailScreen(orderId: 'fixture-order'),
        brightness,
        overrides: [
          orderTrackingRefreshProvider.overrideWithValue((value) async {
            expect(value.id, 'fixture-order');
            carrierRefreshes++;
          }),
          authStateProvider.overrideWith((ref) => const Stream.empty()),
          currentUserIdProvider.overrideWithValue('fixture-owner'),
          currentAppUserProvider.overrideWith(
            (ref) async =>
                const AppUser(id: 'fixture-owner', role: UserRole.owner),
          ),
          orderByIdProvider('fixture-order').overrideWith((ref) async => order),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Awaiting courier pickup'), findsWidgets);
      expect(find.byTooltip('Refresh tracking'), findsNothing);
      await tester.drag(find.byType(ListView).first, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(carrierRefreshes, 1);
      await reveal(tester, find.text('Tracking: QSP223261096'));
      expect(find.text('Tracking: QSP223261096').hitTestable(), findsOneWidget);
      await shot(tester, 'owner-detail-pickup-$brightness');
      await reveal(tester, find.text('View / Download Invoice'), delta: -180);
      expect(
        find.text('View / Download Invoice').hitTestable(),
        findsOneWidget,
      );
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('View / Download Invoice'))
            .didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await shot(tester, 'owner-detail-actions-$brightness');
      await reveal(tester, find.text('SHIPPING ADDRESS'));
      await shot(tester, 'owner-detail-address-$brightness');
      await reveal(tester, find.text('Total'));
      await shot(tester, 'owner-detail-items-$brightness');
      expect(writes, 0);
    });
    testWidgets('refresh removes externally deleted orders $brightness', (
      tester,
    ) async {
      final removed = Order.fromMap({
        'id': 'removed-order',
        'order_number': 'TEST-OLD',
        'user_id': 'customer',
        'status': 'pending',
        'total': 0,
        'created_at': '2026-10-19T01:00:00Z',
      });
      final repository = DeliveryOrders([removed, deliveryOrder()]);
      await host(
        tester,
        const AdminOrdersScreen(),
        brightness,
        width: 600,
        textScale: 1,
        overrides: [
          orderRepositoryProvider.overrideWithValue(repository),
          easyParcelConnectedProvider.overrideWith((ref) async => false),
        ],
      );
      expect(find.text('Order #TEST-OLD'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AdminOrdersScreen)),
      );
      expect((await container.read(adminOrdersProvider.future)).length, 2);
      repository.orders.removeWhere((order) => order.id == removed.id);
      expect(find.byTooltip('Refresh orders'), findsNothing);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      await tester.drag(find.text('Order #TEST-OLD'), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.text('Order #TEST-OLD'), findsNothing);
      expect(find.text('Order #DEL-001'), findsOneWidget);
      expect((await container.read(adminOrdersProvider.future)).length, 1);
      expect(repository.writes, 0);
      expect(tester.takeException(), isNull);
      await shot(tester, 'order-refresh-$brightness');
    });
    testWidgets('order tabs fill available width when labels fit $brightness', (
      tester,
    ) async {
      await host(
        tester,
        const AdminOrdersScreen(),
        brightness,
        width: capture ? 390 : 600,
        textScale: 1,
        overrides: [
          orderRepositoryProvider.overrideWithValue(DeliveryOrders([])),
          adminOrdersProvider.overrideWith((ref) async => []),
          easyParcelConnectedProvider.overrideWith((ref) async => false),
        ],
      );
      final bar = tester.widget<TabBar>(find.byType(TabBar));
      expect(bar.isScrollable, isFalse);
      expect(bar.tabAlignment, TabAlignment.fill);
      final centers = ['All', 'Fulfillment', 'Payments']
          .map((label) => tester.getCenter(find.widgetWithText(Tab, label)).dx)
          .toList();
      final width = capture ? 390.0 : 600.0;
      expect(centers[0], closeTo(width / 6, 1));
      expect(centers[1], closeTo(width / 2, 1));
      expect(centers[2], closeTo(width * 5 / 6, 1));
      expect(tester.takeException(), isNull);
      await shot(tester, 'order-tabs-spaced-$brightness');
    });
    testWidgets('product delete can be dismissed without write $brightness', (
      tester,
    ) async {
      await host(
        tester,
        const AdminProductEditScreen(productId: 'product-1'),
        brightness,
      );
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('Delete product?'), findsOneWidget);
      expect(find.text('Cancel').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shot(tester, 'product-delete-$brightness');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Delete product?'), findsNothing);
      expect(writes, 0);
    });
    testWidgets(
      'owner order actions keep complete labels and cancel safely $brightness',
      (tester) async {
        final order = deliveryOrder(status: 'pending');
        final repository = DeliveryOrders([order]);
        await host(
          tester,
          const AdminOrdersScreen(),
          brightness,
          overrides: [
            orderRepositoryProvider.overrideWithValue(repository),
            adminOrdersProvider.overrideWith((ref) async => [order]),
            easyParcelConnectedProvider.overrideWith((ref) async => false),
          ],
        );
        expect(
          tester
              .renderObject<RenderParagraph>(find.text('Fulfillment'))
              .didExceedMaxLines,
          isFalse,
        );
        await reveal(tester, find.text('Print Invoice'));
        for (final label in ['Print Invoice', 'Contact Buyer']) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(label),
          );
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '$label must stay complete at 320px / 2x',
          );
        }
        expect(tester.takeException(), isNull);
        await shot(tester, 'owner-actions-$brightness');
        await tester.tap(find.widgetWithText(TextButton, 'Cancelled'));
        await tester.pumpAndSettle();
        expect(find.text('Cancel this order?'), findsOneWidget);
        expect(find.text('Cancel').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shot(tester, 'owner-cancel-$brightness');
        await tester.tap(find.text('Cancel').hitTestable());
        await tester.pumpAndSettle();
        expect(repository.writes, 0);
        expect(find.text('Cancel this order?'), findsNothing);
      },
    );
  }
}
