import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../profile/presentation/address_book_screen.dart';
import '../../shop/presentation/shell_tab_provider.dart';
import '../../wishlist/presentation/wishlist_screen.dart';
import 'auth_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: AppColors.offWhite,
                    child: const Icon(Icons.person, size: 36, color: AppColors.grey),
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
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('Notifications'),
                    subtitle: const Text('Order updates are sent automatically',
                        style: TextStyle(fontSize: 12, color: AppColors.grey)),
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'You\'ll be notified automatically about your order status.'),
                      ),
                    ),
                  ),
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
                    leading: const Icon(Icons.logout, color: AppColors.error),
                    title: const Text('Log Out', style: TextStyle(color: AppColors.error)),
                    onTap: () => ref.read(authRepositoryProvider).signOut(),
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
