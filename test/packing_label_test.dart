import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/features/orders/utils/packing_slip_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'packing label uses A6 paper and long orders paginate without clipping',
    () async {
      final order = Order(
        id: 'demo-order-0001',
        userId: 'demo',
        orderNumber: 'DEMO-0001',
        status: OrderStatus.shipped,
        total: 0,
        createdAt: DateTime(2026, 10, 10),
        qxpressTrackingNo: 'DEMO123456789',
        shippingAddress: {
          'recipient_name': 'Sample Customer',
          'phone': '00000000',
          'line1': '123 Sample Street',
          'line2': '#04-01',
          'city': 'Singapore',
          'postal_code': '123456',
        },
        items: List.generate(
          40,
          (i) => OrderItem(
            productId: 'demo-$i',
            productName: 'Marugen Special Mix High Growth + JPD Yamato Colour Enhancing Koi Food',
            quantity: 2,
            unitPrice: 0,
            sizeLabel: '3 kg',
          ),
        ),
      );
      final file = File('/private/tmp/marugen-label-pagination.pdf');
      await file.writeAsBytes(await buildPackingSlipPdf(order));
      final result = await Process.run('pdfinfo', [file.path]);
      expect(result.exitCode, 0);
      expect(result.stdout.toString(), contains('297.638 x 419.528'));
      final pages = RegExp(r'Pages:\s+(\d+)')
          .firstMatch(result.stdout.toString());
      expect(int.parse(pages!.group(1)!), greaterThan(1));
      final sample = Order(
        id: order.id,
        userId: order.userId,
        orderNumber: order.orderNumber,
        status: order.status,
        total: 0,
        createdAt: order.createdAt,
        qxpressTrackingNo: order.qxpressTrackingNo,
        shippingAddress: order.shippingAddress,
        items: order.items.take(1).toList(),
      );
      await File('output/pdf/marugen-packing-label-sample.pdf')
          .writeAsBytes(await buildPackingSlipPdf(sample));
    },
  );
}
