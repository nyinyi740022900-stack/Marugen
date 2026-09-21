import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/notifications/push_notification_service.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/app_user.dart';

/// Wraps Supabase Auth + the `profiles` table (which stores the app-level
/// role used to decide customer vs admin UI). See
/// `supabase/migrations/0001_init.sql` for the `profiles` table + RLS.
class AuthRepository {
  final SupabaseClient _client = SupabaseService.client;

  bool _googleInitialized = false;

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

  /// Uploads a new profile photo and saves its public URL onto the
  /// caller's own `profiles` row. Reuses the same `product-images`
  /// bucket as product/variety/service photos (see ProductRepository.
  /// uploadProductImage), scoped under `avatars/<uid>/...` — the storage
  /// policies added in 0032_profile_avatar.sql let a regular user write
  /// only within their own `avatars/<their uid>/` prefix, leaving every
  /// other path in the bucket admin-only as before.
  Future<String> uploadAvatar(Uint8List bytes, String ext) async {
    final user = currentUser;
    if (user == null) throw Exception('Not logged in');
    final path = 'avatars/${user.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('product-images').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    final url = _client.storage.from('product-images').getPublicUrl(path);
    await _client.from('profiles').update({'avatar_url': url}).eq('id', user.id);
    return url;
  }

  /// Toggles push notifications for the current user (Profile →
  /// Notifications). The in-app notification inbox keeps logging order
  /// updates regardless — this only gates whether a push is sent.
  Future<void> updateNotificationsEnabled(bool enabled) async {
    final user = currentUser;
    if (user == null) return;
    await _client
        .from('profiles')
        .update({'notifications_enabled': enabled})
        .eq('id', user.id);
    // Opting out should stop this device from being targetable at all, not
    // just flip a flag the send function checks — see push_notification
    // service doc for why (shared/handed-down device risk).
    if (!enabled) {
      await PushNotificationService.clearTokenForCurrentUser();
    }
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

  /// Deep link used for browser OAuth fallback (Android Apple / missing native config).
  static const oauthRedirectTo = 'marugen://login-callback';

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    final webClientId = Env.googleWebClientId;
    final iosClientId = Env.googleIosClientId;
    if (webClientId.isEmpty) {
      throw Exception(
        'Google Sign-In is not configured. Add GOOGLE_WEB_CLIENT_ID '
        '(and GOOGLE_IOS_CLIENT_ID on iOS) to .env — see README.',
      );
    }
    await GoogleSignIn.instance.initialize(
      serverClientId: webClientId,
      clientId: defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS
          ? (iosClientId.isEmpty ? null : iosClientId)
          : null,
    );
    _googleInitialized = true;
  }

  /// Native Google sign-in via ID token → Supabase session.
  Future<void> signInWithGoogle() async {
    await _ensureGoogleInitialized();

    const scopes = ['email', 'profile'];
    final googleSignIn = GoogleSignIn.instance;

    late final GoogleSignInAccount googleUser;
    try {
      googleUser = await googleSignIn.authenticate(scopeHint: scopes);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw Exception('Google sign-in was cancelled.');
      }
      rethrow;
    }

    final authorization =
        await googleUser.authorizationClient.authorizationForScopes(scopes) ??
            await googleUser.authorizationClient.authorizeScopes(scopes);

    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
      throw Exception('Google did not return an ID token. Check GOOGLE_WEB_CLIENT_ID.');
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: authorization.accessToken,
    );
  }

  /// Native Apple sign-in on iOS/macOS; browser OAuth elsewhere.
  Future<void> signInWithApple() async {
    final isApplePlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    if (!isApplePlatform) {
      final launched = await _client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: oauthRedirectTo,
      );
      if (!launched) {
        throw Exception('Could not open Apple sign-in.');
      }
      return;
    }

    final rawNonce = _generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw Exception('Apple did not return an ID token.');
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );

    // Apple only sends the name on the first authorization.
    if (credential.givenName != null || credential.familyName != null) {
      final parts = <String>[
        if (credential.givenName != null) credential.givenName!,
        if (credential.familyName != null) credential.familyName!,
      ];
      if (parts.isNotEmpty) {
        await _client.auth.updateUser(
          UserAttributes(data: {
            'full_name': parts.join(' '),
            'given_name': credential.givenName,
            'family_name': credential.familyName,
          }),
        );
      }
    }
  }

  String _generateRawNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  Future<void> signOut() async {
    // Must run before auth.signOut() below — clearing the token relies on
    // RLS scoping the update to the still-authenticated auth.uid().
    await PushNotificationService.clearTokenForCurrentUser();
    try {
      if (_googleInitialized) {
        await GoogleSignIn.instance.signOut();
      }
    } catch (_) {}
    await _client.auth.signOut();
  }

  /// Sends a password-reset email via Supabase Auth. Uses the same deep
  /// link already allow-listed for OAuth (see [oauthRedirectTo]) so the
  /// email opens the app instead of falling back to Supabase's default web
  /// redirect — the router (see app_router.dart) watches for the resulting
  /// `AuthChangeEvent.passwordRecovery` and sends the user to
  /// ResetPasswordScreen to actually set a new password.
  Future<void> sendPasswordResetEmail(String email) {
    return _client.auth.resetPasswordForEmail(email, redirectTo: oauthRedirectTo);
  }

  /// Sets a new password for the currently-authenticated session — used
  /// both for the password-recovery deep link flow (a temporary session
  /// Supabase creates when the reset link is opened) and for a regular
  /// logged-in user changing their password from Profile.
  Future<void> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }
}
