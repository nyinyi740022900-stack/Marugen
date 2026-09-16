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

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
