import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_providers.dart';
import '../theme/app_theme.dart';
import '../../shared/widgets/brand_logo.dart';

/// Shown while the session and the signed-in user's role resolve. When the
/// profile cannot be loaded the router keeps the user here (see the redirect
/// in app_router.dart) rather than guessing a role, so this screen has to
/// offer the way forward: retry, or sign out.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(currentAppUserProvider);
    final profileFailed = appUser.hasError && !appUser.isLoading;
    return Scaffold(
      backgroundColor: AppPalette.of(context).surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandLogo(size: 120),
                SizedBox(height: 20),
                Text(
                  'MARUGEN FISH FARM',
                  style: TextStyle(
                    color: AppPalette.of(context).text,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 28),
                if (profileFailed)
                  const _ProfileLoadFailed()
                else
                  CircularProgressIndicator(
                    color: AppPalette.of(context).accent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileLoadFailed extends ConsumerStatefulWidget {
  const _ProfileLoadFailed();

  @override
  ConsumerState<_ProfileLoadFailed> createState() => _ProfileLoadFailedState();
}

class _ProfileLoadFailedState extends ConsumerState<_ProfileLoadFailed> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (_) {
      // Still signed in: the Retry / Sign out choice stays on screen.
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            "We couldn't load your account. Check your connection and try "
            'again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppPalette.of(context).textMuted),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ElevatedButton(
          onPressed: _signingOut
              ? null
              : () => ref.invalidate(currentAppUserProvider),
          child: const Text('Retry'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: _signingOut ? null : _signOut,
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}
