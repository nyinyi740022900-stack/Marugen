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
      home: Scaffold(
        backgroundColor: AppColors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_suggest_outlined, color: AppColors.red, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Setup Required',
                  style: TextStyle(color: AppColors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Copy .env.example to .env and fill in your Supabase URL, '
                  'anon key, and Stripe publishable key, then restart the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.lightGrey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
