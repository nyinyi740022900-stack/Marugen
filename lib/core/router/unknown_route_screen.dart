import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
              Text('Route not found: $uri', textAlign: TextAlign.center),
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
