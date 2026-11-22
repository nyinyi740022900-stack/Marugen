import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/notifications/app_icon_badge.dart';
import '../../../core/notifications/push_notification_service.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/utils/error_message.dart';
import '../../../shared/utils/image_upload.dart';

/// A failure this repository reports in its own words. [message] is written
/// for the customer and is the only auth error text the screens show as-is;
/// everything else (Supabase, Google, Apple) is mapped to fixed copy.
const googleSignInUnavailableMessage =
    "Google sign-in isn't available right now. Use email instead.";

class AuthRepositoryException implements Exception {
  final String message;
  const AuthRepositoryException(this.message);

  @override
  String toString() => message;
}

/// Sign-up was refused because the address already has an account.
class EmailAlreadyRegisteredException extends AuthRepositoryException {
  const EmailAlreadyRegisteredException()
    : super(
        'An account with this email already exists. Log in, or use Forgot password.',
      );
}

/// With email confirmation on, Supabase answers a sign-up for an address
/// that already has an account exactly like a new one — no error, no
/// session — except that the returned user carries no identities, and no
/// email is sent. Treating that as "check your inbox" strands the customer.
bool signUpEmailAlreadyRegistered(AuthResponse response) =>
    response.session == null && (response.user?.identities?.isEmpty ?? false);

/// Wraps Supabase Auth + the `profiles` table (which stores the app-level
/// role used to decide customer vs admin UI). See
/// `supabase/migrations/0001_init.sql` for the `profiles` table + RLS.
class AuthRepository {
  final SupabaseClient _client;
  AuthRepository({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  bool _googleInitialized = false;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  /// False only for an email/password account that hasn't clicked its
  /// confirmation link yet. Always true for OAuth accounts (Google/Apple
  /// verify the email themselves before Supabase ever creates the user) and
  /// for any account once `email_confirmed_at` is set. If the Supabase
  /// project's own "Confirm email" setting is enabled, a session can't even
  /// exist yet for an unconfirmed email/password account — this is a
  /// client-side belt-and-suspenders check for when that setting is off (or
  /// changes later), not a replacement for it.
  bool get isEmailVerified {
    final user = currentUser;
    if (user == null) return true;
    final provider = user.appMetadata['provider'] as String?;
    if (provider != null && provider != 'email') return true;
    return user.emailConfirmedAt != null;
  }

  /// Re-sends the signup confirmation email to [email], or to the current
  /// session's address when omitted. Right after sign-up there is no
  /// session yet, so the sign-up screen passes the address it just used.
  /// Throws if there is no address to send to.
  Future<void> resendVerificationEmail({String? email}) async {
    final address = email ?? currentUser?.email;
    if (address == null) {
      throw const AuthRepositoryException('Log in to resend the email.');
    }
    await _client.auth.resend(type: OtpType.signup, email: address);
  }

  Future<AppUser?> fetchCurrentAppUser() async {
    final user = currentUser;
    if (user == null) return null;
    final data = await _client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    final usesPassword = user.appMetadata['provider'] == 'email';
    if (data == null) {
      // Profile row is created by a DB trigger on signup; fall back to a
      // bare customer profile if it hasn't landed yet.
      return AppUser(
        id: user.id,
        email: user.email,
        usesPassword: usesPassword,
      );
    }
    return AppUser.fromMap(data, usesPassword: usesPassword);
  }

  /// Looks up another user's profile by id — for the admin "view customer"
  /// screen. Relies on the admin-only RLS policy added in
  /// 0045_admin_view_profiles.sql; returns null for a non-admin caller or a
  /// missing id, same as a not-found result.
  Future<AppUser?> fetchAppUserById(String id) async {
    final data = await _client
        .from('profiles')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
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
    if (user == null) {
      throw const AuthRepositoryException('Log in to change your photo.');
    }
    final upload = prepareImageUpload(bytes, ext, upsert: true);
    final path =
        'avatars/${user.id}/${DateTime.now().millisecondsSinceEpoch}.${upload.extension}';
    await _client.storage
        .from('product-images')
        .uploadBinary(
          path,
          bytes,
          fileOptions: upload.fileOptions,
        );
    final url = _client.storage.from('product-images').getPublicUrl(path);
    await _client
        .from('profiles')
        .update({'avatar_url': url})
        .eq('id', user.id);
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

  /// Creates the account. Returns true when the email must be confirmed
  /// before logging in (Supabase returned no session); false when the
  /// customer is already signed in and the router takes over. Throws
  /// [EmailAlreadyRegisteredException] when the address already has an
  /// account (see [signUpEmailAlreadyRegistered]).
  Future<bool> signUpWithEmail(
    String email,
    String password, {
    String? fullName,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: fullName != null ? {'full_name': fullName} : null,
    );
    if (signUpEmailAlreadyRegistered(response)) {
      throw const EmailAlreadyRegisteredException();
    }
    return response.session == null;
  }

  /// Deep link used for browser OAuth fallback (Android Apple / missing native config).
  static const oauthRedirectTo = 'marugen://login-callback';

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    final webClientId = Env.googleWebClientId;
    final iosClientId = Env.googleIosClientId;
    if (webClientId.isEmpty) {
      // Missing GOOGLE_WEB_CLIENT_ID (and GOOGLE_IOS_CLIENT_ID on iOS) in
      // the build's environment — see README. Not something a customer can
      // act on, so they are pointed at the way that works.
      developer.log(
        'Google Sign-In is not configured for this build',
        name: 'AuthRepository',
      );
      throw const AuthRepositoryException(googleSignInUnavailableMessage);
    }
    await GoogleSignIn.instance.initialize(
      serverClientId: webClientId,
      clientId:
          defaultTargetPlatform == TargetPlatform.iOS ||
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
        throw const AuthRepositoryException('Sign-in was cancelled.');
      }
      rethrow;
    }

    final authorization =
        await googleUser.authorizationClient.authorizationForScopes(scopes) ??
        await googleUser.authorizationClient.authorizeScopes(scopes);

    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
      developer.log(
        'Google did not return an ID token',
        name: 'AuthRepository',
      );
      throw const AuthRepositoryException(googleSignInUnavailableMessage);
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: authorization.accessToken,
    );
  }

