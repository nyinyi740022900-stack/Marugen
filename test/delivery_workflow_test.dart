import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/delivery/admin_delivery_screen.dart';
import 'package:marugen_app/features/admin/delivery/easyparcel_providers.dart';
import 'package:marugen_app/features/admin/delivery/easyparcel_repository.dart';
import 'package:marugen_app/features/admin/orders/admin_orders_screen.dart';
import 'package:marugen_app/features/orders/data/order_repository.dart';
import 'package:marugen_app/features/orders/presentation/order_status_timeline.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/shared/models/order.dart';

Order deliveryOrder({
  String method = 'courier',
  String category = 'fish_food',
  String status = 'packing',
  String? provider,
  String? tracking,
  bool registered = false,
  String? bookingState,
  String? detail,
}) => Order.fromMap({
  'id': 'order-12345',
  'order_number': 'DEL-001',
  'user_id': 'customer',
  'status': status,
  'total': 20,
  'created_at': '2026-10-19T01:00:00Z',
  'fulfillment_method': method,
  'tracking_provider': provider,
  'qxpress_tracking_no': tracking,
  'tracking_registered': registered,
  'easyparcel_booking_state': bookingState,
  'tracking_status_detail': detail,
  'easyparcel_awb_url': provider == 'easyparcel'
      ? 'https://example.com/awb.pdf'
      : null,
  'shipping_address': {
    'recipient_name': 'Daw May',
    'phone': '81234567',
    'line1': '12 Farm Road',
    'line2': '#02-03',
    'city': 'Singapore',
    'postal_code': '123456',
  },
  'customer_remarks': 'Call before delivery',
  'items': [
    {
      'product_id': 'food-1',
      'product_name': 'Koi food',
      'quantity': 2,
      'unit_price': 10,
      'product_category': category,
    },
  ],
});

