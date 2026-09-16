import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../../shared/widgets/brand_logo.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandLogo(size: 120),
            SizedBox(height: 20),
            Text(
              'MARUGEN KOI FARM',
              style: TextStyle(
                color: AppColors.black,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 28),
            CircularProgressIndicator(color: AppColors.red),
          ],
        ),
      ),
    );
  }
}
