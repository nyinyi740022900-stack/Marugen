import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/shared/models/product.dart';

void main() {
  group('Product.sizeOptions', () {
    test('parses size_options from map', () {
      final product = Product.fromMap({
        'id': 'p1',
        'name': 'JPD Mixed Koi Food',
        'category': 'fish_food',
        'size_options': ['Small', 'Medium', 'Large'],
      });

      expect(product.sizeOptions, ['Small', 'Medium', 'Large']);
      expect(product.hasSizeOptions, isTrue);
    });

    test('defaults to empty when size_options missing', () {
      final product = Product.fromMap({
        'id': 'p1',
        'name': 'Food',
        'category': 'fish_food',
      });

      expect(product.sizeOptions, isEmpty);
      expect(product.hasSizeOptions, isFalse);
    });
  });

  group('ProductVariant.sizeStocks', () {
    test('parses nested size_stocks and reports combo stock', () {
      final variant = ProductVariant.fromMap({
        'id': 'v1',
        'product_id': 'p1',
        'label': '5kg',
        'price': 98.8,
        'stock_quantity': 99,
        'size_stocks': [
          {'size_label': 'Small', 'stock_quantity': 10},
          {'size_label': 'Large', 'stock_quantity': 3},
        ],
      });

      expect(variant.usesSizeStocks, isTrue);
      expect(variant.stockForSize('Small'), 10);
      expect(variant.stockForSize('Large'), 3);
      expect(variant.stockForSize('Medium'), 0);
      // Combo stock ignores the legacy weight-level stock_quantity.
      expect(variant.effectiveStock, 13);
    });

    test('falls back to stock_quantity when no size stocks', () {
      final variant = ProductVariant.fromMap({
        'id': 'v1',
        'product_id': 'p1',
        'label': '5kg',
        'price': 98.8,
        'stock_quantity': 7,
      });

      expect(variant.usesSizeStocks, isFalse);
      expect(variant.stockForSize(null), 7);
      expect(variant.effectiveStock, 7);
    });
  });

  group('Product.availableStock with size matrix', () {
    test('sums weight×size stocks when size options exist', () {
      final product = Product.fromMap({
        'id': 'p1',
        'name': 'Food',
        'category': 'fish_food',
        'size_options': ['Small', 'Large'],
        'variants': [
          {
            'id': 'v1',
            'product_id': 'p1',
            'label': '5kg',
            'price': 98.8,
            'stock_quantity': 0,
            'size_stocks': [
              {'size_label': 'Small', 'stock_quantity': 10},
              {'size_label': 'Large', 'stock_quantity': 0},
            ],
          },
          {
            'id': 'v2',
            'product_id': 'p1',
            'label': '10kg',
            'price': 180,
            'stock_quantity': 0,
            'size_stocks': [
              {'size_label': 'Small', 'stock_quantity': 2},
            ],
          },
        ],
      });

      expect(product.availableStock, 12);
      expect(product.isOutOfStock, isFalse);
      expect(product.stockFor(variantId: 'v1', size: 'Large'), 0);
      expect(product.stockFor(variantId: 'v1', size: 'Small'), 10);
    });
  });

  group('CartItem.lineKey', () {
    final product = Product.fromMap({
      'id': 'p1',
      'name': 'Food',
      'category': 'fish_food',
      'size_options': ['Small', 'Large'],
      'variants': [
        {
          'id': 'v1',
          'product_id': 'p1',
          'label': '5kg',
          'price': 98.8,
          'stock_quantity': 10,
          'size_stocks': [
            {'size_label': 'Small', 'stock_quantity': 4},
            {'size_label': 'Large', 'stock_quantity': 6},
          ],
        },
      ],
    });

    test('includes selected size so different sizes are separate lines', () {
      final a = CartItem(
        product: product,
        selectedVariant: product.variants.first,
        selectedSize: 'Small',
      );
      final b = CartItem(
        product: product,
        selectedVariant: product.variants.first,
        selectedSize: 'Large',
      );

      expect(a.lineKey, isNot(equals(b.lineKey)));
      expect(a.lineKey, contains('Small'));
      expect(b.lineKey, contains('Large'));
    });
  });
}
