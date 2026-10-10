import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/orders/presentation/checkout_screen.dart';
import 'package:marugen_app/features/orders/presentation/purchase_intent.dart';
import 'package:marugen_app/features/profile/presentation/address_providers.dart';
import 'package:marugen_app/shared/models/address.dart';
import 'package:marugen_app/shared/models/promo_code.dart';
import 'package:marugen_app/features/promo/data/promo_repository.dart';
import 'package:marugen_app/features/promo/presentation/promo_providers.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';

final checkoutUserProvider = StateProvider<String?>((ref) => 'a');

const selectedItem = CartItem(
  product: Product(
    id: 'selected',
    name: 'Fish food',
    category: ProductCategory.accessories,
    price: 10,
  ),
  quantity: 2,
);
const address = Address(
  id: 'address',
  userId: 'a',
  recipientName: 'Customer',
  phone: '12345678',
  line1: '1 Street',
  postalCode: '123456',
);

Future<void> showCheckout(
  WidgetTester tester,
  Future<Map<String, dynamic>> settings, {
  PromoRepository? promoRepository,
  double textScale = 1,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWith(
          (ref) => ref.watch(checkoutUserProvider),
        ),
        if (promoRepository != null)
          promoRepositoryProvider.overrideWithValue(promoRepository),
        shopSettingsProvider.overrideWith((ref) => settings),
        myAddressesProvider.overrideWith((ref) async => [address]),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const CheckoutScreen(buyNowItems: [selectedItem]),
      ),
    ),
  );
  await tester.pump();
}

class PendingPromoRepository implements PromoRepository {
  final Completer<PromoCode?> result = Completer<PromoCode?>();
  @override
  Future<PromoCode?> lookupCode(String code) => result.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('checkout remains readable on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showCheckout(
      tester,
      Future.value({'gst_percent': 9, 'gst_included_in_price': true}),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Total (incl. GST)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });
  testWidgets('checkout hides former account selection after account changes', (
    tester,
  ) async {
    await showCheckout(
      tester,
      Future.value({'gst_percent': 9, 'gst_included_in_price': true}),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CheckoutScreen)),
    );
    container.read(checkoutUserProvider.notifier).state = 'b';
    await tester.pumpAndSettle();
    expect(find.text('Fish food'), findsNothing);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
  });
  testWidgets(
    'token selection mounts and is consumed without account cart fallback',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('a'),
          shopSettingsProvider.overrideWith(
            (ref) async => {'gst_percent': 9, 'gst_included_in_price': true},
          ),
          myAddressesProvider.overrideWith((ref) async => [address]),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(purchaseIntentProvider.notifier);
      final token = notifier.start([selectedItem]);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: CheckoutScreen(purchaseIntentId: token)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('20.00 with Stripe'), findsOneWidget);
      expect(container.read(purchaseIntentProvider), isNull);
      expect(notifier.consume(token), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('payment is disabled throughout promo validation', (
    tester,
  ) async {
    final repo = PendingPromoRepository();
    await showCheckout(
      tester,
      Future.value({'gst_percent': 9, 'gst_included_in_price': true}),
      promoRepository: repo,
    );
    await tester.pumpAndSettle();
    final promoField = find.byKey(const ValueKey('promo-code'));
    await tester.scrollUntilVisible(
      promoField,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(promoField, 'SAVE');
    await tester.ensureVisible(find.text('Apply'));
    await tester.tap(find.text('Apply'));
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    expect(tester.widget<TextField>(promoField).enabled, isFalse);
    repo.result.complete(null);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });
  testWidgets(
    'payment stays disabled until totals are loaded then shows tax-inclusive amount',
    (tester) async {
      final settings = Completer<Map<String, dynamic>>();
      await showCheckout(tester, settings.future);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      settings.complete({'gst_percent': 9, 'gst_included_in_price': false});
      await tester.pumpAndSettle();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull,
      );
      expect(find.textContaining('21.80 with Stripe'), findsOneWidget);
    },
  );
  testWidgets(
    'failed totals cannot enable payment even with items and address',
    (tester) async {
      final settings = Completer<Map<String, dynamic>>();
      await showCheckout(tester, settings.future);
      settings.completeError(Exception('unavailable'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.text('Retry'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Retry'), findsOneWidget);
    },
  );
  testWidgets('isolated item removal can be undone without losing quantity', (
    tester,
  ) async {
    await showCheckout(
      tester,
      Future.value({'gst_percent': 9, 'gst_included_in_price': true}),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    expect(find.textContaining('20.00 with Stripe'), findsOneWidget);
  });
}
