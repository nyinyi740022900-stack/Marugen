import '../../../shared/widgets/sized_network_image.dart'
    show avatarImageMaxSide;

import 'package:flutter/material.dart';

import '../../../shared/widgets/bottom_inset.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/notifications/push_permission_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/appearance_tile.dart';
import '../../../shared/utils/error_message.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/guest_account_state.dart';
import '../../../shared/widgets/content_width.dart';
import '../../../shared/widgets/support_contact_picker.dart';
import '../../orders/data/order_repository.dart' show OrderInProgress;
import '../../orders/presentation/orders_providers.dart';
import '../../shop/presentation/shell_tab_provider.dart';
import 'account_details_tiles.dart';
import 'auth_providers.dart';
import 'profile_help_section.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

/// What the customer chose when warned that an order is still on its way.
enum _InProgressChoice { keep, contact, delete }

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with WidgetsBindingObserver {
  // Optimistic override for the notification switch — null means "trust
  // the server value from currentAppUserProvider". Toggling used to call
  // ref.invalidate(currentAppUserProvider), which is also what GoRouter's
  // refreshListenable watches (see _GoRouterRefreshStream in
  // app_router.dart) — invalidating it re-ran the router's redirect logic
  // and rebuilt the whole CustomerShell (bottom nav included) on every
  // toggle, which is what showed up as the screen visibly jittering.
  // Nothing else on screen needs a fresh fetch for a boolean flip, so this
  // just flips local state instantly and fires the write in the
  // background instead.
  bool? _notificationsOverride;
  bool _signingOut = false;
  bool _deletingAccount = false;
  bool _uploadingAvatar = false;
  // Optimistic override, same reasoning as _notificationsOverride: avoid
  // ref.invalidate(currentAppUserProvider) (router-rebuild jank) for a
  // change that only needs this screen's own avatar to update instantly.
  String? _avatarUrlOverride;

  /// What the phone says about notifications for this app. The switch is
  /// only "on" when the account setting and the phone both allow them.
  PushPermission _osPermission = PushPermission.unknown;
  bool _requestingPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readOsPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the phone's Settings: the answer may have changed there.
    if (state == AppLifecycleState.resumed) _readOsPermission();
  }

  Future<void> _readOsPermission() async {
    final permission = await ref
        .read(pushPermissionControllerProvider)
        .current();
    if (mounted && permission != _osPermission) {
      setState(() => _osPermission = permission);
    }
  }

  bool get _osAllowsPush =>
      _osPermission == PushPermission.authorized ||
      _osPermission == PushPermission.unknown;

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: avatarImageMaxSide,
      maxHeight: avatarImageMaxSide,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.')
          ? picked.name.split('.').last
          : 'jpg';
      final url = await ref
          .read(authRepositoryProvider)
          .uploadAvatar(bytes, ext);
      if (mounted) setState(() => _avatarUrlOverride = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorMessage(
                e,
                fallback:
                    'Your photo was not updated. Check your connection and try again.',
                context: 'profile.avatar',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await confirmLogout(context);
    if (!confirmed) return;

    setState(() => _signingOut = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
      // Router redirect handles navigation once auth state updates.
    } catch (e) {
      if (!mounted) return;
      setState(() => _signingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You are still signed in. Check your connection and try logging out again.',
          ),
        ),
      );
    }
  }

  /// The customer's order that is still in progress, if any. A failed
  /// check never blocks deletion: the server decides that.
  Future<OrderInProgress?> _orderInProgress() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return null;
    try {
      return await ref
          .read(orderRepositoryProvider)
          .fetchNewestOrderInProgress(userId);
    } catch (_) {
      // Fall through to the ordinary confirmation.
      return null;
    }
  }

  Future<void> _confirmDeleteAccount() async {
    if (_deletingAccount) return;
    setState(() => _deletingAccount = true);
    final inProgress = await _orderInProgress();
    if (!mounted) return;
    setState(() => _deletingAccount = false);
    if (inProgress != null) {
      // A warning, never a refusal: the account can always be deleted here.
      final choice = await showAdaptiveDialog<_InProgressChoice>(
        context: context,
        builder: (dialogContext) => AlertDialog.adaptive(
          title: const Text('You have an order in progress'),
          content: Text(
            'Order #${inProgress.displayNumber} is still on its way. If you '
            "delete your account now you won't be able to track it or "
            'request a cancellation in the app. The order itself is not '
            'cancelled.',
          ),
          actions: [
            adaptiveDialogAction(
              dialogContext,
              label: 'Keep my account',
              primary: true,
              onPressed: () =>
                  Navigator.pop(dialogContext, _InProgressChoice.keep),
            ),
            adaptiveDialogAction(
              dialogContext,
              label: 'Contact support',
              onPressed: () =>
                  Navigator.pop(dialogContext, _InProgressChoice.contact),
            ),
            adaptiveDialogAction(
              dialogContext,
              label: 'Delete anyway',
              destructive: true,
              onPressed: () =>
                  Navigator.pop(dialogContext, _InProgressChoice.delete),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == _InProgressChoice.contact) {
        await showSupportContactPicker(
          context,
          message:
              'Hi, I would like to delete my account but order '
              '#${inProgress.displayNumber} is still in progress.',
        );
        return;
      }
      // Dismissed, or "Keep my account".
      if (choice != _InProgressChoice.delete) return;
    }
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete your account?',
      message:
          'This permanently removes your profile, saved addresses, wishlist, and reviews. '
          'This cannot be undone. (Past orders are kept for accounting/tax records, with '
          'necessary order, payment and delivery details retained.)',
      confirmLabel: 'Delete Account',
    );
    if (!confirmed) return;

    setState(() => _deletingAccount = true);
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      // Router redirect handles navigation once auth state updates.
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingAccount = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback:
                  'Your account was not deleted. Check your connection and try again, or contact support.',
              context: 'profile.deleteAccount',
            ),
          ),
        ),
      );
    }
  }

  /// "Notifications are off on this phone" cannot be fixed by a switch in
  /// the app: say where it is fixed, and open it where the platform lets us.
  void _showTurnOnInSettings() {
    final controller = ref.read(pushPermissionControllerProvider);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text(
            'Turn on notifications for Marugen in Settings',
          ),
          action: controller.canOpenSettings
              ? SnackBarAction(
                  label: 'Open Settings',
                  onPressed: controller.openSettings,
                )
              : null,
        ),
      );
  }

  Future<void> _toggleNotifications(bool value) async {
    if (value && !_osAllowsPush) {
      // The account may well say "on" already; the phone is what is off.
      if (_requestingPermission) return;
      if (_osPermission == PushPermission.blocked) {
        _showTurnOnInSettings();
        return;
      }
      setState(() => _requestingPermission = true);
      final granted = await ref
          .read(pushPermissionControllerProvider)
          .request();
      if (!mounted) return;
      setState(() {
        _requestingPermission = false;
        _osPermission = granted;
      });
      if (granted != PushPermission.authorized) {
        _showTurnOnInSettings();
        return;
      }
    }
    setState(() => _notificationsOverride = value);
    try {
      await ref.read(authRepositoryProvider).updateNotificationsEnabled(value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _notificationsOverride = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your notification setting was restored. Check your connection and try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentAppUserProvider);
    final isLoggedIn = ref.watch(isLoggedInProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: const [AppearanceButton(), SizedBox(width: 4)],
      ),
      body: ContentWidth(
        child: !isLoggedIn
            ? const _GuestProfile()
            : userAsync.when(
                data: (user) => ListView(
                  padding: EdgeInsets.all(20).plusBottomInset(context),
                  children: [
                    Center(
                      child: Semantics(
                        label: 'Change profile photo',
                        button: true,
                        child: GestureDetector(
                          onTap: _uploadingAvatar ? null : _pickAvatar,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Builder(
                                builder: (context) {
                                  final avatarUrl =
                                      _avatarUrlOverride ?? user?.avatarUrl;
                                  return CircleAvatar(
                                    radius: 36,
                                    backgroundColor: AppPalette.of(context)
                                        .surfaceMuted,
                                    backgroundImage: avatarUrl != null
                                        ? NetworkImage(avatarUrl)
                                        : null,
                                    child: avatarUrl == null
                                        ? Icon(
                                            Icons.person,
                                            size: 36,
                                            color: AppPalette.of(context)
                                                .textMuted,
                                          )
                                        : null,
                                  );
                                },
                              ),
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: const BoxDecoration(
                                    color: AppColors.red,
                                    shape: BoxShape.circle,
                                    border: Border.fromBorderSide(
                                      BorderSide(
                                        color: AppColors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: _uploadingAvatar
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: AppColors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.camera_alt,
                                          size: 12,
                                          color: AppColors.white,
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        user?.fullName ?? user?.email ?? 'Guest',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (user?.email != null)
                      Center(
                        child: Text(
                          user!.email!,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppPalette.of(context).textMuted,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    const Divider(),
                    AccountDetailsTiles(
                      fullName: user?.fullName,
                      usesPassword: user?.usesPassword ?? false,
                    ),
                    ListTile(
                      leading: const Icon(Icons.location_on_outlined),
                      title: const Text('Delivery Addresses'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/addresses'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.favorite_border),
                      title: const Text('Wishlist'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/wishlist'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Order History'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          ref.read(customerTabIndexProvider.notifier).state = 2,
                    ),
                    Builder(
                      builder: (context) {
                        final accountEnabled =
                            _notificationsOverride ??
                            user?.notificationsEnabled ??
                            true;
                        // Never "on" while the phone would not show them.
                        final notificationsEnabled =
                            accountEnabled && _osAllowsPush;
                        return SwitchListTile(
                          secondary: const Icon(Icons.notifications_outlined),
                          title: const Text('Notifications'),
                          subtitle: Text(
                            !_osAllowsPush
                                ? 'Notifications are off on this phone'
                                : notificationsEnabled
                                ? 'Push alerts for order updates are on'
                                : 'Push alerts are off — order status still shows in-app',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppPalette.of(context).textMuted,
                            ),
                          ),
                          value: notificationsEnabled,
                          onChanged: _toggleNotifications,
                        );
                      },
                    ),
                    const Divider(),
                    const ProfileHelpTiles(),
                    const Divider(),
                    ListTile(
                      leading: _signingOut
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppPalette.of(context).error,
                              ),
                            )
                          : Icon(
                              Icons.logout,
                              color: AppPalette.of(context).error,
                            ),
                      title: Text(
                        'Log Out',
                        style: TextStyle(color: AppPalette.of(context).error),
                      ),
                      enabled: !_signingOut,
                      onTap: _confirmSignOut,
                    ),
                    ListTile(
                      leading: _deletingAccount
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppPalette.of(context).error,
                              ),
                            )
                          : Icon(
                              Icons.delete_forever_outlined,
                              color: AppPalette.of(context).error,
                            ),
                      title: Text(
                        'Delete My Account',
                        style: TextStyle(color: AppPalette.of(context).error),
                      ),
                      enabled: !_deletingAccount,
                      onTap: _confirmDeleteAccount,
                    ),
                    const AppVersionFooter(),
                  ],
                ),
                loading: () => const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
                error: (e, _) => ErrorState(
                  subtitle: "We couldn't load your profile. Check your connection and retry.",
                  onRetry: () => ref.invalidate(currentAppUserProvider),
                ),
              ),
      ),
    );
  }
}

/// Shown on the Profile tab when browsing as a guest — invites login
/// instead of showing broken/empty account fields, with help, legal and
/// feedback still within reach underneath.
class _GuestProfile extends StatelessWidget {
  const _GuestProfile();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 20).plusBottomInset(context),
      children: const [
        GuestAccountState(
          icon: Icons.person_outline,
          subtitle: 'View your profile and saved addresses.',
          returnTo: '/?tab=profile',
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [Divider(), ProfileHelpTiles(), AppVersionFooter()],
          ),
        ),
      ],
    );
  }
}
