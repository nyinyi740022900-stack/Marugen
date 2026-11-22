import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/content_width.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    show SignInWithAppleButton, SignInWithAppleButtonStyle;
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        AuthException,
        AuthRetryableFetchException,
        AuthSessionMissingException;

import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/email_validator.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../data/auth_repository.dart';
import 'auth_providers.dart';
import '../../orders/presentation/purchase_intent.dart';

class LoginScreen extends ConsumerStatefulWidget {
  /// Pre-fills the email field: set when arriving from Sign Up with an
  /// address that already has an account, or that was just registered.
  final String? initialEmail;
  const LoginScreen({super.key, this.initialEmail});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _emailCtrl = TextEditingController(
    text: widget.initialEmail?.trim(),
  );
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _oauthLoading = false;
  String? _error;

  /// Opens Sign Up; when it sends the customer back with an email (already
  /// registered, or just registered and awaiting confirmation) that address
  /// is put in the email field.
  Future<void> _openSignup() async {
    final email = await context.push<Object?>(
      authRouteWithRedirect(
        '/signup',
        GoRouterState.of(context).uri.queryParameters['redirect'],
      ),
    );
    if (!mounted || email is! String || email.trim().isEmpty) return;
    setState(() {
      _emailCtrl.text = email.trim();
      _passwordCtrl.clear();
      _error = null;
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || _oauthLoading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signInWithEmail(_emailCtrl.text.trim(), _passwordCtrl.text);
      // Router redirect handles navigation once auth state updates.
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e, AuthErrorScreen.login));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _oauthSignIn(Future<void> Function() signIn) async {
    if (_loading || _oauthLoading) return;
    setState(() {
      _oauthLoading = true;
      _error = null;
    });
    try {
      await signIn();
      // Router redirect handles navigation once the OAuth redirect lands
      // and auth state updates.
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e, AuthErrorScreen.login));
    } finally {
      if (mounted) setState(() => _oauthLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // A tall, wide iPhone can afford the full form. Height alone classified
    // even the Pro Max as compact once its safe areas were subtracted.
    final roomyPhone =
        Theme.of(context).platform == TargetPlatform.iOS &&
        media.size.width >= 400 &&
        media.size.height - media.viewPadding.vertical >= 800;
    final compact =
        !roomyPhone && media.size.height - media.viewPadding.vertical < 900;
    final sectionGap = roomyPhone
        ? AppSpacing.lg
        : compact
        ? AppSpacing.md
        : AppSpacing.xl;
    final groupGap = roomyPhone
        ? AppSpacing.sm
        : compact
        ? AppSpacing.sm
        : AppSpacing.lg;
    final buttonStyle = roomyPhone
        ? const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(0, 56)),
            textStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          )
        : compact
        ? const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(0, 48)),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          )
        : null;
    // Login is a light page with no AppBar when it is the root route, so
    // set the status bar explicitly; otherwise iOS keeps the previous
    // screen's light icons and the clock disappears.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: statusBarStyleFor(Theme.of(context).brightness),
      child: Scaffold(
        backgroundColor: AppPalette.of(context).surface,
        // Visible way back when Login was pushed from Buy Now / Checkout —
        // iOS has no system back button, only the edge swipe.
        extendBodyBehindAppBar: true,
        appBar: Navigator.of(context).canPop()
            ? AppBar(
                backgroundColor: Colors.transparent,
                foregroundColor: AppPalette.of(context).text,
                leading: BackButton(
                  color: AppPalette.of(context).text,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                elevation: 0,
                scrolledUnderElevation: 0,
                systemOverlayStyle: statusBarStyleFor(
                  Theme.of(context).brightness,
                ),
              )
            : null,
        body: ContentWidth(
          maxWidth: 560,
          child: Theme(
            data: roomyPhone
                ? Theme.of(context).copyWith(
                    inputDecorationTheme: Theme.of(context).inputDecorationTheme
                        .copyWith(
                          labelStyle: TextStyle(
                            fontSize: 16,
                            color: AppPalette.of(context).textMuted,
                          ),
                        ),
                    textTheme: Theme.of(context).textTheme.copyWith(
                      bodyLarge: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(fontSize: 16),
                    ),
                  )
                : Theme.of(context),
            child: SafeArea(
              child: CustomScrollView(
                slivers: [
                  // The hero and form scroll together, including above the keyboard.
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        roomyPhone
                            ? AppSpacing.lg
                            : compact
                            ? AppSpacing.sm
                            : AppSpacing.xl,
                        AppSpacing.xl,
                        roomyPhone
                            ? AppSpacing.sm
                            : compact
                            ? AppSpacing.sm
                            : AppSpacing.md,
                      ),
                      child: Column(
                        children: [
                          BrandLogo(size: compact ? 56 : 88),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'MARUGEN FISH FARM',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppPalette.of(context).text,
                              fontSize: compact ? 16 : 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: compact ? 1.5 : 3,
                            ),
                          ),
                          if (!compact) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Premium Koi & Arowana — Singapore',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppPalette.of(context).textMuted,
                                fontSize: 12.5,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Form sheet
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppPalette.of(context).background,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(AppRadius.lg),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          roomyPhone
                              ? 20
                              : compact
                              ? AppSpacing.lg
                              : AppSpacing.xxl,
                          AppSpacing.xl,
                          roomyPhone
                              ? AppSpacing.lg
                              : compact
                              ? AppSpacing.sm
                              : AppSpacing.xl,
                        ),
                        child: AutofillGroup(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Welcome back',
                                  style: TextStyle(
                                    fontSize: roomyPhone ? 26 : 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Log in to continue shopping',
                                  style: TextStyle(
                                    fontSize: roomyPhone ? 16 : 13.5,
                                    color: AppPalette.of(context).textMuted,
                                  ),
                                ),
                                SizedBox(height: sectionGap),
                                TextFormField(
                                  controller: _emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  decoration: const InputDecoration(
                                    errorMaxLines: 4,
                                    labelText: 'Email',
                                    prefixIcon: Icon(
                                      Icons.mail_outline,
                                      size: 20,
                                    ),
                                  ),
                                  validator: validateEmail,
                                ),
                                SizedBox(
                                  height: roomyPhone
                                      ? AppSpacing.sm
                                      : compact
                                      ? AppSpacing.sm
                                      : AppSpacing.md,
                                ),
                                TextFormField(
                                  controller: _passwordCtrl,
                                  obscureText: _obscure,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [AutofillHints.password],
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    errorMaxLines: 4,
                                    labelText: 'Password',
                                    prefixIcon: const Icon(
                                      Icons.lock_outline,
                                      size: 20,
                                    ),
                                    suffixIcon: IconButton(
                                      tooltip: _obscure
                                          ? 'Show password'
                                          : 'Hide password',
                                      icon: Icon(
                                        _obscure
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        size: 20,
                                        color: AppPalette.of(context).textMuted,
                                      ),
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                    ),
                                  ),
                                  validator: (v) => (v == null || v.length < 6)
                                      ? 'Minimum 6 characters'
                                      : null,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Align(
                                  alignment: Alignment.centerRight,
                                  // Was shrunk to text-bounds via
                                  // tapTargetSize.shrinkWrap/minimumSize.zero — well
                                  // under the ~44px tap-target guideline. A normal
                                  // TextButton already has a sane default hit area;
                                  // removing that override is the whole fix.
                                  child: TextButton(
                                    onPressed: () =>
                                        context.push('/forgot-password'),
                                    child: Text(
                                      'Forgot password?',
                                      style: TextStyle(
                                        color: AppPalette.of(context).textMuted,
                                        fontSize: roomyPhone ? 14 : 12.5,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_error != null) ...[
                                  SizedBox(
                                    height: compact
                                        ? AppSpacing.sm
                                        : AppSpacing.md,
                                  ),
                                  // Announced the moment it appears.
                                  Semantics(
                                    liveRegion: true,
                                    child: Container(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.md,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppPalette.of(context).accentSoft,
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.sm,
                                      ),
                                    ),
                                    child: Text(
                                      _error!,
                                      style: TextStyle(
                                        color: AppPalette.of(context).accent,
                                        fontSize: 13,
                                      ),
                                    ),
                                    ),
                                  ),
                                ],
                                SizedBox(
                                  height: compact ? AppSpacing.xs : sectionGap,
                                ),
                                ElevatedButton(
                                  style: buttonStyle,
                                  onPressed: _loading ? null : _submit,
                                  child: _loading
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.white,
                                          ),
                                        )
                                      : const Text('Log In'),
                                ),
                                SizedBox(height: sectionGap),
                                Row(
                                  children: [
                                    const Expanded(child: Divider()),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.md,
                                      ),
                                      child: Text(
                                        'OR',
                                        style: TextStyle(
                                          color: AppPalette.of(context)
                                              .textMuted,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                    ),
                                    const Expanded(child: Divider()),
                                  ],
                                ),
                                SizedBox(height: groupGap),
                                OutlinedButton.icon(
                                  style: buttonStyle,
                                  onPressed: _oauthLoading
                                      ? null
                                      : () => _oauthSignIn(
                                          () => ref
                                              .read(authRepositoryProvider)
                                              .signInWithGoogle(),
                                        ),
                                  icon: const Icon(
                                    Icons.g_mobiledata,
                                    size: 24,
                                  ),
                                  label: const Text('Continue with Google'),
                                ),
                                if (Theme.of(context).platform !=
                                    TargetPlatform.android) ...[
                                  SizedBox(
                                    height: roomyPhone
                                        ? AppSpacing.sm
                                        : compact
                                        ? AppSpacing.sm
                                        : AppSpacing.md,
                                  ),
                                  // Apple's own button: App Review expects
                                  // the HIG style, not a generic outline.
                                  SignInWithAppleButton(
                                    text: 'Continue with Apple',
                                    height: 48,
                                    style:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? SignInWithAppleButtonStyle.white
                                        : SignInWithAppleButtonStyle.black,
                                    onPressed: _oauthLoading
                                        ? null
                                        : () => _oauthSignIn(
                                            () => ref
                                                .read(authRepositoryProvider)
                                                .signInWithApple(),
                                          ),
                                  ),
                                ],
                                SizedBox(height: groupGap),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      "Don't have an account?",
                                      style: TextStyle(
                                        color: AppPalette.of(context).textMuted,
                                        fontSize: roomyPhone ? 16 : 13.5,
                                      ),
                                    ),
                                    // TextButton (not a bare GestureDetector) so
                                    // this gets a real ~44px tap target and a
                                    // splash/highlight, not just the glyph bounds.
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                      ),
                                      onPressed: _openSignup,
                                      child: Text(
                                        'Sign up',
                                        style: TextStyle(
                                          color: AppPalette.of(context).accent,
                                          fontWeight: FontWeight.w700,
                                          fontSize: roomyPhone ? 16 : 13.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                TextButton(
                                  onPressed: () => context.push('/privacy'),
                                  child: const Text('Privacy Policy'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The auth screen an error is shown on: each has its own last-resort line,
/// so a failed sign-up never reads "Could not log in".
enum AuthErrorScreen {
  login('Could not log in. Please try again.'),
  signUp('Could not create your account. Please try again.'),
  forgotPassword('Could not send the reset email. Please try again.'),
  resetPassword('Could not change your password. Please try again.');

  const AuthErrorScreen(this.fallback);

  /// Shown for a failure nothing below recognises.
  final String fallback;
}

/// Shown when the recovery link (or the temporary session it opened) is no
/// longer good.
const resetLinkExpiredMessage =
    'This reset link has expired. Request a new one from Forgot password.';

/// GoTrue codes for a recovery link or session that is no longer usable
/// (`ErrorCode` in the gotrue package).
const _expiredLinkCodes = {
  'otp_expired',
  'session_not_found',
  'session_missing',
  'session_expired',
  'flow_state_expired',
  'flow_state_not_found',
};

/// True when [e] says sign-up was refused because the address already has
/// an account: AuthRepository's own exception, or Supabase's error code.
/// A reply from a server too old to send codes is recognised by its text.
bool isEmailAlreadyRegisteredError(Object e) {
  if (e is EmailAlreadyRegisteredException) return true;
  if (e is! AuthException) return false;
  final code = (e.code ?? '').toLowerCase();
  if (code.isNotEmpty) {
    return code == 'user_already_exists' || code == 'email_exists';
  }
  final message = e.message.toLowerCase();
  return message.contains('already registered') ||
      message.contains('already exists');
}

/// True when [e] means the password-reset link has expired or its session
/// is gone. On the Set New Password screen ([duringRecovery]) any 401 / 403
/// means the same: the only session there is the one the link opened.
bool isExpiredResetLinkError(Object e, {bool duringRecovery = false}) {
  if (e is! AuthException) return false;
  if (e is AuthSessionMissingException) return true;
  final code = (e.code ?? '').toLowerCase();
  if (_expiredLinkCodes.contains(code)) return true;
  if (e.message.toLowerCase().contains('auth session missing')) return true;
  return duringRecovery && (e.statusCode == '401' || e.statusCode == '403');
}

/// Maps an auth failure to short, user-safe copy — shared by the Log In,
/// Sign Up, Forgot password and Set New Password screens, each passing the
/// [screen] it is. Raw Supabase / Postgres / SDK text never reaches the
/// screen: a Supabase [AuthException] is mapped by its code and status, the
/// SDK failures by what they are, and only an [AuthRepositoryException] —
/// copy AuthRepository wrote for the customer — is shown as it is.
String friendlyAuthError(Object e, AuthErrorScreen screen) {
  final fallback = screen.fallback;
  if (e is AuthRepositoryException) return e.message;
  if (e is AuthException) {
    final code = (e.code ?? '').toLowerCase();
    final message = e.message.toLowerCase();
    if (e.statusCode == '429' ||
        code == 'over_email_send_rate_limit' ||
        code.contains('rate_limit')) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    if (isExpiredResetLinkError(
      e,
      duringRecovery: screen == AuthErrorScreen.resetPassword,
    )) {
      return resetLinkExpiredMessage;
    }
    if (code == 'same_password') {
      return "Choose a password you haven't used before.";
    }
    if (code == 'invalid_credentials' ||
        message.contains('invalid login credentials')) {
      return 'Email or password is incorrect. Try again, use Forgot password, or Sign up for a new account.';
    }
    if (code == 'email_not_confirmed' ||
        message.contains('email not confirmed')) {
      return 'Please confirm your email from the link we sent, then try again.';
    }
    if (isEmailAlreadyRegisteredError(e)) {
      return const EmailAlreadyRegisteredException().message;
    }
    if (code == 'weak_password' ||
        (message.contains('password') &&
            (message.contains('weak') || message.contains('short')))) {
      return 'Please choose a stronger password: at least 8 characters with a letter and a number.';
    }
    if (e is AuthRetryableFetchException) {
      return 'Network error — check your connection and try again.';
    }
    return fallback;
  }
  // Google / Apple SDK failures and transport errors: recognised by kind,
  // answered with fixed copy.
  final raw = e.toString().toLowerCase();
  if (raw.contains('cancelled') || raw.contains('canceled')) {
    return 'Sign-in was cancelled.';
  }
  if (raw.contains('network') ||
      raw.contains('socket') ||
      raw.contains('failed host lookup') ||
      raw.contains('clientexception')) {
    return 'Network error — check your connection and try again.';
  }
  return fallback;
}
