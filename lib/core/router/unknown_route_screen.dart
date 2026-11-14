import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';

/// Keeps invalid/deleted deep links recoverable without relying on history.
class UnknownRouteScreen extends StatelessWidget {
  const UnknownRouteScreen({super.key, required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "We couldn't find that page.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'The link may be old or mistyped.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppPalette.of(context).textMuted),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to Shop'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
