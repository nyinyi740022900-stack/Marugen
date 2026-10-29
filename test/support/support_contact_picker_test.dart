import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:marugen_app/shared/widgets/support_contact_picker.dart';

void main() {
  testWidgets('private order context is hidden after switching accounts', (
    tester,
  ) async {
    final actor = StateProvider<String?>((ref) => 'owner-a');
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith((ref) => ref.watch(actor)),
        shopSettingsProvider.overrideWith(
          (ref) async => {'shop_phone': '+6588889999'},
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SupportContactPicker(message: 'Order #123')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('WhatsApp'), findsOneWidget);
    container.read(actor.notifier).state = 'owner-b';
    await tester.pumpAndSettle();
    expect(find.text('WhatsApp'), findsNothing);
    expect(find.textContaining('Account changed'), findsOneWidget);
  });
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets('support choices fit narrow large text ${theme.brightness}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shopSettingsProvider.overrideWith(
              (ref) async => {
                'support_contacts': [
                  {
                    'id': 'orders',
                    'name': 'Order support colleague',
                    'category': 'Orders, cancellations and delivery enquiries',
                    'whatsapp': '+6588889999',
                    'phone': '+6562223333',
                    'email': 'help@example.com',
                  },
                ],
              },
            ),
          ],
          child: MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const Scaffold(body: SupportContactPicker()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Order support colleague'), findsOneWidget);
      for (final text in ['WhatsApp', 'Phone', 'Email']) {
        await tester.scrollUntilVisible(find.text(text), 150);
        expect(find.text(text), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('failed directory load retries and empty state has recovery', (
    tester,
  ) async {
    var fail = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shopSettingsProvider.overrideWith((ref) async {
            if (fail) throw Exception('offline');
            return {'support_contacts': []};
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: SupportContactPicker())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No support contacts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
