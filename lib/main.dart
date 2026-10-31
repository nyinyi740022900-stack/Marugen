import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'core/config/env.dart';
import 'core/crash/crash_reporting.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/router/app_router.dart';
import 'core/router/setup_required_screen.dart';
import 'core/supabase/supabase_client.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_preference.dart';
import 'shared/widgets/keyboard_dismiss_region.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Wired up before anything else so a crash during the rest of startup
  // (dotenv, Supabase, Stripe init below) is still reported. Hard outer
  // timeout as a last-resort ceiling — CrashReporting.initialize() already
  // times out its own native calls internally, but this guarantees
  // `runApp` is reached regardless of which specific call misbehaves; a
  // missing crash-reporting hookup is far better than an app stuck on the
  // native launch splash forever (observed on a fresh Android emulator).
  debugPrint('[BOOT] before CrashReporting.initialize');
  await CrashReporting.initialize().timeout(
    const Duration(seconds: 10),
    onTimeout: () {},
  );
  debugPrint('[BOOT] after CrashReporting.initialize');

  // Uncaught async errors reach Crashlytics through
  // PlatformDispatcher.onError (set in CrashReporting.initialize), so no
  // runZonedGuarded here: running the app in a different zone than the one
  // that initialized the bindings triggers Flutter's "Zone mismatch" error.
  await _runApp();
}

Future<void> _runApp() async {
  // `.env` is optional at this stage — the app still boots without it so
  // the UI is browsable before Supabase/Stripe keys are wired up. See
  // `.env.example` for what to fill in.
  debugPrint('[BOOT] before dotenv.load');
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // No .env yet — Env.isConfigured will be false and screens show
    // friendly "not configured" states instead of crashing.
  }
  debugPrint('[BOOT] after dotenv.load, isConfigured=${Env.isConfigured}');

  if (!Env.isConfigured) {
    // No Supabase credentials yet — show setup instructions instead of
    // crashing on the first `flutter run` after checkout.
    runApp(const SetupRequiredScreen());
    return;
  }

  debugPrint('[BOOT] before SupabaseService.init');
  await SupabaseService.init();
  debugPrint('[BOOT] after SupabaseService.init');
  if (Env.stripePublishableKey.isNotEmpty) {
    Stripe.publishableKey = Env.stripePublishableKey;
    // Apple Pay is intentionally NOT configured here: it needs a real
    // merchant ID registered on a paid Apple Developer Program membership
    // plus the Apple Pay capability + entitlement added in Xcode. Without
    // that entitlement present in the app bundle, configuring Apple Pay in
    // the payment sheet (`applePay:` param, checkout_screen.dart) was
    // observed to crash the app on launch of the sheet rather than just
    // hiding the button — so leave both out until a paid account exists.
    //
    // Fire-and-forget, NOT awaited — same reasoning as PushNotificationService
    // below. On a device/emulator without Google Play Services, this native
    // call has been observed to block the platform thread itself rather than
    // just the Dart Future, so even a `.timeout()` on the await never fires
    // (the engine's message loop that would deliver the timeout is itself
    // stuck behind the blocked native call). Awaiting it here would freeze
    // the app on the native launch splash forever with no recovery.
    unawaited(Stripe.instance.applySettings());
  }
  debugPrint('[BOOT] about to call runApp');

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

/// Phones stay in portrait: in landscape the product page's header, tabs
/// and buy bar left almost no room for the product. Tablets, iPads and
/// unfolded foldables (shortest side 600dp or more) still rotate. Decided
/// from the first laid-out size, since the window can still be empty when
/// `main` runs, and again whenever a foldable changes size class.
abstract final class OrientationPolicy {
  static bool? _portraitOnly;

  static void apply(Size size) {
    if (size.isEmpty) return;
    final phone = size.shortestSide < 600;
    if (_portraitOnly == phone) return;
    _portraitOnly = phone;
    SystemChrome.setPreferredOrientations(
      phone ? const [DeviceOrientation.portraitUp] : const [],
    );
  }
}

class MarugenApp extends ConsumerWidget {
  const MarugenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    PushNotificationService.openLocation = (location) =>
        openFromNotification(router, location);
    return MaterialApp.router(
      title: 'Marugen Fish Farm',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      scaffoldMessengerKey: PushNotificationService.messengerKey,
      builder: (context, child) {
        OrientationPolicy.apply(MediaQuery.sizeOf(context));
        return ListenableBuilder(
          listenable: router.routeInformationProvider,
          builder: (context, _) {
            final path = router.routeInformationProvider.value.uri.path;
            final authentication = {
              '/login',
              '/signup',
              '/forgot-password',
              '/reset-password',
            }.contains(path);
            return Theme(
              data: AppTheme.forViewport(
                Theme.of(context),
                width: MediaQuery.sizeOf(context).width,
                authentication: authentication,
              ),
              child: _NonProdReleaseBanner(
                child: KeyboardDismissRegion(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// A release build is what actually gets uploaded to the Play Store —
/// this makes it visually impossible to miss if one somehow isn't pointed
/// at the production backend (see Env.appEnv doc: a real prod build must
/// pass `--dart-define-from-file=env/prod.json`, and forgetting that flag
/// used to be silent). No-ops in debug/profile, where "dev" is expected.
class _NonProdReleaseBanner extends StatelessWidget {
  final Widget? child;
  const _NonProdReleaseBanner({required this.child});

  @override
  Widget build(BuildContext context) {
    if (!kReleaseMode || Env.isProd || child == null) {
      return child ?? const SizedBox.shrink();
    }
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        child!,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Material(
              color: Colors.red.shade700,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'NON-PROD BACKEND (${Env.appEnv}) — RELEASE BUILD',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
