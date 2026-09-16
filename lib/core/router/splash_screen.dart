import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.water, color: AppColors.red, size: 56),
            SizedBox(height: 16),
            Text(
              'MARUGEN KOI FARM',
              style: TextStyle(color: AppColors.white, letterSpacing: 1.5, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(color: AppColors.red),
          ],
        ),
      ),
    );
  }
}
