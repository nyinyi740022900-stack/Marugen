import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marugen_app/core/theme/theme_preference.dart';
import 'package:marugen_app/core/theme/appearance_tile.dart';
import 'package:marugen_app/core/theme/app_theme.dart';

void main() {
  test('late preference loading never replaces a new user choice', () async {
    SharedPreferences.setMockInitialValues({'appearance_mode': 'light'});
    final pending = Completer<SharedPreferences>();
    final container = ProviderContainer(
      overrides: [themePreferencesProvider.overrideWithValue(pending.future)],
    );
    addTearDown(container.dispose);
    container.read(themeModeProvider);
    final save = container
        .read(themeModeProvider.notifier)
        .setMode(ThemeMode.dark);
    pending.complete(await SharedPreferences.getInstance());
    await save;
    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(
      (await SharedPreferences.getInstance()).getString('appearance_mode'),
      'dark',
    );
  });
  testWidgets(
    'system appearance follows device changes while explicit light stays light',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: ref.watch(themeModeProvider),
              home: const Scaffold(body: AppearanceTile()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(AppearanceTile))).brightness,
        Brightness.dark,
      );
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(AppearanceTile))).brightness,
        Brightness.light,
      );
    },
  );
  test('restores saved dark mode and persists a later system choice', () async {
    SharedPreferences.setMockInitialValues({'appearance_mode': 'dark'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(themeModeProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(themeModeProvider), ThemeMode.dark);
    await container.read(themeModeProvider.notifier).setMode(ThemeMode.system);
    expect(
      (await SharedPreferences.getInstance()).getString('appearance_mode'),
      'system',
    );
  });
  testWidgets('appearance picker switches real app theme and saves choice', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ref.watch(themeModeProvider),
            home: const Scaffold(body: AppearanceTile()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(AppearanceTile))).brightness,
      Brightness.dark,
    );
    expect(
      (await SharedPreferences.getInstance()).getString('appearance_mode'),
      'dark',
    );
    expect(tester.takeException(), isNull);
  });
  test('dark semantic text and status colors remain readable on surfaces', () {
    final palette = AppPalette.dark;
    for (final surface in [
      palette.background,
      palette.surface,
      palette.surfaceMuted,
    ]) {
      for (final foreground in [
        palette.text,
        palette.textMuted,
        palette.accent,
        palette.error,
        palette.success,
        palette.warning,
      ]) {
        final a = foreground.computeLuminance();
        final b = surface.computeLuminance();
        expect((a + .05) / (b + .05), greaterThanOrEqualTo(4.5));
      }
    }
  });
}
