import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Thin accessor around the singleton Supabase client.
/// Call [SupabaseService.init] once in `main.dart` before use.
class SupabaseService {
  SupabaseService._();

  static Future<void> init() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser => client.auth.currentUser;

  static bool get isLoggedIn => currentUser != null;
}
