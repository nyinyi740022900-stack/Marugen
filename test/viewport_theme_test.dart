import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';

void main() {
  test(
    'compact Android content uses denser roles without changing auth or iOS',
    () {
      for (final base in [AppTheme.light, AppTheme.dark]) {
        final android = base.copyWith(platform: TargetPlatform.android);
        final compact = AppTheme.forViewport(android, width: 360);
        expect(compact.textTheme.bodyMedium!.fontSize, 13);
        expect(
          AppTheme.forViewport(
            android,
            width: 411,
          ).textTheme.bodyMedium!.fontSize,
          13,
        );
        expect(compact.textTheme.titleMedium!.fontSize, 15);
        expect(
          compact.elevatedButtonTheme.style!.minimumSize!.resolve({})!.height,
          48,
        );
        expect(
          identical(
            AppTheme.forViewport(android, width: 360, authentication: true),
            android,
          ),
          isTrue,
        );
        expect(
          identical(AppTheme.forViewport(android, width: 600), android),
          isTrue,
        );
        final ios = base.copyWith(platform: TargetPlatform.iOS);
        expect(identical(AppTheme.forViewport(ios, width: 360), ios), isTrue);
      }
    },
  );
}
