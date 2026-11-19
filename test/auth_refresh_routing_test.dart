import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marugen_app/core/router/app_router.dart';
import 'package:marugen_app/core/router/splash_screen.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/dashboard/admin_top_products_screen.dart';
import 'package:marugen_app/features/auth/data/auth_repository.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/auth/presentation/login_screen.dart';
import 'package:marugen_app/features/cart/domain/cart_item.dart';
import 'package:marugen_app/features/legal/terms_screen.dart';
import 'package:marugen_app/features/orders/presentation/checkout_screen.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/orders/presentation/shipping_quote_providers.dart';
import 'package:marugen_app/features/profile/presentation/address_providers.dart';
import 'package:marugen_app/shared/models/address.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'shipping_test_fixtures.dart';

Session sessionFor(String userId) => Session(
  accessToken: 'token-$userId',
  tokenType: 'bearer',
  user: User(
    id: userId,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
);

/// Stands in for Supabase auth: the test decides which events fire and how
/// each profile fetch resolves, while the real [currentAppUserProvider] and
/// [routerProvider] run on top of it.
class FakeAuth implements AuthRepository {
  final events = StreamController<AuthState>.broadcast();
  Session? session;
  Future<AppUser?> Function(String userId) profile =
      (id) async => AppUser(id: id);
  int profileFetches = 0;

  void emit(AuthChangeEvent event, Session? next) {
    session = next;
    events.add(AuthState(event, next));
  }

  @override
  Stream<AuthState> get authStateChanges => events.stream;
  @override
  User? get currentUser => session?.user;
  @override
  bool get isEmailVerified => true;
  @override
  Future<AppUser?> fetchCurrentAppUser() {
    profileFetches++;
    return profile(session!.user.id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const item = CartItem(
  product: Product(
    id: 'food',
    name: 'Fish food',
    category: ProductCategory.accessories,
    price: 10,
  ),
  quantity: 1,
);

const address = Address(
  id: 'address',
  userId: 'a',
  recipientName: 'Customer',
  phone: '81234567',
  line1: '1 Street',
  postalCode: '123456',
);

Future<GoRouter> startApp(
  WidgetTester tester,
  FakeAuth auth, {
  required String at,
  String? signedInAs,
}) async {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      shopSettingsProvider.overrideWith(
        (ref) async => <String, dynamic>{'gst_percent': 9},
      ),
      myAddressesProvider.overrideWith((ref) async => [address]),
      checkoutShippingQuoteProvider.overrideWith(
        (ref, key) async => fixtureShippingQuote(key),
      ),
      adminAllOrdersProvider.overrideWith((ref) async => []),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(auth.events.close);
  if (signedInAs != null) {
    // A restored session whose profile is already known: the app opens
    // straight on [at], the way a returning customer's does.
    final sub = container.listen(authStateProvider, (_, _) {});
    addTearDown(sub.close);
    auth.emit(AuthChangeEvent.initialSession, sessionFor(signedInAs));
    await container.read(authStateProvider.future);
    await container.read(currentAppUserProvider.future);
  }
  final router = container.read(routerProvider);
  router.go(at);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  return router;
}

void main() {
  testWidgets('a token refresh leaves checkout on the stack with its state', (
    tester,
  ) async {
    final auth = FakeAuth();
    final router = await startApp(
      tester,
      auth,
      at: '/terms',
      signedInAs: 'a',
    );
    await tester.pumpAndSettle();
    expect(find.byType(TermsScreen), findsOneWidget);

    router.push('/checkout', extra: const [item]);
    await tester.pumpAndSettle();
    final checkout = tester.state(find.byType(CheckoutScreen));
    final remarks = find.byType(TextField).last;
    await tester.ensureVisible(remarks);
    await tester.enterText(remarks, 'Leave at the door');
    await tester.pump();

    final fetchesBefore = auth.profileFetches;
    for (final event in [
      AuthChangeEvent.tokenRefreshed,
      AuthChangeEvent.userUpdated,
    ]) {
      auth.emit(event, sessionFor('a'));
      // The frame in which the profile is still re-loading is the one that
      // used to redirect to /splash.
      await tester.pump();
      expect(find.byType(SplashScreen), findsNothing, reason: event.name);
      await tester.pumpAndSettle();
      expect(find.byType(SplashScreen), findsNothing, reason: event.name);
    }
    expect(auth.profileFetches, greaterThan(fetchesBefore));

    expect(tester.state(find.byType(CheckoutScreen)), same(checkout));
    expect(find.text('Leave at the door'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(TermsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signing out of checkout goes to login, and the next account is '
      'never routed by a stale profile', (tester) async {
    final auth = FakeAuth();
    final router = await startApp(
      tester,
      auth,
      at: '/terms',
      signedInAs: 'a',
    );
    await tester.pumpAndSettle();
    // Checkout as the location itself (a deep link / post-login return), so
    // the router's own guard is what has to react to the sign-out.
    router.go('/checkout', extra: const [item]);
    await tester.pumpAndSettle();
    expect(find.byType(CheckoutScreen), findsOneWidget);

    auth.emit(AuthChangeEvent.signedOut, null);
    await tester.pumpAndSettle();
    expect(find.byType(CheckoutScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);

    // An owner signs in on the same device, heading for an admin screen.
    // Until *their* profile has loaded nothing may be decided from the
    // previous (customer / signed-out) value.
    router.go('/login?redirect=%2Fadmin%2Ftop-products');
    await tester.pumpAndSettle();
    final owner = Completer<AppUser?>();
    auth.profile = (id) => owner.future;
    auth.emit(AuthChangeEvent.signedIn, sessionFor('b'));
    // Bounded pumps, not pumpAndSettle: the splash spinner never settles.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(AdminTopProductsScreen), findsNothing);

    owner.complete(const AppUser(id: 'b', role: UserRole.owner));
    await tester.pumpAndSettle();
    expect(find.byType(AdminTopProductsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed profile load stays on splash and offers Retry', (
    tester,
  ) async {
    final auth = FakeAuth();
    var online = false;
    auth.profile = (id) async {
      if (!online) throw Exception('SocketException: secret-host');
      return AppUser(id: id, role: UserRole.owner);
    };
    await startApp(tester, auth, at: '/admin/top-products');
    auth.emit(AuthChangeEvent.initialSession, sessionFor('a'));
    await tester.pumpAndSettle();

    // Not the customer shop, not the admin screen: the role is unknown.
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(AdminTopProductsScreen), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.textContaining('secret-host'), findsNothing);

    online = true;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(AdminTopProductsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
