import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/push_notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../orders/presentation/orders_providers.dart';
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
  const _MoreItem({
    required this.icon,
    required this.label,
    required this.index,
  });
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
    NavigationDestination(
      icon: Icon(Icons.inventory_2_outlined),
      label: 'Products',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      label: 'Orders',
    ),
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

  Future<void> _openMoreSheet(
    BuildContext context,
    WidgetRef ref,
    int index,
  ) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => AdminMoreMenu(
        selectedIndex: index,
        onSelected: (value) => Navigator.of(sheetContext).pop(value),
      ),
    );
    if (selected != null) {
      ref.read(adminTabIndexProvider.notifier).state = selected;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(adminTabIndexProvider);
    // Staff get new-order pushes; the admin shell has no launch popup, so
    // ask after first paint. requestPermission() only prompts once.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PushNotificationService.requestPermission(),
    );
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            TickerMode(
              enabled: i == index,
              child: HeroMode(enabled: i == index, child: _tabs[i]),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _isMoreSelected(index) ? 3 : index,
        onDestinationSelected: (i) {
          if (i == 3) {
            _openMoreSheet(context, ref, index);
          } else {
            if (i == 2) refreshAdminOrders(ref);
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

/// Scrollable owner destinations stay reachable in landscape and large text.
class AdminMoreMenu extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  const AdminMoreMenu({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'More',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppPalette.of(context).textMuted,
                ),
              ),
            ),
          ),
          for (final item in AdminShell._moreItems)
            ListTile(
              leading: Icon(
                item.icon,
                color: selectedIndex == item.index
                    ? AppPalette.of(context).accent
                    : AppPalette.of(context).text,
              ),
              title: Text(
                item.label,
                style: TextStyle(
                  fontWeight: selectedIndex == item.index
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: selectedIndex == item.index
                      ? AppPalette.of(context).accent
                      : AppPalette.of(context).text,
                ),
              ),
              trailing: selectedIndex == item.index
                  ? Icon(Icons.check, color: AppPalette.of(context).accent)
                  : null,
              onTap: () => onSelected(item.index),
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
}
