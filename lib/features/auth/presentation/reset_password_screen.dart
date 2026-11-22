import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/password_validator.dart';
import 'auth_providers.dart';
import 'login_screen.dart'
    show AuthErrorScreen, friendlyAuthError, isExpiredResetLinkError;

/// Shown when the app is opened via the password-reset email link.
/// Supabase creates a temporary session for this (`AuthChangeEvent
/// .passwordRecovery`, see app_router.dart's redirect) — this screen's
/// only job is to let the user set a new password for that session.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _done = false;
  String? _error;

  /// The link (or the session it opened) is no longer good: nothing typed
  /// here can succeed, so the way out to a new link is offered.
  bool _linkExpired = false;
  bool _leaving = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || _leaving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _linkExpired = false;
    });
    try {
      await ref.read(authRepositoryProvider).updatePassword(_passwordCtrl.text);
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyAuthError(e, AuthErrorScreen.resetPassword);
          _linkExpired = isExpiredResetLinkError(e, duringRecovery: true);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Back to Forgot password for a new link. The router holds this screen
  /// for as long as the recovery session is the current auth event, so
  /// what is left of that session is ended first.
  Future<void> _requestNewLink() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (_) {
      // Already gone, or offline: Forgot password works signed out or not.
    }
    if (!mounted) return;
    setState(() => _leaving = false);
    context.go('/forgot-password');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set New Password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: _done ? _buildSuccess(context) : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose a new password',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter and confirm your new password below.',
            style: TextStyle(
              fontSize: 13.5,
              color: AppPalette.of(context).textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              errorMaxLines: 4,
              labelText: 'New password',
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
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _confirmCtrl,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              errorMaxLines: 4,
              labelText: 'Confirm password',
              prefixIcon: Icon(Icons.lock_outline, size: 20),
            ),
            validator: (v) =>
                (v != _passwordCtrl.text) ? 'Passwords do not match' : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            // Announced the moment it appears.
            Semantics(
              liveRegion: true,
              child: Container(
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
            ),
            if (_linkExpired) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: _leaving ? null : _requestNewLink,
                child: const Text('Go to Forgot password'),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.xl),
          ElevatedButton(
            onPressed: _loading || _leaving ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.white,
                    ),
                  )
                : const Text('Update Password'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppPalette.of(context).background,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle_outline,
            size: 32,
            color: AppPalette.of(context).accent,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text(
          'Password updated',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Your password has been changed. Continue to the app.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            color: AppPalette.of(context).textMuted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        ElevatedButton(
          onPressed: () => context.go('/'),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
