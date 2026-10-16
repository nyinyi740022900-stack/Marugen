import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/content_width.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _oauthSignIn(Future<void> Function() signIn) async {
    setState(() {
      _oauthLoading = true;
      _error = null;
    });
    try {
      await signIn();
      // Router redirect handles navigation once the OAuth redirect lands
      // and auth state updates.
    } catch (e) {
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _oauthLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              systemOverlayStyle:
                  Theme.of(context).brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
            )
          : null,
      body: ContentWidth(
        maxWidth: 560,
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // The hero and form scroll together, including above the keyboard.
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    MediaQuery.of(context).size.height < 700
                        ? AppSpacing.md
                        : AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.md,
                  ),
                  child: Column(
                    children: [
                      BrandLogo(
                        size: MediaQuery.of(context).size.height < 700
                            ? 64
                            : 88,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'MARUGEN FISH FARM',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppPalette.of(context).text,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 3,
                        ),
                      ),
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
                      MediaQuery.of(context).size.height < 700
                          ? AppSpacing.lg
                          : AppSpacing.xxl,
                      AppSpacing.xl,
                      MediaQuery.of(context).padding.bottom + AppSpacing.xl,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Welcome back',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Log in to continue shopping',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: AppPalette.of(context).textMuted,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline, size: 20),
                            ),
                            validator: (v) => (v == null || !v.contains('@'))
                                ? 'Enter a valid email'
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
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
                              onPressed: () => context.push('/forgot-password'),
                              child: Text(
                                'Forgot password?',
                                style: TextStyle(
                                  color: AppPalette.of(context).textMuted,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: AppSpacing.md),
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
                          const SizedBox(height: AppSpacing.xl),
                          ElevatedButton(
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
                          const SizedBox(height: AppSpacing.xl),
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
                          const SizedBox(height: AppSpacing.lg),
                          OutlinedButton.icon(
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
                          const SizedBox(height: AppSpacing.md),
                          OutlinedButton.icon(
                            onPressed: _oauthLoading
                                ? null
                                : () => _oauthSignIn(
                                    () => ref
                                        .read(authRepositoryProvider)
                                        .signInWithApple(),
                                  ),
                            icon: const Icon(Icons.apple, size: 20),
                            label: const Text('Continue with Apple'),
                          ),
                          const SizedBox(height: AppSpacing.lg),
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
                                  fontSize: 13.5,
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
                                    fontSize: 13.5,
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
    return 'Please choose a stronger password (at least 6 characters).';
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
