import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/shared/models/order.dart';

import 'delivery_workflow_test.dart' as delivery;

Order splitOrder({
  List<Map<String, dynamic>> parcels = const [],
  bool legacy = false,
}) => Order.fromMap({
  'id': 'o',
  'user_id': 'buyer',
  'order_number': 'BOX-001',
  'status': 'packing',
  'total': 25,
  'created_at': '2026-10-19T01:00:00Z',
  'fulfillment_method': 'courier',
  'tracking_provider': legacy ? 'easyparcel' : null,
  'tracking_registered': legacy,
  'qxpress_tracking_no': legacy ? 'EPSAMPLE123' : null,
  'buyer_shipping_cents': 200,
  'total_shipping_cents': 400,
  'shipping_address': {
    'recipient_name': 'Buyer',
    'phone': '81234567',
    'line1': '12 Test Road',
    'postal_code': '808735',
    'city': 'Singapore',
  },
  'items': [
    {
      'id': 'line-1',
      'product_id': 'p',
      'product_name': 'Water care',
      'quantity': 2,
      'unit_price': 10,
      'product_category': 'accessories',
    },
  ],
  'parcels': parcels,
});
Map<String, dynamic> box(int n, String state) => {
  'id': 'box-$n',
  'order_id': 'o',
  'parcel_number': n,
  'state': state,
  'weight_kg': 0.5,
  'length_cm': 20,
  'width_cm': 10,
  'height_cm': 8,
  'collection_date': '2099-10-24',
  'items': [
    {'order_item_id': 'line-1', 'quantity': 1},
  ],
  'tracking_number': 'REAL$n',
};

class ParcelCourier extends delivery.CourierRepository {
  final List<Map<String, dynamic>> rows;
  Map<String, dynamic>? saved;
  int bookings = 0;
  int? approved;
  String? approvedSignature;
  ParcelCourier({List<Map<String, dynamic>>? parcels}) : rows = parcels ?? [];
  @override
  Future<Map<String, dynamic>> parcelAction(
    String action,
    String orderId, {
    Map<String, dynamic> data = const {},
  }) async {
    if (action == 'save_plan') {
      saved = data;
      return {
        'parcels': (data['parcels'] as List)
            .asMap()
            .entries
            .map(
              (e) => {
                ...(e.value as Map),
                'id': 'box-${e.key + 1}',
                'parcel_number': e.key + 1,
                'state': 'draft',
              },
            )
            .toList(),
      };
    }
    if (action == 'book') {
      bookings++;
      approved = data['approved_total_cents'] as int;
      approvedSignature = data['approved_quote_signature'] as String;
      for (final row in rows) {
        row['state'] = 'booked';
      }
    }
    return {
      'parcels': rows,
      'items': [
        {
          'order_item_id': 'line-1',
          'product_name': 'Water care',
          'quantity': 2,
          'weight_kg': 0.5,
          'packed_dimensions': {
            'length_cm': 20,
            'width_cm': 10,
            'height_cm': 8,
          },
        },
      ],
      if (action == 'quote') ...{
        'total_cents': 500,
        'quote_signature': 'reviewed-plan-A',
        'buyer_shipping_cents': 200,
        'seller_shipping_cents': 300,
        'additional_seller_cents': 100,
      },
    };
  }
}

