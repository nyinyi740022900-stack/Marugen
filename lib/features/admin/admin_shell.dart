import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'analytics/admin_analytics_screen.dart';
import 'dashboard/admin_dashboard_screen.dart';
import 'knowledge/admin_knowledge_screen.dart';
import 'orders/admin_orders_screen.dart';
import 'products/admin_products_screen.dart';
import 'promo/admin_promo_screen.dart';
import 'reviews/admin_reviews_screen.dart';
import 'settings/admin_settings_screen.dart';

/// The AdminShell's currently selected tab (index into _AdminShellState.
/// _tabs). Exposed so screens nested inside a tab — e.g. the dashboard's
/// stat cards — can jump to another tab without the shell needing to pass
/// callbacks down through every nested widget.
final adminTabIndexProvider = StateProvider<int>((ref) => 0);

class _MoreItem {
  final IconData icon;
  final String label;
  final int index;
  const _MoreItem({required this.icon, required this.label, required this.index});
}

/// Bottom-nav shell for staff/owner.
///
/// Primary: Home / Products / Orders. Delivery + Payments live under Orders
/// tabs. More sheet: Knowledge, Promo, Reviews, Analytics, Settings.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key});

  static const _tabs = [
    AdminDashboardScreen(),
    AdminProductsScreen(),
    AdminOrdersScreen(),
    AdminKnowledgeScreen(),
    AdminPromoScreen(),
    AdminReviewsScreen(),
    AdminSettingsScreen(),
    AdminAnalyticsScreen(),
  ];

  static const _primaryDestinations = [
    NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Home'),
    NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Products'),
    NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
  ];

  // Settings kept last — it's the least-used item, so the more frequently
  // reached-for ones (Knowledge/Promo/Reviews/Analytics) sit above it.
  static const _moreItems = [
    _MoreItem(icon: Icons.menu_book_outlined, label: 'Knowledge', index: 3),
    _MoreItem(icon: Icons.local_offer_outlined, label: 'Promo Codes', index: 4),
    _MoreItem(icon: Icons.rate_review_outlined, label: 'Reviews', index: 5),
    _MoreItem(icon: Icons.query_stats_outlined, label: 'Analytics', index: 7),
    _MoreItem(icon: Icons.settings_outlined, label: 'Settings', index: 6),
  ];

  bool _isMoreSelected(int index) => index >= 3;

  IconData _moreTabIcon(int index) {
    if (!_isMoreSelected(index)) return Icons.more_horiz;
    return _moreItems.firstWhere((m) => m.index == index).icon;
  }

  String _moreTabLabel(int index) {
    if (!_isMoreSelected(index)) return 'More';
    return _moreItems.firstWhere((m) => m.index == index).label;
  }

  Future<void> _openMoreSheet(BuildContext context, WidgetRef ref, int index) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('More',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.grey)),
              ),
            ),
            for (final item in _moreItems)
              ListTile(
                leading: Icon(item.icon,
                    color: index == item.index ? AppColors.red : AppColors.black),
                title: Text(
                  item.label,
                  style: TextStyle(
                    fontWeight:
                        index == item.index ? FontWeight.w700 : FontWeight.w500,
                    color: index == item.index ? AppColors.red : AppColors.black,
                  ),
                ),
                trailing: index == item.index
                    ? const Icon(Icons.check, color: AppColors.red)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(item.index),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (selected != null) ref.read(adminTabIndexProvider.notifier).state = selected;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(adminTabIndexProvider);
    return Scaffold(
      body: IndexedStack(index: index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _isMoreSelected(index) ? 3 : index,
        onDestinationSelected: (i) {
          if (i == 3) {
            _openMoreSheet(context, ref, index);
          } else {
            ref.read(adminTabIndexProvider.notifier).state = i;
          }
        },
        destinations: [
          ..._primaryDestinations,
          NavigationDestination(
            icon: Icon(_moreTabIcon(index)),
            label: _moreTabLabel(index),
          ),
        ],
      ),
    );
  }
}
