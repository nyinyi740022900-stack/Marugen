import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/features/shop/data/product_repository.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DelayedProducts implements ProductRepository {
  final result = Completer<Product?>();
  @override
  Future<Product?> fetchProductById(String id) => result.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final account = StateProvider<String?>((ref) => 'a');
const product = Product(
  id: 'p',
  name: 'Koi food',
  category: ProductCategory.fishFood,
  price: 10,
  stockQuantity: 5,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'An old stock refresh never puts account A items into account B',
    () async {
      final repository = DelayedProducts();
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWith((ref) => ref.watch(account)),
          productRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final cart = container.read(cartProvider.notifier);
      cart.add(product);
      final refresh = cart.refreshFromServer();
      container.read(account.notifier).state = 'b';
      expect(container.read(cartProvider), isEmpty);
      repository.result.complete(product);
      await refresh;
      expect(container.read(cartProvider), isEmpty);
    },
  );

  test(
    'A stock refresh never resurrects an item removed while waiting',
    () async {
      final repository = DelayedProducts();
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('a'),
          productRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final cart = container.read(cartProvider.notifier);
      cart.add(product);
      final refresh = cart.refreshFromServer();
      cart.remove(product.id);
      repository.result.complete(product);
      await refresh;
      expect(container.read(cartProvider), isEmpty);
    },
  );
}
