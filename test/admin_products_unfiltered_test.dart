import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/dashboard/admin_low_stock_screen.dart';
import 'package:marugen_app/features/shop/data/product_repository.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';

Product item(String id, String category, int stock) => Product.fromMap({
  'id': id,
  'name': 'Item $id',
  'category': category,
  'price': 20,
  'stock_quantity': stock,
});

/// The catalogue as the server filters it: a category narrows the result.
class Catalogue implements ProductRepository {
  final all = [
    item('kohaku', 'koi', 1),
    item('pellets', 'fish_food', 2),
    item('net', 'accessories', 40),
  ];
  bool offline = false;
  int fetches = 0;

  @override
  Future<List<Product>> fetchProducts({ProductCategory? category}) async {
    fetches++;
    if (offline) throw Exception('offline');
    return [
      for (final product in all)
        if (category == null || product.category == category) product,
    ];
  }

  @override
  Future<List<Product>> fetchProductsPage({
    ProductCategory? category,
    required int offset,
    required int limit,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> admin(Catalogue catalogue) => [
  productRepositoryProvider.overrideWithValue(catalogue),
  shopSettingsProvider.overrideWith((ref) async => <String, dynamic>{}),
];

void main() {
  test('Home product count and Low Stock ignore the Products category chip', () async {
    final container = ProviderContainer(overrides: admin(Catalogue()));
    addTearDown(container.dispose);
    final lowStock = container.listen(lowStockProductsProvider, (_, _) {});
    addTearDown(lowStock.close);

    // Staff tap "Koi" on the Products tab.
    container.read(selectedCategoryProvider.notifier).state =
        ProductCategory.koi;
    expect(await container.read(productListProvider.future), hasLength(1));

    expect(await container.read(adminAllProductsProvider.future), hasLength(3));
    expect(lowStock.read().requireValue.map((p) => p.id), ['pellets']);
  });

  testWidgets('Low Stock Retry reloads the products it is derived from', (
    tester,
  ) async {
    final catalogue = Catalogue()..offline = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: admin(catalogue),
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AdminLowStockScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);

    catalogue.offline = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Item pellets'), findsOneWidget);
  });

  testWidgets('an admin product change reloads the unfiltered list', (
    tester,
  ) async {
    final catalogue = Catalogue();
    await tester.pumpWidget(
      ProviderScope(
        overrides: admin(catalogue),
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Column(
              children: [
                Text(
                  'low ${ref.watch(lowStockProductsProvider).valueOrNull?.length}',
                ),
                TextButton(
                  onPressed: () => refreshAdminProducts(ref),
                  child: const Text('after product change'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('low 1'), findsOneWidget);

    // The net is sold down to its last two.
    catalogue.all[2] = item('net', 'accessories', 2);
    await tester.tap(find.text('after product change'));
    await tester.pumpAndSettle();
    expect(find.text('low 2'), findsOneWidget);
  });
}
