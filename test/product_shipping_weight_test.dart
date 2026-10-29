import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/shared/models/product.dart';

void main() {
  test(
    'packed dimensions survive product copies and reject partial measurements',
    () {
      final product = Product.fromMap({
        'id': 'p',
        'packed_dimensions': {'length_cm': 20, 'width_cm': 10, 'height_cm': 8},
        'variants': [
          {
            'id': 'v',
            'product_id': 'p',
            'packed_dimensions': {
              'length_cm': 30,
              'width_cm': 15,
              'height_cm': 12,
            },
          },
        ],
      });
      expect(product.packedDimensions?.toMap(), {
        'length_cm': 20.0,
        'width_cm': 10.0,
        'height_cm': 8.0,
      });
      expect(product.variants.single.packedDimensions?.lengthCm, 30);
      expect(
        product
            .withStats(soldCount: 1, reviewCount: 0)
            .packedDimensions
            ?.heightCm,
        8,
      );
      expect(product.copyWithVariants([]).packedDimensions?.widthCm, 10);
      expect(PackedDimensions.fromMap({'length_cm': 20}), isNull);
      expect(
        PackedDimensions.fromMap({
          'length_cm': -1,
          'width_cm': 2,
          'height_cm': 3,
        }),
        isNull,
      );
    },
  );
  test('shipping kg survives database parsing and product copies', () {
    final product = Product.fromMap({
      'id': 'p',
      'name': 'Food',
      'category': 'fish_food',
      'shipping_weight_kg': 3,
      'variants': [
        {
          'id': 'v',
          'product_id': 'p',
          'label': '500g',
          'price': 10,
          'shipping_weight_kg': 0.5,
        },
      ],
    });
    expect(product.shippingWeightKg, 3);
    expect(product.variants.single.shippingWeightKg, 0.5);
    expect(product.withStats(soldCount: 2, reviewCount: 0).shippingWeightKg, 3);
    expect(product.copyWithVariants(product.variants).shippingWeightKg, 3);
    expect(Product.fromMap({'id': 'legacy'}).shippingWeightKg, isNull);
  });
}
