import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/delivery/easyparcel_providers.dart';
import 'package:marugen_app/features/admin/orders/admin_orders_screen.dart';
import 'package:marugen_app/features/admin/products/admin_product_edit_screen.dart';
import 'package:marugen_app/features/admin/products/admin_products_screen.dart';
import 'package:marugen_app/features/admin/services/admin_services_screen.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/reviews/presentation/review_providers.dart';
import 'package:marugen_app/features/reviews/presentation/reviews_section.dart';
import 'package:marugen_app/features/services/presentation/service_providers.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/models/review.dart';
import 'package:marugen_app/shared/models/service.dart';
import 'package:marugen_app/shared/providers/paged_notifier.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';

import 'delivery_workflow_test.dart' show deliveryOrder;
import 'forms_responsive_test.dart' as forms;

class _MyReview extends MyReviewNotifier {
  @override
  AsyncValue<ProductReview?> build(String arg) => AsyncData(
    ProductReview(
      id: 'r1',
      productId: arg,
      userId: 'customer',
      rating: 5,
      comment: 'Healthy fish',
      createdAt: DateTime(2026, 11, 1),
    ),
  );
}

class _LoadedProducts extends AdminProductsPagedNotifier {
  @override
  AsyncValue<PagedListState<Product>> build() =>
      const AsyncData(PagedListState(items: [_food], hasMore: false));
}

const _food = Product(
  id: 'food',
  name: 'Growth Pellets',
  category: ProductCategory.fishFood,
  price: 20,
  stockQuantity: 5,
);

void _phone(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _expectTouchTarget(WidgetTester tester, Finder button) {
  final size = tester.getSize(button);
  expect(size.width, greaterThanOrEqualTo(44));
  expect(size.height, greaterThanOrEqualTo(44));
}

void main() {
  testWidgets("the customer's own review has named edit and delete buttons", (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isLoggedInProvider.overrideWithValue(true),
          myReviewForProductProvider.overrideWith(_MyReview.new),
          canReviewProductProvider('p').overrideWith((ref) async => true),
          productReviewsProvider('p').overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(child: ReviewsSection(productId: 'p')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your review'), findsOneWidget);
    expect(find.byTooltip('Edit your review'), findsOneWidget);
    expect(find.byTooltip('Delete your review'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete your review'));
    await tester.pumpAndSettle();
    expect(find.text('Delete review?'), findsOneWidget);
  });

  testWidgets('admin product search has a named clear button', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminProductsPagedProvider.overrideWith(_LoadedProducts.new),
          productListProvider.overrideWith((ref) async => const [_food]),
          isLoggedInProvider.overrideWithValue(false),
          shopSettingsProvider.overrideWith((ref) async => {}),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AdminProductsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Clear search'), findsNothing);
    await tester.enterText(find.byType(TextField), 'pellet');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.byTooltip('Clear search'), findsNothing);
  });

  testWidgets('admin order search has a named clear button', (tester) async {
    _phone(tester);
    final order = deliveryOrder(status: 'paid');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminOrdersProvider.overrideWith((ref) async => [order]),
          easyParcelConnectedProvider.overrideWith((ref) async => false),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AdminOrdersScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Clear search'), findsNothing);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });

  testWidgets('removing a size option is a named, full-size button', (
    tester,
  ) async {
    _phone(tester, const Size(390, 3000));
    await tester.pumpWidget(
      forms.host(
        const AdminProductEditScreen(),
        0,
        Brightness.light,
        textScale: 1,
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButtonFormField<ProductCategory>>(
          find.byType(DropdownButtonFormField<ProductCategory>),
        )
        .onChanged!(ProductCategory.fishFood);
    await tester.pumpAndSettle();
    final before = find.byTooltip('Remove size').evaluate().length;
    final add = find.widgetWithText(OutlinedButton, 'Add Size');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    final remove = find.byTooltip('Remove size');
    expect(remove, findsNWidgets(before + 1));
    _expectTouchTarget(tester, remove.last);
    await tester.ensureVisible(remove.last);
    // The corner of the target, away from the 18pt glyph.
    await tester.tapAt(
      tester.getRect(remove.last).topLeft + const Offset(3, 3),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove size'), findsNWidgets(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing a service photo is a named, full-size button', (
    tester,
  ) async {
    _phone(tester, const Size(390, 1400));
    // The test binding answers every image request with HTTP 400; the form
    // shows its broken-image placeholder, which is all this test needs.
    final reportError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception is NetworkImageLoadException) return;
      reportError?.call(details);
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          servicesProvider.overrideWith(
            (ref) async => const [
              Service(
                id: 's1',
                name: 'Pond cleaning',
                imageUrls: ['https://example.com/pond.jpg'],
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: AdminServicesTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pond cleaning'));
    await tester.pumpAndSettle();
    final remove = find.byTooltip('Remove photo');
    expect(remove, findsOneWidget);
    await tester.ensureVisible(remove);
    _expectTouchTarget(tester, remove);
    // The whole target must be tappable: bottom-left corner, far from the
    // glyph in the top-right corner.
    await tester.tapAt(tester.getRect(remove).bottomLeft + const Offset(3, -3));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove photo'), findsNothing);
    FlutterError.onError = reportError;
    expect(tester.takeException(), isNull);
  });
}