class DeliveryOrders implements OrderRepository {
  final List<Order> orders;
  int writes = 0;
  DeliveryOrders(this.orders);
  @override
  Future<List<Order>> fetchAllOrders({OrderStatus? status}) async =>
      orders.where((o) => status == null || o.status == status).toList();
  @override
  Future<List<Order>> fetchFulfillmentOrders() async => orders;
  @override
  Future<List<Order>> fetchAllOrdersPage({
    OrderStatus? status,
    required int offset,
    required int limit,
  }) async => orders
      .where((o) => status == null || o.status == status)
      .skip(offset)
      .take(limit)
      .toList();
  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    writes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CourierRepository implements EasyParcelRepository {
  int quoteCalls = 0;
  ParcelDetails? quoted;
  ParcelDetails? booked;
  final rate = const EasyParcelRate(
    serviceId: 'service',
    courierName: 'J&T Express',
    price: 4,
    currency: 'SGD',
  );
  @override
  Future<List<EasyParcelRate>> getRates(
    String orderId, {
    required ParcelDetails parcel,
  }) async {
    quoteCalls++;
    quoted = parcel;
    return [
      rate,
      const EasyParcelRate(
        serviceId: 'ninja',
        courierName: 'Ninja Logistics',
        price: 6,
        currency: 'SGD',
        bookingAvailable: false,
        bookingMessage: 'Different from the prepaid service',
      ),
    ];
  }

  @override
  Future<void> bookShipment({
    required String orderId,
    required String serviceId,
    required ParcelDetails parcel,
    String? courierId,
  }) async {
    booked = parcel;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PickupCourier extends CourierRepository {
  bool fail = false;
  int checks = 0;
  @override
  Future<Map<String, dynamic>> pickupDiagnostics(String orderId) async {
    checks++;
    if (fail) throw StateError('offline');
    return {
      'reason': 'pickup_overdue',
      'title': 'Pickup date passed',
      'message': 'The scheduled date passed; the cause is not supplied.',
      'action': 'Check this existing shipment with EasyParcel.',
      'wallet': {'balance': 0, 'free_credit': 0},
      'checked_at': '2026-10-22T12:00:00Z',
      'collection_date': '2026-10-20',
    };
  }
}

Future<void> showDelivery(
  WidgetTester tester,
  Order order, {
  bool filteredEmpty = false,
  double textScale = 1,
  ThemeData? theme,
  DeliveryOrders? repository,
  EasyParcelRepository? courier,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        orderRepositoryProvider.overrideWithValue(
          repository ?? DeliveryOrders([order]),
        ),
        adminOrdersProvider.overrideWith(
          (ref) async => filteredEmpty ? [] : [order],
        ),
        easyParcelConnectedProvider.overrideWith((ref) async => true),
        if (courier != null)
          easyParcelRepositoryProvider.overrideWithValue(courier),
      ],
      child: RepaintBoundary(
        key: const ValueKey('delivery-app-preview'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme ?? AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const RepaintBoundary(
            key: ValueKey('delivery-preview'),
            child: Scaffold(body: AdminDeliveryPane()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (Platform.environment['DELIVERY_CAPTURE'] == '1') {
      final text = FontLoader('.SF Pro Text')
        ..addFont(
          File('/System/Library/Fonts/SFNS.ttf')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await text.load();
      await icons.load();
    }
  });
  testWidgets(
    'pickup check shows zero wallet without inventing cause and clears stale result on failure',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final courier = PickupCourier();
      await showDelivery(
        tester,
        deliveryOrder(
          provider: 'easyparcel',
          tracking: 'AWB123',
          registered: true,
          bookingState: 'booked',
        ),
        courier: courier,
        textScale: 1.3,
      );
      await tester.ensureVisible(find.text('Delivery details'));
      await tester.tap(find.text('Delivery details'));
      await tester.pumpAndSettle();
      final check = find.text('Check delivery details');
      await tester.ensureVisible(check);
      await tester.pumpAndSettle();
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(courier.checks, 1);
      expect(find.text('Pickup date passed'), findsOneWidget);
      expect(find.text('EasyParcel wallet: S\$0.00'), findsOneWidget);
      await tester.ensureVisible(find.text('Delivery details'));
      await tester.tap(find.text('Delivery details'));
      await tester.pumpAndSettle();
      expect(find.text('EasyParcel wallet: S\$0.00'), findsNothing);
      await tester.tap(find.text('Delivery details'));
      await tester.pumpAndSettle();
      expect(find.text('EasyParcel wallet: S\$0.00'), findsOneWidget);
      expect(find.textContaining('MYR'), findsNothing);
      expect(find.textContaining('insufficient credit'), findsNothing);
      expect(tester.takeException(), isNull);
      courier.fail = true;
      await tester.ensureVisible(check);
      await tester.pumpAndSettle();
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(find.text('Pickup date passed'), findsNothing);
      expect(find.textContaining('Could not check pickup.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sample shipment explains the problem before checking pickup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showDelivery(
      tester,
      deliveryOrder(
        provider: 'easyparcel',
        tracking: 'EPSAMPLE123',
        registered: true,
        bookingState: 'booked',
      ),
    );
    expect(find.text('Live booking required'), findsOneWidget);
    expect(find.text('Recover existing shipment'), findsNothing);
    expect(find.text('Refresh tracking'), findsNothing);
    if (Platform.environment['DELIVERY_CAPTURE'] == '1') {
      await tester.ensureVisible(find.text('Live booking required'));
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('delivery-preview')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        final dir = Directory('output/shipping-investigation')
          ..createSync(recursive: true);
        File('${dir.path}/pickup-explanation.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    expect(find.text('Check delivery details'), findsNothing);
    expect(find.text('Open EasyParcel'), findsOneWidget);
    expect(find.text('Open Shipping Label'), findsNothing);
    expect(find.textContaining('EPSAMPLE123'), findsNothing);
    await tester.ensureVisible(find.text('Delivery details'));
    await tester.tap(find.text('Delivery details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('EPSAMPLE123'), findsOneWidget);
    expect(find.text('Check delivery details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'owner booking issue code does not leak into customer tracking text',
    () {
      final order = deliveryOrder(detail: 'booking_issue:insufficient_credit');
      expect(
        order.trackingStatusDetail,
        'The shop is checking a shipping booking issue.',
      );
      expect(
        deliveryOrder(detail: 'Singapore depot').trackingStatusDetail,
        'Singapore depot',
      );
    },
  );

  test('sample AWB is attention, never a pickup confirmation', () {
    final order = deliveryOrder(
      provider: 'easyparcel',
      tracking: 'EPSAMPLE17924122984637797262',
      registered: true,
      bookingState: 'booked',
    );
    expect(order.needsBookingAttention, isTrue);
    expect(order.awaitingCourierPickup, isFalse);
  });

  testWidgets(
    'All orders directs staff to fulfillment instead of direct Delivered',
    (tester) async {
      final order = deliveryOrder();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderRepositoryProvider.overrideWithValue(DeliveryOrders([order])),
            adminOrdersProvider.overrideWith((ref) async => [order]),
            easyParcelConnectedProvider.overrideWith((ref) async => false),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const AdminOrdersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, 'Delivered'), findsNothing);
      final manage = find.widgetWithText(TextButton, 'Manage delivery');
      await tester.ensureVisible(manage);
      await tester.tap(manage);
      await tester.pumpAndSettle();
      expect(find.text('Open order'), findsOneWidget);
      expect(find.text('Mark as delivered'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'parcel measurements are required and editing invalidates quoted rates',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final courier = CourierRepository();
      await showDelivery(tester, deliveryOrder(), courier: courier);
      await tester.ensureVisible(find.text('Ship with EasyParcel'));
      await tester.tap(find.text('Ship with EasyParcel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get courier rates'));
      await tester.pumpAndSettle();
      expect(courier.quoteCalls, 0);
      for (final entry in {
        'Weight (kg)': '2',
        'Length (cm)': '30',
        'Width (cm)': '20',
        'Height (cm)': '10',
      }.entries) {
        await tester.enterText(
          find.widgetWithText(TextFormField, entry.key),
          entry.value,
        );
      }
      await tester.tap(find.text('Choose pickup date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get courier rates'));
      await tester.pumpAndSettle();
      expect(courier.quoteCalls, 1);
      expect(find.text('Ninja Logistics'), findsOneWidget);
      expect(find.textContaining('S\$4.00 total delivery'), findsOneWidget);
      expect(find.textContaining('MYR'), findsNothing);
      await tester.tap(find.text('J&T Express'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Weight (kg)'),
        '2.5',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Book Shipment'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Get courier rates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('J&T Express'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book Shipment'));
      await tester.pumpAndSettle();
      expect(courier.booked, same(courier.quoted));
      expect(courier.booked!.weightKg, 2.5);
      expect(courier.booked!.lengthCm, 30);
      expect(tester.takeException(), isNull);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'delivery fits narrow ${dark ? 'dark' : 'light'} phone and large text',
      (tester) async {
        tester.view.physicalSize = Size(dark ? 320 : 390, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await showDelivery(
          tester,
          deliveryOrder(),
          theme: dark ? AppTheme.dark : AppTheme.light,
          textScale: dark ? 1.6 : 1,
        );
        expect(tester.takeException(), isNull);
        if (Platform.environment['DELIVERY_CAPTURE'] == '1') {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('delivery-preview')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            final dir = Directory('output/delivery-review')
              ..createSync(recursive: true);
            File('${dir.path}/${dark ? 'dark' : 'light'}.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.ensureVisible(find.text('Add tracking number'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'fulfillment ignores All filter and keeps manual shipments until delivery',
    (tester) async {
      await showDelivery(
        tester,
        deliveryOrder(
          status: 'shipped',
          provider: 'seventeentrack',
          tracking: 'MANUAL-123456',
          registered: true,
        ),
        filteredEmpty: true,
      );
      expect(find.text('Order #DEL-001'), findsOneWidget);
      expect(find.textContaining('MANUAL-123456'), findsOneWidget);
    },
  );
  testWidgets(
    'staff sees recipient address items and instructions before booking',
    (tester) async {
      await showDelivery(tester, deliveryOrder());
      expect(find.textContaining('Daw May'), findsOneWidget);
      expect(find.textContaining('12 Farm Road'), findsOneWidget);
      expect(find.textContaining('Koi food'), findsOneWidget);
      expect(find.textContaining('Call before delivery'), findsOneWidget);
      expect(find.text('Open order'), findsOneWidget);
    },
  );
  testWidgets('live and mixed orders never expose courier booking', (
    tester,
  ) async {
    await showDelivery(
      tester,
      deliveryOrder(method: 'shop_delivery', category: 'koi'),
    );
    expect(find.text('Shop delivery'), findsOneWidget);
    expect(find.text('Ship with EasyParcel'), findsNothing);
    expect(find.text('Add tracking number'), findsNothing);
    expect(find.text('Start delivery'), findsOneWidget);
    expect(find.text('Mark as delivered'), findsNothing);
  });
  testWidgets('paid orders start with packing instead of shipping', (
    tester,
  ) async {
    await showDelivery(tester, deliveryOrder(status: 'paid'));
    expect(find.text('Start packing'), findsOneWidget);
    expect(find.text('Ship with EasyParcel'), findsNothing);
    expect(find.text('Mark as delivered'), findsNothing);
  });
  testWidgets('unknown legacy method cannot book a courier', (tester) async {
    await showDelivery(
      tester,
      deliveryOrder(method: 'review_required', category: 'unknown'),
    );
    expect(find.textContaining('Delivery method needs review'), findsOneWidget);
    expect(find.text('Ship with EasyParcel'), findsNothing);
    expect(find.text('Add tracking number'), findsNothing);
  });
  testWidgets('uncertain booking offers recovery instead of another booking', (
    tester,
  ) async {
    await showDelivery(
      tester,
      deliveryOrder(
        provider: 'easyparcel',
        registered: true,
        bookingState: 'needs_attention',
      ),
    );
    expect(find.text('Booking needs checking'), findsOneWidget);
    expect(find.text('Recover existing shipment'), findsOneWidget);
    expect(find.text('Ship with EasyParcel'), findsNothing);
    expect(find.text('Add tracking number'), findsNothing);
  });
  testWidgets(
    'shop handover always requires confirmation and cancel writes nothing',
    (tester) async {
      final order = deliveryOrder(
        method: 'shop_delivery',
        category: 'koi',
        status: 'shipped',
      );
      final repo = DeliveryOrders([order]);
      await showDelivery(tester, order, repository: repo);
      await tester.ensureVisible(find.text('Mark as delivered'));
      await tester.tap(find.text('Mark as delivered'));
      await tester.pumpAndSettle();
      expect(find.text('Mark as delivered?'), findsOneWidget);
      expect(repo.writes, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.writes, 0);
    },
  );
  testWidgets(
    'booked courier timeline says awaiting pickup instead of collected',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: OrderStatusTimeline(
              status: OrderStatus.shipped,
              trackingProvider: 'easyparcel',
              trackingStatusCode: 7,
            ),
          ),
        ),
      );
      expect(find.text('Awaiting pickup'), findsOneWidget);
      expect(find.text('Collected'), findsNothing);
      expect(find.text('Packed'), findsNothing);
    },
  );
}
