import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/address.dart';
import '../../../shared/models/order.dart' show orderStatusLabel;
import '../../../shared/utils/price_format.dart';
import '../../../shared/widgets/empty_state.dart';
import 'admin_customer_providers.dart';

/// Admin-only: a customer's profile, saved addresses, and full order
/// history — reached by tapping the profile icon on an order that isn't
/// the admin's own (see [order_detail_screen.dart]'s AppBar actions).
class AdminCustomerProfileScreen extends ConsumerWidget {
  final String userId;
  const AdminCustomerProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(customerProfileProvider(userId));
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: Text(profileAsync.valueOrNull?.fullName ?? 'Customer Profile'),
      ),
      body: profileAsync.when(
        data: (user) {
          if (user == null) {
            return const EmptyState(
              icon: Icons.person_off_outlined,
              title: 'Customer not found',
              subtitle: 'This account may have been removed.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: AppShadows.card,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.redSoft,
                      backgroundImage:
                          user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
                      child: user.avatarUrl == null
                          ? Text(
                              (user.fullName?.isNotEmpty ?? false)
                                  ? user.fullName![0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 20),
                            )
                          : null,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.fullName ?? 'No name on file',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          if (user.email != null) ...[
                            const SizedBox(height: 2),
                            Text(user.email!,
                                style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                          ],
                          if (user.phone != null) ...[
                            const SizedBox(height: 2),
                            Text(user.phone!,
                                style: const TextStyle(color: AppColors.grey, fontSize: 13)),
                          ],
                          if (user.createdAt != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Member since ${DateFormat.yMMMd().format(user.createdAt!)}',
                              style: const TextStyle(color: AppColors.greySoft, fontSize: 11.5),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionHeader('SAVED ADDRESSES'),
              const SizedBox(height: AppSpacing.sm),
              _AddressesSection(userId: userId),
              const SizedBox(height: AppSpacing.xl),
              const _SectionHeader('ORDER HISTORY'),
              const SizedBox(height: AppSpacing.sm),
              _OrderHistorySection(userId: userId),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.red)),
        error: (e, _) =>
            ErrorState(onRetry: () => ref.invalidate(customerProfileProvider(userId))),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.8, color: AppColors.grey));
  }
}

class _AddressesSection extends ConsumerWidget {
  final String userId;
  const _AddressesSection({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressesAsync = ref.watch(customerAddressesProvider(userId));
    return addressesAsync.when(
      data: (addresses) {
        if (addresses.isEmpty) {
          return const _EmptyCard(text: 'No saved addresses.');
        }
        return Column(
          children: [
            for (final a in addresses) ...[
              _AddressCard(address: a),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator(color: AppColors.red, strokeWidth: 2)),
      ),
      error: (e, _) => _EmptyCard(text: 'Could not load addresses: $e'),
    );
  }
}

class _AddressCard extends StatelessWidget {
  final Address address;
  const _AddressCard({required this.address});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on_outlined, size: 18, color: AppColors.grey),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(address.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (address.isDefault) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.redSoft,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: const Text('Default',
                            style: TextStyle(fontSize: 10, color: AppColors.redDark)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text('${address.recipientName} · ${address.phone}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.grey)),
                const SizedBox(height: 2),
                Text(address.oneLine, style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderHistorySection extends ConsumerWidget {
  final String userId;
  const _OrderHistorySection({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(customerOrdersProvider(userId));
    return ordersAsync.when(
      data: (orders) {
        if (orders.isEmpty) {
          return const _EmptyCard(text: 'No orders yet.');
        }
        return Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            children: [
              for (var i = 0; i < orders.length; i++) ...[
                if (i != 0) const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
                ListTile(
                  title: Text('Order #${orders[i].displayNumber}'),
                  subtitle: Text(
                    '${orderStatusLabel(orders[i].status)} · '
                    '${DateFormat.yMMMd().format(orders[i].createdAt)}',
                  ),
                  trailing: Text(formatPrice(orders[i].total),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => context.push('/orders/${orders[i].id}', extra: orders[i]),
                ),
              ],
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator(color: AppColors.red, strokeWidth: 2)),
      ),
      error: (e, _) => _EmptyCard(text: 'Could not load order history: $e'),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;
  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(text, style: const TextStyle(color: AppColors.grey, fontSize: 13)),
    );
  }
}
