import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central place to read environment/config values.
///
/// Two ways a value can be provided, checked in this order:
///   1. A compile-time `--dart-define` (or `--dart-define-from-file=env/
///      prod.json`) — e.g. `SUPABASE_URL`. Values passed this way are
///      baked into the binary at build time. These are public client
///      configuration values, not a safe place for server secrets.
///      Runtime overrides do not remove the bundled `.env` asset.
///   2. `.env` (see `.env.example`), loaded at runtime via flutter_dotenv
///      in `main.dart` — the zero-setup path for local development that
///      has always worked here; unchanged for anyone not using flavors.
///
/// A value from (1) always wins when present, so a CI/release build only
/// has to pass `--dart-define-from-file=env/prod.json` (see
/// `env/prod.json.example`) to fully override `.env` with production
/// values — no asset-bundling changes, no native build flavors needed.
class Env {
  Env._();

  /// Which backend this build is pointed at — 'dev' unless a build
  /// explicitly passes `--dart-define=APP_ENV=prod` (normally via
  /// `--dart-define-from-file=env/prod.json`, see `env/prod.json.example`).
  /// Purely a safety/label value: it does not itself select which keys are
  /// read, it's what `main.dart` checks to warn if a **release** build
  /// somehow isn't flagged as pointing at production.
  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );
  static bool get isProd => appEnv == 'prod';

  static const _supabaseUrlDefine = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseAnonKeyDefine = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const _stripePublishableKeyDefine = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
  );
  static const _googleWebClientIdDefine = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );
  static const _googleIosClientIdDefine = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  static String get supabaseUrl => _supabaseUrlDefine.isNotEmpty
      ? _supabaseUrlDefine
      : (dotenv.env['SUPABASE_URL'] ?? '');
  static String get supabaseAnonKey => _supabaseAnonKeyDefine.isNotEmpty
      ? _supabaseAnonKeyDefine
      : (dotenv.env['SUPABASE_ANON_KEY'] ?? '');
  static String get stripePublishableKey =>
      _stripePublishableKeyDefine.isNotEmpty
      ? _stripePublishableKeyDefine
      : (dotenv.env['STRIPE_PUBLISHABLE_KEY'] ?? '');

  /// Google Cloud OAuth 2.0 **Web** client ID (used as serverClientId so
  /// google_sign_in returns an ID token Supabase can verify).
  static String get googleWebClientId => _googleWebClientIdDefine.isNotEmpty
      ? _googleWebClientIdDefine
      : (dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '');

  /// Google Cloud OAuth 2.0 **iOS** client ID.
  static String get googleIosClientId => _googleIosClientIdDefine.isNotEmpty
      ? _googleIosClientIdDefine
      : (dotenv.env['GOOGLE_IOS_CLIENT_ID'] ?? '');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
