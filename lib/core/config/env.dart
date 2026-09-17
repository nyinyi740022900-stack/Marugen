import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central place to read environment/config values.
/// Values are loaded from `.env` (see `.env.example`) via flutter_dotenv
/// in `main.dart` before the app starts.
class Env {
  Env._();

  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  static String get stripePublishableKey =>
      dotenv.env['STRIPE_PUBLISHABLE_KEY'] ?? '';

  /// Google Cloud OAuth 2.0 **Web** client ID (used as serverClientId so
  /// google_sign_in returns an ID token Supabase can verify).
  static String get googleWebClientId =>
      dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';

  /// Google Cloud OAuth 2.0 **iOS** client ID.
  static String get googleIosClientId =>
      dotenv.env['GOOGLE_IOS_CLIENT_ID'] ?? '';

  /// Apple Pay merchant identifier (Apple Developer → Identifiers → Merchant
  /// IDs), e.g. `merchant.com.marugen.marugenApp`. Must also be set as
  /// `APPLE_MERCHANT_ID` in `ios/Flutter/Secrets.xcconfig` so it reaches
  /// `Runner.entitlements`. Leave blank to disable Apple Pay.
  static String get appleMerchantId =>
      dotenv.env['APPLE_MERCHANT_ID'] ?? '';

  static bool get isStripeTestMode =>
      stripePublishableKey.startsWith('pk_test_');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
