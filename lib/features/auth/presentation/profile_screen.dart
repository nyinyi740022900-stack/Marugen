import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../profile/presentation/address_book_screen.dart';
import '../../shop/presentation/shell_tab_provider.dart';
import '../../wishlist/presentation/wishlist_screen.dart';
import 'auth_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
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
  bool _uploadingAvatar = false;
  // Optimistic override, same reasoning as _notificationsOverride: avoid
  // ref.invalidate(currentAppUserProvider) (router-rebuild jank) for a
  // change that only needs this screen's own avatar to update instantly.
  String? _avatarUrlOverride;

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
      final url = await ref.read(authRepositoryProvider).uploadAvatar(bytes, ext);
      if (mounted) setState(() => _avatarUrlOverride = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update photo: $e')),
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
        SnackBar(content: Text('Could not log out: $e')),
      );
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() => _notificationsOverride = value);
    try {
      await ref.read(authRepositoryProvider).updateNotificationsEnabled(value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _notificationsOverride = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update notification setting: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentAppUserProvider);
    final isLoggedIn = ref.watch(isLoggedInProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: !isLoggedIn
          ? const _GuestProfile()
          : userAsync.when(
              data: (user) => ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _uploadingAvatar ? null : _pickAvatar,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Builder(builder: (context) {
                            final avatarUrl = _avatarUrlOverride ?? user?.avatarUrl;
                            return CircleAvatar(
                              radius: 36,
                              backgroundColor: AppColors.offWhite,
                              backgroundImage:
                                  avatarUrl != null ? NetworkImage(avatarUrl) : null,
                              child: avatarUrl == null
                                  ? const Icon(Icons.person, size: 36, color: AppColors.grey)
                                  : null,
                            );
                          }),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: AppColors.red,
                                shape: BoxShape.circle,
                                border: Border.fromBorderSide(
                                  BorderSide(color: AppColors.white, width: 2),
                                ),
                              ),
                              child: _uploadingAvatar
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 1.5, color: AppColors.white),
                                    )
                                  : const Icon(Icons.camera_alt,
                                      size: 12, color: AppColors.white),
                            ),
                          ),
                        ],
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
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (user?.email != null)
                    Center(
                      child: Text(user!.email!,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.grey)),
                    ),
                  const SizedBox(height: 24),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: const Text('Delivery Addresses'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AddressBookScreen()),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.favorite_border),
                    title: const Text('Wishlist'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WishlistScreen()),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: const Text('Order History'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => ref.read(customerTabIndexProvider.notifier).state = 2,
                  ),
                  Builder(builder: (context) {
                    final notificationsEnabled =
                        _notificationsOverride ?? user?.notificationsEnabled ?? true;
                    return SwitchListTile(
                      secondary: const Icon(Icons.notifications_outlined),
                      title: const Text('Notifications'),
                      subtitle: Text(
                        notificationsEnabled
                            ? 'Push alerts for order updates are on'
                            : 'Push alerts are off — order status still shows in-app',
                        style: const TextStyle(fontSize: 12, color: AppColors.grey),
                      ),
                      value: notificationsEnabled,
                      onChanged: _toggleNotifications,
                    );
                  }),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('FAQ & Support'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/faq'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Terms of Service'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/terms'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('Privacy Policy'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/privacy'),
                  ),
                  const Divider(),
                  ListTile(
                    leading: _signingOut
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error),
                          )
                        : const Icon(Icons.logout, color: AppColors.error),
                    title: const Text('Log Out', style: TextStyle(color: AppColors.error)),
                    enabled: !_signingOut,
                    onTap: _confirmSignOut,
                  ),
                ],
              ),
              loading: () => const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
    );
  }
}

/// Shown on the Profile tab when browsing as a guest — invites login
/// instead of showing broken/empty account fields.
class _GuestProfile extends StatelessWidget {
  const _GuestProfile();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.person_outline,
      title: 'You are not logged in',
      subtitle: 'Log in to see your profile, saved addresses and order history.',
      actionLabel: 'Log In',
      onAction: () => context.push('/login'),
    );
  }
}
