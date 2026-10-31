import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/shop/data/product_repository.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:shared_preferences/shared_preferences.dart';

Product product(String id) => Product(
  id: id,
  name: id,
  category: ProductCategory.accessories,
  price: 10,
  stockQuantity: 5,
);

class Catalogue implements ProductRepository {
  bool offline = false;
  @override
  Future<Product?> fetchProductById(String id) async {
    if (offline) throw const SocketException('offline');
    return product(id);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

String line(String id) => jsonEncode([
  {'product_id': id, 'variant_id': null, 'size_label': null, 'quantity': 2},
]);

Future<List<String>> savedIds(String key) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(key);
  if (raw == null) return [];
  return [
    for (final entry in jsonDecode(raw) as List)
      (entry as Map)['product_id'] as String,
  ];
}

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('opening the app offline keeps the saved cart when something new '
      'is added', () async {
    SharedPreferences.setMockInitialValues({
      'cart_items_v1::u1': line('saved-food'),
    });
    final catalogue = Catalogue()..offline = true;
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith((ref) => 'u1'),
        productRepositoryProvider.overrideWithValue(catalogue),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(cartProvider), isEmpty);
    await settle();
    container.read(cartProvider.notifier).add(product('new-food'));
    await settle();
    expect(await savedIds('cart_items_v1::u1'), ['new-food', 'saved-food']);
  });

  test('a guest cart joins the account the guest signs in to', () async {
    SharedPreferences.setMockInitialValues({
      'cart_items_v1::guest': line('guest-koi-food'),
      'cart_items_v1::u1': line('account-food'),
    });
    final account = StateProvider<String?>((ref) => null);
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith((ref) => ref.watch(account)),
        productRepositoryProvider.overrideWithValue(Catalogue()),
      ],
    );
    addTearDown(container.dispose);
    container.listen(cartProvider, (_, _) {});
    await settle();
    container.read(account.notifier).state = 'u1';
    await settle();
    expect(container.read(cartProvider).map((i) => i.product.id), [
      'account-food',
      'guest-koi-food',
    ]);
    expect(await savedIds('cart_items_v1::u1'), [
      'account-food',
      'guest-koi-food',
    ]);
    expect(await savedIds('cart_items_v1::guest'), isEmpty);
  });
}
