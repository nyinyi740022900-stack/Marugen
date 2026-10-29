import 'package:flutter/material.dart';
import 'package:marugen_app/shared/widgets/keyboard_dismiss_region.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/login_screen.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/auth/presentation/signup_screen.dart';
import 'package:marugen_app/features/auth/presentation/forgot_password_screen.dart';
import 'package:marugen_app/features/auth/presentation/reset_password_screen.dart';
import 'package:marugen_app/features/profile/presentation/address_book_screen.dart';
import 'package:marugen_app/features/notifications/presentation/notifications_screen.dart';
import 'package:marugen_app/features/notifications/presentation/notification_providers.dart';
import 'package:marugen_app/features/admin/products/admin_product_edit_screen.dart';
import 'package:marugen_app/shared/models/app_notification.dart';

Widget host(
  Widget screen,
  double keyboard,
  Brightness brightness, {
  double textScale = 2,
}) {
  return ProviderScope(
    overrides: [
      isLoggedInProvider.overrideWithValue(true),
      currentUserIdProvider.overrideWithValue('customer'),
      myNotificationsProvider.overrideWith(_Inbox.new),
    ],
    child: MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: KeyboardDismissRegion(child: child!),
      ),
      home: screen,
    ),
  );
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('product category supports reduced font size in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(const AdminProductEditScreen(), 0, brightness, textScale: .85),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    for (final keyboard in [0.0, 300.0]) {
      for (final screen in [
        const LoginScreen(),
        const SignupScreen(),
        const ForgotPasswordScreen(),
        const ResetPasswordScreen(),
      ]) {
        testWidgets(
          '${screen.runtimeType} fits large text with keyboard $keyboard in $brightness',
          (tester) async {
            tester.view.physicalSize = const Size(320, 600);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(host(screen, keyboard, brightness));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (screen is LoginScreen) {
              await tester.scrollUntilVisible(
                find.text('Log In'),
                160,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expect(find.text('Log In').hitTestable(), findsOneWidget);
              expect(
                tester.getBottomRight(find.text('Log In')).dy,
                lessThanOrEqualTo(600 - keyboard),
              );
            }
          },
        );
      }
    }
    testWidgets('address form allows save above keyboard in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(const Scaffold(body: AddressForm()), 300, brightness),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Save Address'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Save Address').hitTestable(), findsOneWidget);
    });
    testWidgets('notification inbox fits large text in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(host(const NotificationsScreen(), 0, brightness));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Mark all read'), findsOneWidget);
    });
    testWidgets('new product variant fields fit compact phone in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(const AdminProductEditScreen(), 0, brightness),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Add Fish Option'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Add Fish Option'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Price'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final priceField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Price',
      );
      expect(tester.getSize(priceField).width, greaterThanOrEqualTo(120));
    });
  }
}

class _Inbox extends NotificationsNotifier {
  @override
  AsyncValue<List<AppNotification>> build() => AsyncData([
    AppNotification(
      id: 'n',
      title: 'Order shipped',
      body: 'Your order is on its way. You can view tracking information in your order details.',
      type: 'order_status',
      read: false,
      createdAt: DateTime(2026, 10, 11),
    ),
  ]);
}
