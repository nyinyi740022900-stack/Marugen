import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/login_screen.dart';
import 'package:marugen_app/shared/widgets/brand_logo.dart';

void main() {
  testWidgets('large iPhone uses the available space for login', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: 62, bottom: 34),
              viewPadding: const EdgeInsets.only(top: 62, bottom: 34),
            ),
            child: child!,
          ),
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<BrandLogo>(find.byType(BrandLogo)).size, 88);
    expect(
      tester.getSize(find.byType(ElevatedButton)).height,
      greaterThanOrEqualTo(56),
    );
    expect(
      tester.getBottomRight(find.text('Privacy Policy')).dy,
      greaterThan(780),
    );
    expect(find.text('Privacy Policy').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    for (final scale in [1.3, 2.0]) {
      testWidgets('roomy iPhone large text $scale keyboard in dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(440, 956);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
                platform: TargetPlatform.iOS,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 62),
                  viewPadding: const EdgeInsets.only(top: 62, bottom: 34),
                  viewInsets: const EdgeInsets.only(bottom: 320),
                  textScaler: TextScaler.linear(scale),
                ),
                child: child!,
              ),
              home: const LoginScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Privacy Policy'));
        await tester.pumpAndSettle();
        expect(find.text('Privacy Policy').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final size in [const Size(360, 740), const Size(390, 844)]) {
      testWidgets('$platform login shows every action at $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light.copyWith(platform: platform),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 24, bottom: 24),
                  viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
                ),
                child: child!,
              ),
              home: const LoginScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final label in [
          'Log In',
          'Continue with Google',
          if (platform != TargetPlatform.android) 'Continue with Apple',
          'Sign up',
          'Privacy Policy',
        ]) {
          expect(
            find.text(label).hitTestable(),
            findsOneWidget,
            reason: '$label must be visible before scrolling',
          );
          expect(
            tester.getBottomRight(find.text(label)).dy,
            lessThanOrEqualTo(size.height - 24),
          );
        }
        for (final button in [
          find.byType(ElevatedButton),
          find.widgetWithText(OutlinedButton, 'Continue with Google'),
          if (platform != TargetPlatform.android)
            find.byType(SignInWithAppleButton),
        ]) {
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        }
      });
    }
  }
}
