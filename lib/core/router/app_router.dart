import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/admin_shell.dart';
import '../../features/admin/products/admin_product_edit_screen.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/cart/presentation/cart_screen.dart';
import '../../features/legal/privacy_screen.dart';
import '../../features/legal/terms_screen.dart';
import '../../features/orders/presentation/checkout_screen.dart';
import '../../features/orders/presentation/order_detail_screen.dart';
import '../../features/shop/presentation/customer_shell.dart';
import '../../features/shop/presentation/product_detail_screen.dart';
import '../../features/support/faq_screen.dart';
import '../../shared/models/app_user.dart';
import '../../shared/models/order.dart';
import 'splash_screen.dart';

/// Routes that require the user to be logged in — everyone else can
/// browse the shop, product pages and cart as a guest. Login is only
/// enforced here (plus everything under `/admin`).
const _authRequiredRoutes = ['/checkout'];

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final appUserAsync = ref.watch(currentAppUserProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _GoRouterRefreshStream(ref),
    redirect: (context, state) {
      final loggingIn = state.matchedLocation == '/login' || state.matchedLocation == '/signup';
      final isLoggedIn = authState.valueOrNull?.session != null;
      final onAdminRoute = state.matchedLocation.startsWith('/admin');

      // Still resolving auth/session on first load.
      if (authState.isLoading) {
        return state.matchedLocation == '/splash' ? null : '/splash';
      }

      if (!isLoggedIn) {
        if (loggingIn) return null;
        // Guests can browse freely; only checkout and admin require login.
        final needsAuth = _authRequiredRoutes.contains(state.matchedLocation) || onAdminRoute;
        if (needsAuth) {
          return '/login?redirect=${Uri.encodeComponent(state.uri.toString())}';
        }
        return state.matchedLocation == '/splash' ? '/' : null;
      }

      // Route to the right shell once we know the user's role.
      final appUser = appUserAsync.valueOrNull;
      if (appUserAsync.isLoading) {
        return state.matchedLocation == '/splash' ? null : '/splash';
      }
      final isAdmin = appUser?.role.isAdmin ?? false;

      if (loggingIn || state.matchedLocation == '/splash') {
        final redirect = state.uri.queryParameters['redirect'];
        if (redirect != null && redirect.isNotEmpty) return redirect;
        return isAdmin ? '/admin' : '/';
      }
      if (isAdmin && state.matchedLocation == '/') return '/admin';
      if (!isAdmin && onAdminRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
      GoRoute(path: '/forgot-password', builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: '/', builder: (_, _) => const CustomerShell()),
      GoRoute(
        path: '/product/:id',
        builder: (_, state) => ProductDetailScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
      GoRoute(path: '/checkout', builder: (_, _) => const CheckoutScreen()),
      GoRoute(path: '/terms', builder: (_, _) => const TermsScreen()),
      GoRoute(path: '/privacy', builder: (_, _) => const PrivacyScreen()),
      GoRoute(path: '/faq', builder: (_, _) => const FaqScreen()),
      GoRoute(
        path: '/orders/:id',
        builder: (_, state) => OrderDetailScreen(
          orderId: state.pathParameters['id']!,
          order: state.extra as Order?,
        ),
      ),
      GoRoute(path: '/admin', builder: (_, _) => const AdminShell()),
      GoRoute(
        path: '/admin/products/new',
        builder: (_, _) => const AdminProductEditScreen(),
      ),
      GoRoute(
        path: '/admin/products/:id',
        builder: (_, state) => AdminProductEditScreen(productId: state.pathParameters['id']),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(body: Center(child: Text('Route not found: ${state.uri}'))),
  );
});

/// Bridges Riverpod's async auth/role state into a [Listenable] so GoRouter
/// re-evaluates `redirect` whenever either changes.
class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
    ref.listen(currentAppUserProvider, (_, _) => notifyListeners());
  }
}
