import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/view_tracker.dart';
import '../../../shared/widgets/promo_banner_dialog.dart';
import '../../auth/presentation/profile_screen.dart';
import '../../knowledge/presentation/knowledge_screen.dart';
import '../../orders/presentation/orders_screen.dart';
import 'shell_tab_provider.dart';
import 'shop_screen.dart';

/// Bottom-nav shell for the customer-facing side of the app.
class CustomerShell extends ConsumerStatefulWidget {
  const CustomerShell({super.key});

  @override
  ConsumerState<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends ConsumerState<CustomerShell> {
  final _contentKey = GlobalKey();
  static const _tabs = [
    ShopScreen(),
    KnowledgeScreen(),
    OrdersScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Once per app session — this shell is only built once (kept alive by
    // its IndexedStack tabs) after auth/role resolves to "customer".
    ViewTracker.logAppVisit();
    // Post-frame so the promo popup appears after this shell's first
    // paint, not mid-build; PromoBannerDialog itself enforces the
    // once-per-device-per-day gate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PromoBannerDialog.maybeShow(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(customerTabIndexProvider);
    return AdaptiveCustomerNavigation(
      index: index,
      onSelected: (i) => ref.read(customerTabIndexProvider.notifier).state = i,
      body: IndexedStack(key: _contentKey, index: index, children: _tabs),
    );
  }
}

/// Keep phone navigation familiar, and use the space available on tablets.
class AdaptiveCustomerNavigation extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelected;
  final Widget body;
  const AdaptiveCustomerNavigation({
    super.key,
    required this.index,
    required this.onSelected,
    required this.body,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 700) {
        return Scaffold(
          // Match the brand AppBar behind the tablet status-bar safe area.
          backgroundColor: AppColors.black,
          body: Row(
            children: [
              SafeArea(
                bottom: false,
                right: false,
                child: SizedBox(
                  width: 104,
                  child: Column(
                    children: [
                      // Navigation stays fixed across all customer modules.
                      const SizedBox(height: kToolbarHeight),
                      Expanded(
                        child: NavigationRail(
                          minWidth: 104,
                          leading: const SizedBox(height: 12),
                          selectedIndex: index,
                          onDestinationSelected: onSelected,
                          scrollable: true,
                          labelType: NavigationRailLabelType.all,
                          backgroundColor: AppPalette.of(context).surface,
                          indicatorColor: AppColors.red,
                          selectedIconTheme: const IconThemeData(
                            color: AppColors.white,
                          ),
                          selectedLabelTextStyle: TextStyle(
                            color: AppPalette.of(context).accent,
                            fontWeight: FontWeight.w600,
                          ),
                          unselectedLabelTextStyle: TextStyle(
                            color: AppPalette.of(context).textMuted,
                          ),
                          destinations: const [
                            NavigationRailDestination(
                              icon: Icon(Icons.storefront_outlined),
                              label: Text('Shop'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.menu_book_outlined),
                              label: Text('Guide'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.receipt_long_outlined),
                              label: Text('Orders'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.person_outline),
                              label: Text('Profile'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: body),
            ],
          ),
        );
      }
      return Scaffold(
        body: body,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: index,
          onTap: onSelected,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.storefront_outlined),
              label: 'Shop',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_outlined),
              label: 'Guide',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              label: 'Orders',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              label: 'Profile',
            ),
          ],
          selectedItemColor: AppPalette.of(context).accent,
        ),
      );
    },
  );
}
