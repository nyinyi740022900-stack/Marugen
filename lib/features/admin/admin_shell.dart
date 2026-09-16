import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'dashboard/admin_dashboard_screen.dart';
import 'delivery/admin_delivery_screen.dart';
import 'knowledge/admin_knowledge_screen.dart';
import 'orders/admin_orders_screen.dart';
import 'payments/admin_payments_screen.dart';
import 'products/admin_products_screen.dart';
import 'promo/admin_promo_screen.dart';
import 'settings/admin_settings_screen.dart';

class _MoreItem {
  final IconData icon;
  final String label;
  final int index;
  const _MoreItem({required this.icon, required this.label, required this.index});
}

/// Bottom-nav shell for staff/owner. Reached automatically after login when
/// the signed-in user's `profiles.role` is `staff` or `owner` (see router).
///
/// Only the 4 most-used sections sit directly on the bar; the rest live
/// behind a "More" tab that opens a sheet. 7 flat destinations on a
/// phone-width bar forced labels like "Knowledge" onto two lines while
/// everything else stayed on one — this keeps every label single-line and
/// the row visually even, regardless of how many admin sections exist.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  static const _tabs = [
    AdminDashboardScreen(),
    AdminProductsScreen(),
    AdminOrdersScreen(),
    AdminDeliveryScreen(),
    AdminPaymentsScreen(),
    AdminKnowledgeScreen(),
    AdminPromoScreen(),
    AdminSettingsScreen(),
  ];

  static const _primaryDestinations = [
    NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Home'),
    NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Products'),
    NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
    NavigationDestination(icon: Icon(Icons.local_shipping_outlined), label: 'Delivery'),
  ];

  static const _moreItems = [
    _MoreItem(icon: Icons.payments_outlined, label: 'Payments', index: 4),
    _MoreItem(icon: Icons.menu_book_outlined, label: 'Knowledge', index: 5),
    _MoreItem(icon: Icons.local_offer_outlined, label: 'Promo Codes', index: 6),
    _MoreItem(icon: Icons.settings_outlined, label: 'Settings', index: 7),
  ];

  bool get _isMoreSelected => _index >= 4;

  IconData get _moreTabIcon {
    if (!_isMoreSelected) return Icons.more_horiz;
    return _moreItems.firstWhere((m) => m.index == _index).icon;
  }

  String get _moreTabLabel {
    if (!_isMoreSelected) return 'More';
    return _moreItems.firstWhere((m) => m.index == _index).label;
  }

  Future<void> _openMoreSheet() async {
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
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        letterSpacing: 0.8, color: AppColors.grey)),
              ),
            ),
            for (final item in _moreItems)
              ListTile(
                leading: Icon(item.icon,
                    color: _index == item.index ? AppColors.red : AppColors.black),
                title: Text(
                  item.label,
                  style: TextStyle(
                    fontWeight: _index == item.index ? FontWeight.w700 : FontWeight.w500,
                    color: _index == item.index ? AppColors.red : AppColors.black,
                  ),
                ),
                trailing:
                    _index == item.index ? const Icon(Icons.check, color: AppColors.red) : null,
                onTap: () => Navigator.of(sheetContext).pop(item.index),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _index = selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _isMoreSelected ? 4 : _index,
        onDestinationSelected: (i) {
          if (i == 4) {
            _openMoreSheet();
          } else {
            setState(() => _index = i);
          }
        },
        destinations: [
          ..._primaryDestinations,
          NavigationDestination(icon: Icon(_moreTabIcon), label: _moreTabLabel),
        ],
      ),
    );
  }
}
