import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'core/config/env.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/router/app_router.dart';
import 'core/router/setup_required_screen.dart';
import 'core/supabase/supabase_client.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // `.env` is optional at this stage — the app still boots without it so
  // the UI is browsable before Supabase/Stripe keys are wired up. See
  // `.env.example` for what to fill in.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // No .env yet — Env.isConfigured will be false and screens show
    // friendly "not configured" states instead of crashing.
  }

  if (!Env.isConfigured) {
    // No Supabase credentials yet — show setup instructions instead of
    // crashing on the first `flutter run` after checkout.
    runApp(const SetupRequiredScreen());
    return;
  }

  await SupabaseService.init();
  if (Env.stripePublishableKey.isNotEmpty) {
    Stripe.publishableKey = Env.stripePublishableKey;
    // Only takes effect once a real Apple Pay merchant ID is registered in
    // the Apple Developer account (paid membership) and the Apple Pay
    // capability + this same identifier are added in Xcode — until then
    // Apple Pay just doesn't appear in the payment sheet, no crash either
    // way.
    Stripe.merchantIdentifier = 'merchant.com.marugen.marugenApp';
    await Stripe.instance.applySettings();
  }

  // Push notifications: fire-and-forget, NOT awaited. Without a
  // GoogleService-Info.plist / google-services.json in place, native FCM
  // calls (getToken() in particular) can hang waiting on an APNs callback
  // that never arrives instead of throwing — if this were awaited here, it
  // would block main() from ever reaching runApp(), freezing the app on
  // the launch screen forever. See the doc comment on
  // PushNotificationService for the setup steps that make this fully live.
  unawaited(PushNotificationService.initialize());

  runApp(const ProviderScope(child: MarugenApp()));
}

class MarugenApp extends ConsumerWidget {
  const MarugenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Marugen Koi Farm',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
      scaffoldMessengerKey: PushNotificationService.messengerKey,
    );
  }
}
