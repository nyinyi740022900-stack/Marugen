import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shown instead of the real app when `.env` hasn't been created yet, so
/// `flutter run` doesn't just crash on a fresh checkout.
class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: AppPalette.of(context).background,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.settings_suggest_outlined,
                    color: AppPalette.of(context).accent,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Setup Required',
                    style: TextStyle(
                      color: AppPalette.of(context).text,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Copy .env.example to .env and fill in your Supabase URL, '
                    'anon key, and Stripe publishable key, then restart the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppPalette.of(context).textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
