import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/presentation/cart_providers.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProviderContainer container;
  final product = Product.fromMap({
    'id': 'food',
    'name': 'Koi food',
    'category': 'fish_food',
    'price': 20,
    'stock_quantity': 5,
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer(
      overrides: [currentUserIdProvider.overrideWithValue('customer-a')],
    );
  });
  tearDown(() => container.dispose());

  test('Undo restores only the removed line and its quantity', () {
    final cart = container.read(cartProvider.notifier);
    cart.add(product, quantity: 3);
    final removed = container.read(cartProvider).single;
    cart.remove(product.id);
    expect(cart.restoreRemoved(removed, ownerId: 'customer-a'), isTrue);
    expect(container.read(cartProvider).single.quantity, 3);
  });

  test('Undo cannot restore another customer cart line', () {
    final cart = container.read(cartProvider.notifier);
    cart.add(product);
    final removed = container.read(cartProvider).single;
    cart.remove(product.id);
    expect(cart.restoreRemoved(removed, ownerId: 'customer-b'), isFalse);
    expect(container.read(cartProvider), isEmpty);
  });

  test('Undo does not duplicate or overwrite an item re-added later', () {
    final cart = container.read(cartProvider.notifier);
    cart.add(product, quantity: 3);
    final removed = container.read(cartProvider).single;
    cart.remove(product.id);
    cart.add(product);
    expect(cart.restoreRemoved(removed, ownerId: 'customer-a'), isFalse);
    expect(container.read(cartProvider).single.quantity, 1);
  });
}
