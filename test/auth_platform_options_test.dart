import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/login_screen.dart';
import 'package:marugen_app/features/auth/presentation/signup_screen.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final screen in [const LoginScreen(), const SignupScreen()]) {
      testWidgets(
        '$platform ${screen.runtimeType} exposes appropriate sign-in providers',
        (tester) async {
          tester.view.physicalSize = const Size(440, 956);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: AppTheme.light.copyWith(platform: platform),
                home: screen,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Continue with Google'), findsOneWidget);
          expect(
            find.text('Continue with Apple'),
            platform == TargetPlatform.android ? findsNothing : findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
