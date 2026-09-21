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
    return Scaffold(
      body: IndexedStack(index: index, children: _tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => ref.read(customerTabIndexProvider.notifier).state = i,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.storefront_outlined), label: 'Shop'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book_outlined), label: 'Guide'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
        selectedItemColor: AppColors.red,
      ),
    );
  }
}