  /// Native Apple sign-in on iOS/macOS; browser OAuth elsewhere.
  Future<void> signInWithApple() async {
    final isApplePlatform =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    if (!isApplePlatform) {
      final launched = await _client.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: oauthRedirectTo,
      );
      if (!launched) {
        throw const AuthRepositoryException(
          "Apple sign-in couldn't be opened. Use email instead.",
        );
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
      throw const AuthRepositoryException(
        "Apple sign-in didn't complete. Try again, or use email instead.",
      );
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
          UserAttributes(
            data: {
              'full_name': parts.join(' '),
              'given_name': credential.givenName,
              'family_name': credential.familyName,
            },
          ),
        );
      }
    }
  }

  String _generateRawNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  Future<void> signOut() async {
    // Must run before auth.signOut() below — clearing the token relies on
    // RLS scoping the update to the still-authenticated auth.uid().
    await PushNotificationService.clearTokenForCurrentUser();
    // The app icon badge reflects *this* account's unread count — clear it
    // so it doesn't keep showing a stale number on a shared/handed-down
    // device after signing out.
    await AppIconBadge.clear();
    try {
      if (_googleInitialized) {
        await GoogleSignIn.instance.signOut();
      }
    } catch (e) {
      // Non-fatal — local Supabase sign-out below still proceeds either
      // way; logged so a real recurring failure isn't invisible.
      developer.log('Google sign-out failed', name: 'AuthRepository', error: e);
    }
    await _client.auth.signOut();
  }

  /// Permanently deletes the signed-in auth account and personal profile.
  /// Necessary order records remain, detached from the deleted profile.
  Future<void> deleteAccount() async {
    try {
      await _client.functions.invoke('delete-account');
    } on FunctionException catch (e) {
      // invoke() throws on every non-2xx response, so nothing below runs
      // and the account stays signed in.
      throw ServerMessageException.fromFunction(
        e,
        fallback:
            'Your account was not deleted. Try again, or contact support.',
      );
    }
    // The server already deleted this account. Clear the local session without
    // requiring a global revocation request against the now-missing user.
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (e) {
      // Local auth state is cleared before the optional remote sign-out call.
      developer.log('Post-deletion sign-out cleanup failed', name: 'AuthRepository', error: e);
    }
    try {
      await AppIconBadge.clear();
      if (_googleInitialized) await GoogleSignIn.instance.signOut();
    } catch (e) {
      developer.log(
        'Post-deletion device cleanup failed',
        name: 'AuthRepository',
        error: e,
      );
    }
  }

  /// Sends a password-reset email via Supabase Auth. Uses the same deep
  /// link already allow-listed for OAuth (see [oauthRedirectTo]) so the
  /// email opens the app instead of falling back to Supabase's default web
  /// redirect — the router (see app_router.dart) watches for the resulting
  /// `AuthChangeEvent.passwordRecovery` and sends the user to
  /// ResetPasswordScreen to actually set a new password.
  Future<void> sendPasswordResetEmail(String email) {
    return _client.auth.resetPasswordForEmail(
      email,
      redirectTo: oauthRedirectTo,
    );
  }

  /// Profile → "Edit name". RLS limits the update to the caller's own row.
  Future<void> updateFullName(String fullName) async {
    final user = currentUser;
    if (user == null) return;
    await _client
        .from('profiles')
        .update({'full_name': fullName})
        .eq('id', user.id);
  }

  /// Sets a new password for the currently-authenticated session — used
  /// both for the password-recovery deep link flow (a temporary session
  /// Supabase creates when the reset link is opened) and for a regular
  /// logged-in user changing their password from Profile.
  Future<void> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }
}
