import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/orders/presentation/checkout_screen.dart';
import 'package:marugen_app/features/orders/presentation/order_status_timeline.dart';
import 'package:marugen_app/features/profile/presentation/address_providers.dart';
import 'package:marugen_app/features/shop/presentation/customer_shell.dart';
import 'package:marugen_app/shared/models/address.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

void main() {
  testWidgets('Dark tablet shopping navigation keeps selected icon contrast', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(820, 1180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AdaptiveCustomerNavigation(
          index: 0,
          onSelected: (_) {},
          body: const Text('Products'),
        ),
      ),
    );
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.backgroundColor!.computeLuminance(), lessThan(.1));
    expect(
      contrast(rail.selectedIconTheme!.color!, rail.indicatorColor!),
      greaterThanOrEqualTo(3),
    );
    expect(
      contrast(rail.selectedLabelTextStyle!.color!, rail.backgroundColor!),
      greaterThanOrEqualTo(4.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Dark checkout amounts and cards remain readable without a backend',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWith((ref) => 'customer'),
            shopSettingsProvider.overrideWith(
              (ref) async => {'delivery_fee': 0, 'gst_registered': false},
            ),
            myAddressesProvider.overrideWith(
              (ref) async => [
                const Address(
                  id: 'address',
                  userId: 'customer',
                  recipientName: 'Customer',
                  phone: '12345678',
                  line1: '1 Street',
                  postalCode: '123456',
                ),
              ],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const CheckoutScreen(
              buyNowItems: [
                CartItem(
                  product: Product(
                    id: 'food',
                    name: 'Fish food',
                    category: ProductCategory.accessories,
                    price: 10,
                  ),
                  quantity: 2,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final amount = find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'S\$20.00',
      );
      expect(amount, findsWidgets);
      for (final element in amount.evaluate()) {
        final text = element.widget as Text;
        final foreground =
            text.style?.color ?? DefaultTextStyle.of(element).style.color!;
        final palette = AppPalette.of(element);
        expect(
          contrast(foreground, palette.surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      final containers = tester.widgetList<Container>(find.byType(Container));
      final colors = containers
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .whereType<Color>();
      expect(colors.where((color) => color.computeLuminance() > .8), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Dark order timeline preserves active step contrast', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: OrderStatusTimeline(status: OrderStatus.paid),
        ),
      ),
    );
    final active = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).shape == BoxShape.circle,
        )
        .first;
    expect(
      contrast(AppColors.white, (active.decoration as BoxDecoration).color!),
      greaterThanOrEqualTo(3),
    );
    expect(tester.takeException(), isNull);
  });
}
