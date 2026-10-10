import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/features/orders/presentation/purchase_intent.dart';

final testUserProvider = StateProvider<String?>((ref) => null);
const item = CartItem(
  product: Product(
    id: 'selected',
    name: 'Selected product',
    category: ProductCategory.accessories,
  ),
  quantity: 3,
  selectedSize: 'M',
);

void main() {
  ProviderContainer container() => ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWith((ref) => ref.watch(testUserProvider)),
    ],
  );
  test(
    'guest selection binds once and survives sign-in without changing options',
    () {
      final c = container();
      addTearDown(c.dispose);
      final n = c.read(purchaseIntentProvider.notifier);
      final source = [item];
      final token = n.start(source);
      source.clear();
      c.read(testUserProvider.notifier).state = 'account-a';
      c.read(currentUserIdProvider);
      final selected = n.consume(token)!;
      expect(selected.single.product.id, 'selected');
      expect(selected.single.quantity, 3);
      expect(selected.single.selectedSize, 'M');
      expect(n.consume(token), isEmpty);
    },
  );
  test(
    'account switch invalidates intent instead of exposing previous selection',
    () {
      final c = container();
      addTearDown(c.dispose);
      c.read(testUserProvider.notifier).state = 'account-a';
      final n = c.read(purchaseIntentProvider.notifier);
      final token = n.start([item]);
      c.read(testUserProvider.notifier).state = 'account-b';
      c.read(currentUserIdProvider);
      expect(n.consume(token), isEmpty);
    },
  );
  test('plain cart entry clears intent and invalid token stays isolated', () {
    final c = container();
    addTearDown(c.dispose);
    final n = c.read(purchaseIntentProvider.notifier);
    final token = n.start([item]);
    expect(n.consume(null), isNull);
    expect(n.consume(token), isEmpty);
    expect(n.consume('expired'), isEmpty);
  });
  test('signup continuation encodes only safe local redirects', () {
    expect(
      Uri.parse(authRouteWithRedirect('/signup', '/checkout?intent=abc'))
          .queryParameters['redirect'],
      '/checkout?intent=abc',
    );
    expect(authRouteWithRedirect('/signup', 'https://evil.example'), '/signup');
  });
  test('redirect only accepts app destinations and preserves query', () {
    expect(safeLocalRedirect('/checkout?intent=abc'), '/checkout?intent=abc');
    for (final unsafe in [
      'https://example.com',
      '//example.com',
      '/login',
      '/signup',
      '/\\evil',
      '/unknown',
      '/checkout#evil',
    ]) {
      expect(safeLocalRedirect(unsafe), isNull, reason: unsafe);
    }
  });
  test('payment requires totals and completed promo validation', () {
    expect(
      checkoutCanPay(
        hasItems: true,
        hasAddress: true,
        totalsReady: false,
        promoLoading: false,
        processing: false,
      ),
      isFalse,
    );
    expect(
      checkoutCanPay(
        hasItems: true,
        hasAddress: true,
        totalsReady: true,
        promoLoading: true,
        processing: false,
      ),
      isFalse,
    );
    expect(
      checkoutCanPay(
        hasItems: true,
        hasAddress: true,
        totalsReady: true,
        promoLoading: false,
        processing: true,
      ),
      isFalse,
    );
    expect(
      checkoutCanPay(
        hasItems: true,
        hasAddress: true,
        totalsReady: true,
        promoLoading: false,
        processing: false,
      ),
      isTrue,
    );
  });
}
