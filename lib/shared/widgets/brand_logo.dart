import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Circular Marugen brand mark. Sits on a white backing so the black seal
/// reads clearly on light surfaces (login, splash, app bar).
class BrandLogo extends StatelessWidget {
  final double size;
  final bool showFallbackIcon;

  const BrandLogo({
    super.key,
    this.size = 88,
    this.showFallbackIcon = true,
  });

  static const assetPath = 'assets/images/logo.png';

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: ColoredBox(
        color: AppColors.white,
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, _, _) => showFallbackIcon
              ? SizedBox(
                  width: size,
                  height: size,
                  child: Icon(Icons.water, size: size * 0.55, color: AppColors.red),
                )
              : SizedBox(width: size, height: size),
        ),
      ),
    );
  }
}
