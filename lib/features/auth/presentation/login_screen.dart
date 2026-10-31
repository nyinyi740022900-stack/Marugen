import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/content_width.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    show SignInWithAppleButton, SignInWithAppleButtonStyle;
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/brand_logo.dart';
import 'auth_providers.dart';
import '../../orders/presentation/purchase_intent.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _oauthLoading = false;
  String? _error;

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
      if (mounted) setState(() => _error = friendlyAuthError(e));
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
      if (mounted) setState(() => _error = friendlyAuthError(e));
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
                                decoration: const InputDecoration(
                                  errorMaxLines: 4,
                                  labelText: 'Email',
                                  prefixIcon: Icon(
                                    Icons.mail_outline,
                                    size: 20,
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null || !v.contains('@'))
                                    ? 'Enter a valid email'
                                    : null,
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
                                Container(
                                  padding: const EdgeInsets.all(AppSpacing.md),
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
                                        color: AppPalette.of(context).textMuted,
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
                                icon: const Icon(Icons.g_mobiledata, size: 24),
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
                                    onPressed: () => context.push(
                                      authRouteWithRedirect(
                                        '/signup',
                                        GoRouterState.of(context)
                                            .uri
                                            .queryParameters['redirect'],
                                      ),
                                    ),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Maps a raw auth exception to short, user-safe copy — shared by
/// LoginScreen and SignupScreen so signup failures (e.g. "duplicate key
/// value violates unique constraint") never leak raw Postgres/Supabase
/// error text to the UI.
String friendlyAuthError(Object e) {
  final raw = e.toString().toLowerCase();
  if (raw.contains('invalid login credentials') ||
      raw.contains('invalid_credentials')) {
    return 'Email or password is incorrect. Try again, use Forgot password, or Sign up for a new account.';
  }
  if (raw.contains('email not confirmed')) {
    return 'Please confirm your email from the link we sent, then try again.';
  }
  if (raw.contains('already registered') || raw.contains('already exists')) {
    return 'An account with this email already exists. Try logging in instead.';
  }
  if (raw.contains('password') &&
      (raw.contains('weak') || raw.contains('short'))) {
    return 'Please choose a stronger password: at least 8 characters with a letter and a number.';
  }
  if (raw.contains('google sign-in is not configured') ||
      raw.contains('google_web_client_id')) {
    return 'Google Sign-In is not set up yet. Add Google client IDs to .env (see README).';
  }
  if (raw.contains('cancelled') || raw.contains('canceled')) {
    return 'Sign-in was cancelled.';
  }
  if (raw.contains('network') || raw.contains('socket')) {
    return 'Network error — check your connection and try again.';
  }
  // Prefer short Exception messages we throw from AuthRepository.
  if (e is Exception) {
    final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    if (msg.isNotEmpty && msg.length < 180) return msg;
  }
  return 'Could not log in. Please try again.';
}