Future<void> captureSplit(WidgetTester tester, String name) async {
  if (Platform.environment['SPLIT_CAPTURE'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('delivery-app-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    Directory('output/split-parcels').createSync(recursive: true);
    File('output/split-parcels/$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (Platform.environment['SPLIT_CAPTURE'] != '1') return;
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
  });
  testWidgets(
    'owner reviews exact extra shop cost; cancelling never books or charges customer',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rows = [box(1, 'draft'), box(2, 'draft')];
      final courier = ParcelCourier(parcels: rows);
      final order = splitOrder(parcels: rows);
      await delivery.showDelivery(tester, order, courier: courier);
      await tester.ensureVisible(find.text('Get parcel quotes'));
      await tester.tap(find.text('Get parcel quotes'));
      await tester.pumpAndSettle();
      expect(find.text('Extra shop cost: S\$1.00'), findsOneWidget);
      await tester.ensureVisible(find.text('Review & book parcels'));
      await tester.tap(find.text('Review & book parcels'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Customer already paid: S\$2.00'),
        findsOneWidget,
      );
      await captureSplit(tester, 'owner-cost-approval');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(courier.bookings, 0);
      await tester.tap(find.text('Review & book parcels'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve booking'));
      await tester.pumpAndSettle();
      expect(courier.approved, 500);
      expect(courier.approvedSignature, 'reviewed-plan-A');
      expect(courier.bookings, 1);
      expect(order.buyerShippingCents, 200);
      expect(find.text('Review & book parcels'), findsNothing);
    },
  );
  testWidgets(
    'packing plan pre-fills single unit sizes and saves each purchased unit once',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final courier = ParcelCourier();
      await delivery.showDelivery(tester, splitOrder(), courier: courier);
      await tester.ensureVisible(find.text('Split into parcels'));
      await tester.tap(find.text('Split into parcels'));
      await tester.pumpAndSettle();
      expect(find.text('Pack into parcels'), findsOneWidget);
      await captureSplit(tester, 'packing-plan');
      final list = find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Save parcel plan'),
        300,
        scrollable: list,
      );
      await tester.ensureVisible(find.text('Save parcel plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save parcel plan'));
      await tester.pumpAndSettle();
      final plan = courier.saved!['parcels'] as List;
      expect(plan.length, 2);
      expect((plan[0]['items'] as List).single['quantity'], 1);
      expect((plan[1]['items'] as List).single['quantity'], 1);
      expect(plan[0]['weight_kg'], 0.5);
      expect(plan[1]['length_cm'], 20);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'split tracking fits narrow large text without a false delivered or live label',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await delivery.showDelivery(
        tester,
        splitOrder(parcels: [box(1, 'delivered'), box(2, 'in_transit')]),
        textScale: 1.6,
      );
      await tester.ensureVisible(find.text('Parcel 2 of 2'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 of 2 parcels delivered'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureSplit(tester, 'partial-parcel-progress');
    },
  );
  test('partial delivery does not claim the whole order delivered', () {
    final order = splitOrder(
      parcels: [box(1, 'delivered'), box(2, 'in_transit')],
    );
    expect(order.fulfillmentStatusLabel, '1 of 2 parcels delivered');
    expect(order.status, OrderStatus.packing);
    expect(order.buyerShippingCents, 200);
  });
  testWidgets(
    'eligible order offers actual parcel split while existing sample claim stays protected',
    (tester) async {
      await delivery.showDelivery(tester, splitOrder());
      expect(find.text('Split into parcels'), findsOneWidget);
      await delivery.showDelivery(tester, splitOrder(legacy: true));
      expect(find.text('Split into parcels'), findsNothing);
    },
  );
  testWidgets(
    'each booked parcel exposes its own label and tracking without repricing customer',
    (tester) async {
      final rows = [
        box(1, 'booked')..['awb_url'] = 'https://carrier.example/label-1.pdf',
        box(2, 'in_transit')..['awb_url'] = 'https://carrier.example/label-2.pdf',
      ];
      final order = splitOrder(parcels: rows);
      await delivery.showDelivery(tester, order);
      expect(find.text('Print label'), findsNWidgets(2));
      expect(find.text('Tracking: REAL1'), findsOneWidget);
      expect(find.text('Tracking: REAL2'), findsOneWidget);
      expect(order.parcels.map((p) => p.awbUrl).toSet().length, 2);
      expect(order.buyerShippingCents, 200);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'multi parcel view replaces single booking actions and hides sample label',
    (tester) async {
      final first = box(1, 'booked')
        ..['tracking_number'] = 'EPSAMPLE123'
        ..['awb_url'] = 'https://example.com/sample.pdf';
      await delivery.showDelivery(
        tester,
        splitOrder(parcels: [first, box(2, 'in_transit')]),
      );
      expect(find.text('Parcel 1 of 2'), findsOneWidget);
      expect(find.text('Parcel 2 of 2'), findsOneWidget);
      expect(find.text('Ship with EasyParcel'), findsNothing);
      expect(find.text('Print label'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
