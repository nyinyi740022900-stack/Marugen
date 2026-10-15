import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/admin/knowledge/admin_knowledge_screen.dart';
import 'package:marugen_app/features/knowledge/presentation/knowledge_providers.dart';
import 'package:marugen_app/features/services/presentation/service_providers.dart';
import 'package:marugen_app/shared/models/knowledge.dart';

void main() {
  testWidgets('admin variety remains usable when its remote image fails', (
    tester,
  ) async {
    // Widget tests return HTTP 400 for real network images, exercising the
    // same fallback as unavailable/rate-limited remote guide thumbnails.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          varietiesProvider(null).overrideWith(
            (_) async => [
              Variety(
                id: 'fixture',
                name: 'Kohaku',
                category: 'koi',
                imageUrl: 'https://example.invalid/unavailable.jpg',
              ),
            ],
          ),
          articlesProvider.overrideWith((_) async => []),
          servicesProvider.overrideWith((_) async => []),
        ],
        child: const MaterialApp(home: AdminKnowledgeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kohaku'), findsOneWidget);
    expect(find.byIcon(Icons.water), findsOneWidget);
    expect(find.byTooltip('Hide from customers').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
