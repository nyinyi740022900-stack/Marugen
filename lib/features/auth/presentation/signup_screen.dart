import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/content_width.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/email_validator.dart';
import '../../../shared/utils/error_message.dart';
import '../../../shared/utils/password_validator.dart';
import '../../orders/presentation/purchase_intent.dart'
    show authRouteWithRedirect;
import 'auth_providers.dart';
import 'login_screen.dart' show friendlyAuthError;

class SignupScreen extends ConsumerStatefulWidget {
  /// How long "Resend email" stays disabled after an email goes out (the
  /// sign-up one included). Supabase refuses a second email to the same
  /// address inside a minute, so an earlier tap could only fail.
  final Duration resendCooldown;

  const SignupScreen({
    super.key,
    this.resendCooldown = const Duration(seconds: 60),
  });

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _oauthLoading = false;
  String? _error;

  /// Set once sign-up succeeded without a session: the address the
  /// confirmation link went to. Replaces the form with the confirm state.
  String? _confirmEmail;
  bool _resending = false;
  int _cooldownLeft = 0;
  Timer? _cooldownTimer;
  String? _resendInfo;
  String? _resendError;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _nameCtrl.dispose();
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
    final email = _emailCtrl.text.trim();
    try {
      final needsConfirmation = await ref
          .read(authRepositoryProvider)
          .signUpWithEmail(
            email,
            _passwordCtrl.text,
            fullName: _nameCtrl.text.trim(),
          );
      // With a session the router redirect takes the customer onward.
      if (mounted && needsConfirmation) {
        setState(() => _confirmEmail = email);
        _startCooldown();
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldownLeft = widget.resendCooldown.inSeconds;
    if (_cooldownLeft <= 0) return;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldownLeft--);
      if (_cooldownLeft <= 0) timer.cancel();
    });
  }

  Future<void> _resend() async {
    final email = _confirmEmail;
    if (email == null || _resending || _cooldownLeft > 0) return;
    setState(() {
      _resending = true;
      _resendInfo = null;
      _resendError = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .resendVerificationEmail(email: email);
      if (!mounted) return;
      setState(() => _resendInfo = 'Email sent again.');
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _resendError = friendlyErrorMessage(
          e,
          fallback:
              'Could not send the email. Check your connection and try again.',
          context: 'auth.resend_confirmation',
        ),
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  /// Back to the Log In screen this one was opened from (it still holds
  /// the redirect); from a direct link, open Log In with the same redirect.
  void _goToLogin() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(
      authRouteWithRedirect(
        '/login',
        GoRouterState.of(context).uri.queryParameters['redirect'],
      ),
    );
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
    final confirmEmail = _confirmEmail;
    if (confirmEmail != null) {
      return Scaffold(
        backgroundColor: AppPalette.of(context).surface,
        appBar: AppBar(
          title: const Text('Create Account'),
          backgroundColor: AppColors.black,
        ),
        body: ContentWidth(
          maxWidth: 560,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: _ConfirmEmailState(
                email: confirmEmail,
                resending: _resending,
                cooldownLeft: _cooldownLeft,
                info: _resendInfo,
                error: _resendError,
                onLogin: _goToLogin,
                onResend: _resend,
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppPalette.of(context).surface,
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: AppColors.black,
      ),
      body: ContentWidth(
        maxWidth: 560,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: AutofillGroup(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Join Marugen',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Create an account to order and track deliveries',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppPalette.of(context).textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextFormField(
                      controller: _nameCtrl,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        errorMaxLines: 4,
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.person_outline, size: 20),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
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
                        prefixIcon: Icon(Icons.mail_outline, size: 20),
                      ),
                      validator: validateEmail,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        errorMaxLines: 4,
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                            color: AppPalette.of(context).textMuted,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: validateNewPassword,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppPalette.of(context).accentSoft,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
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
                    const SizedBox(height: AppSpacing.lg),
                    RichText(
                      textScaler: MediaQuery.textScalerOf(context),
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          fontSize: 12,
                          color: AppPalette.of(context).textMuted,
                          height: 1.4,
                        ),
                        children: [
                          const TextSpan(
                            text: 'By signing up you agree to our ',
                          ),
                          TextSpan(
                            text: 'Terms of Service',
                            style: TextStyle(
                              color: AppPalette.of(context).accent,
                              fontWeight: FontWeight.w600,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => context.push('/terms'),
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: TextStyle(
                              color: AppPalette.of(context).accent,
                              fontWeight: FontWeight.w600,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => context.push('/privacy'),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
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
                          : const Text('Sign Up'),
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
                    if (Theme.of(context).platform !=
                        TargetPlatform.android) ...[
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
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the form once the account exists but its email is not
/// confirmed yet: says where the link went and what to do next.
class _ConfirmEmailState extends StatelessWidget {
  final String email;
  final bool resending;
  final int cooldownLeft;
  final String? info;
  final String? error;
  final VoidCallback onLogin;
  final VoidCallback onResend;

  const _ConfirmEmailState({
    required this.email,
    required this.resending,
    required this.cooldownLeft,
    required this.info,
    required this.error,
    required this.onLogin,
    required this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final message = error ?? info;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Icon(Icons.mark_email_unread_outlined, size: 48, color: palette.accent),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: const Text(
            'Confirm your email',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'We sent a link to $email. Open it, then come back and log in.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.4,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ElevatedButton(onPressed: onLogin, child: const Text('Go to Log In')),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton(
          onPressed: resending || cooldownLeft > 0 ? null : onResend,
          child: resending
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  cooldownLeft > 0
                      ? 'Resend email in ${cooldownLeft}s'
                      : 'Resend email',
                ),
        ),
        // Announced when it changes; the space is not reserved because the
        // buttons above it never move.
        Semantics(
          liveRegion: true,
          child: message == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: error != null ? palette.error : palette.success,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
