import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';

void main() {
  testWidgets('outlined button survives both animated theme transitions', (
    tester,
  ) async {
    Widget host(ThemeMode mode) => MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      home: Scaffold(
        body: OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.open_in_new),
          label: const Text('Connect EasyParcel'),
        ),
      ),
    );
    await tester.pumpWidget(host(ThemeMode.light));
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      await tester.pumpWidget(host(mode));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
