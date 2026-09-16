import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/app_user.dart';

/// Wraps Supabase Auth + the `profiles` table (which stores the app-level
/// role used to decide customer vs admin UI). See
/// `supabase/migrations/0001_init.sql` for the `profiles` table + RLS.
class AuthRepository {
  final SupabaseClient _client = SupabaseService.client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Future<AppUser?> fetchCurrentAppUser() async {
    final user = currentUser;
    if (user == null) return null;
    final data = await _client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    if (data == null) {
      // Profile row is created by a DB trigger on signup; fall back to a
      // bare customer profile if it hasn't landed yet.
      return AppUser(id: user.id, email: user.email);
    }
    return AppUser.fromMap(data);
  }

  Future<void> signInWithEmail(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUpWithEmail(String email, String password, {String? fullName}) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      data: fullName != null ? {'full_name': fullName} : null,
    );
  }

  /// Deep link back into the app after the OAuth provider redirects to
  /// Supabase's hosted callback — registered as a URL scheme on both
  /// platforms (`ios/Runner/Info.plist`, `android/.../AndroidManifest.xml`).
  static const _oauthRedirectTo = 'marugen://login-callback';

  /// Starts the Google OAuth sign-in flow via Supabase Auth. Requires the
  /// Google provider to be enabled (with a client ID/secret) in the
  /// Supabase dashboard under Authentication → Providers — see the app's
  /// setup notes. Throws if that isn't configured yet; callers should
  /// catch and show an inline error rather than let this hang.
  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _oauthRedirectTo,
    );
  }

  /// Starts the Apple OAuth sign-in flow via Supabase Auth. Requires the
  /// Apple provider to be enabled in the Supabase dashboard — see the
  /// app's setup notes. Throws if that isn't configured yet; callers
  /// should catch and show an inline error rather than let this hang.
  Future<void> signInWithApple() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: _oauthRedirectTo,
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Sends a password-reset email via Supabase Auth. The user follows the
  /// link in that email to set a new password (handled by Supabase's
  /// hosted flow / the app's deep link, whichever is configured in the
  /// Supabase project's Auth settings).
  Future<void> sendPasswordResetEmail(String email) {
    return _client.auth.resetPasswordForEmail(email);
  }
}
