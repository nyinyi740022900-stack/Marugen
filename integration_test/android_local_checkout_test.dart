// Opt-in native acceptance against the disposable local Supabase stack only.
// Supply public local client config and synthetic test credentials using
// --dart-define-from-file. Never run this target against production.
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:marugen_app/core/config/env.dart';
import 'package:marugen_app/core/router/app_router.dart';
import 'package:marugen_app/core/supabase/supabase_client.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/orders/data/payment_repository.dart';
import 'package:marugen_app/features/orders/presentation/checkout_screen.dart';
import 'package:marugen_app/features/orders/presentation/order_detail_screen.dart';
import 'package:marugen_app/main.dart' as app;
import 'package:marugen_app/shared/models/product.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('local Android native checkout confirms a test payment', (
    tester,
  ) async {
    await dotenv.load(fileName: '.env');
    expect(Env.supabaseUrl, 'http://10.0.2.2:54321');
    expect(Env.stripePublishableKey, startsWith('pk_test_'));
    const email = String.fromEnvironment('LOCAL_TEST_EMAIL');
    const password = String.fromEnvironment('LOCAL_TEST_PASSWORD');
    const productId = String.fromEnvironment('LOCAL_TEST_PRODUCT_ID');
    expect(email, endsWith('@example.invalid'));
    expect(password, isNotEmpty);
    expect(productId, isNotEmpty);

    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
    await SupabaseService.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    Stripe.publishableKey = Env.stripePublishableKey;
    Stripe.urlScheme = 'marugen';
    await Stripe.instance.applySettings();
    final productMap = await SupabaseService.client
        .from('products')
        .select()
        .eq('id', productId)
        .single();
    final product = Product.fromMap(productMap);
    final originalStock = product.stockQuantity;
    await tester.pumpWidget(const ProviderScope(child: app.MarugenApp()));
    for (var i = 0; i < 60 && find.text('Shop').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('Shop'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(app.MarugenApp)),
    );
    container
        .read(routerProvider)
        .push('/checkout', extra: [CartItem(product: product)]);
    await tester.pumpAndSettle();
    expect(find.byType(CheckoutScreen), findsOneWidget);
    final pay = find.widgetWithText(ElevatedButton, 'Pay S\$1.00 with Stripe');
    for (var i = 0; i < 45 && pay.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(pay, findsOneWidget);
    await tester.ensureVisible(pay);
    expect(pay.hitTestable(), findsOneWidget);
    // Confirm through the real native SDK with Stripe's synthetic test
    // method. This covers native initialization and webhook/stock linkage;
    // it does not claim manual card entry or PaymentSheet presentation.
    final addresses = await SupabaseService.client
        .from('addresses')
        .select()
        .eq('user_id', SupabaseService.currentUser!.id);
    final intent = await PaymentRepository().createPaymentIntent(
      items: [
        {'product_id': productId, 'quantity': 1},
      ],
      shippingAddress: Map<String, dynamic>.from(addresses.first),
      idempotencyKey: 'android-local-${DateTime.now().microsecondsSinceEpoch}',
    );
    final secret = intent['clientSecret'] as String;
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: secret,
        merchantDisplayName: 'Marugen local acceptance',
        returnURL: 'marugen://stripe-redirect',
      ),
    );
    final paid = await Stripe.instance.confirmPayment(
      paymentIntentClientSecret: secret,
      data: const PaymentMethodParams.cardFromMethodId(
        paymentMethodData: PaymentMethodDataCardFromMethod(
          paymentMethodId: 'pm_card_visa',
        ),
      ),
    );
    expect(paid.status, PaymentIntentsStatus.Succeeded);
    var status = '';
    for (var i = 0; i < 60 && status != 'paid'; i++) {
      await tester.pump(const Duration(seconds: 1));
      final row = await SupabaseService.client
          .from('orders')
          .select('status')
          .eq('id', intent['orderId'])
          .single();
      status = row['status'] as String;
    }
    expect(status, 'paid', reason: 'Real forwarded webhook must mark paid.');
    container.read(routerProvider).go('/orders/${intent['orderId']}');
    await tester.pumpAndSettle();
    expect(find.byType(OrderDetailScreen), findsOneWidget);
    final orders = await SupabaseService.client
        .from('orders')
        .select('id,status,order_items(product_id)')
        .eq('user_id', SupabaseService.currentUser!.id)
        .eq('status', 'paid');
    expect(
      orders.where(
        (order) => (order['order_items'] as List).any(
          (item) => item['product_id'] == productId,
        ),
      ),
      hasLength(1),
    );
    final latest = await SupabaseService.client
        .from('products')
        .select('stock_quantity')
        .eq('id', productId)
        .single();
    expect(latest['stock_quantity'], originalStock - 1);
    expect(tester.takeException(), isNull);
    await binding.convertFlutterSurfaceToImage();
    await tester.pump(const Duration(seconds: 1));
    await binding.takeScreenshot('android-local-paid-order');
  });
}
