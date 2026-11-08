import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../../core/config/env.dart';

/// Shows Stripe's PaymentSheet for [clientSecret] — at checkout and from
/// "Complete payment" on a pending order. Native setup may outlive the screen
/// or its signed-in owner, so [stillWanted] is checked before presenting.
Future<void> showStripePaymentSheet(
  String clientSecret, {
  required Brightness brightness,
  required bool Function() stillWanted,
}) async {
  await Stripe.instance.initPaymentSheet(
    paymentSheetParameters: SetupPaymentSheetParameters(
      paymentIntentClientSecret: clientSecret,
      style: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      merchantDisplayName: 'Marugen Fish Farm',
      // Required for PayNow (and any other redirect/voucher-based
      // method) to bring the customer back into the app instead of
      // stranding them in Safari — matches the `marugen` URL scheme
      // registered in ios/Runner/Info.plist.
      returnURL: 'marugen://stripe-redirect',
      // Apple Pay is deliberately left out: without a real merchant ID
      // (needs a paid Apple Developer Program membership) and the
      // matching Xcode entitlement, configuring `applePay:` here was
      // observed to crash the app when the sheet opens rather than
      // just hiding the button. Re-add once that account/entitlement
      // exists. Google Pay is Android-only — harmless to leave on here,
      // it's simply ignored on iOS.
      googlePay: PaymentSheetGooglePay(
        merchantCountryCode: 'SG',
        currencyCode: 'SGD',
        // Was hardcoded `true` — meant every build, including a real
        // production release, would only ever offer Google Pay's test
        // environment, silently failing/faking real customer charges
        // via Google Pay. Derived from the actual publishable key in
        // use (not just Env.appEnv) so it's correct even if a build is
        // mislabeled: `pk_live_...` always means real money.
        testEnv: !Env.stripePublishableKey.startsWith('pk_live'),
      ),
    ),
  );
  if (!stillWanted()) return;
  await Stripe.instance.presentPaymentSheet();
}
