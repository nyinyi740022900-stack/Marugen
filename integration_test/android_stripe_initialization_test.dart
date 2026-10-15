import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android native Stripe initializes with the app activity/theme', (
    tester,
  ) async {
    const testKey = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
    expect(testKey, startsWith('pk_test_'));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Stripe initialization test'))),
      ),
    );
    Stripe.publishableKey = testKey;
    await Stripe.instance.applySettings();
    expect(tester.takeException(), isNull);
  });
}
