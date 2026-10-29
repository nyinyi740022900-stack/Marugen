import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/support/support_directory_settings.dart';
import 'package:marugen_app/features/support/support_contact_form.dart';
import 'package:marugen_app/shared/models/app_user.dart';

void main() {
  for (final role in UserRole.values) {
    testWidgets('support directory management is owner-only for $role', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAppUserProvider.overrideWith(
              (ref) async => AppUser(id: 'user', role: role),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SupportDirectorySettingsTile()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Support contacts'),
        role == UserRole.owner ? findsOneWidget : findsNothing,
      );
    });
  }
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      'support contact editor scrolls at narrow large text ${theme.brightness}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 200),
              ),
              child: child!,
            ),
            home: SupportContactForm(onSaved: (_) {}),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Save contact'),
          180,
          maxScrolls: 40,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Save contact').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
