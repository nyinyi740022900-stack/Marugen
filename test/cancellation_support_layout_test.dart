import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/orders/presentation/orders_providers.dart';
import 'package:marugen_app/features/orders/presentation/order_cancellation_panel.dart';
import 'package:marugen_app/shared/models/app_user.dart';
import 'package:marugen_app/shared/models/order.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:marugen_app/shared/widgets/support_contact_picker.dart';

import 'order_cancellation_test.dart' show orderMap;
import 'cancellation_panel_test.dart' show CancellationRepository;

void main() {
  final capture = Platform.environment['CANCELLATION_UI_CAPTURE'] == '1';
  if (capture) {
    setUpAll(() async {
      for (final family in ['.SF Pro Text', 'Roboto']) {
        await (FontLoader(family)..addFont(
              File('/System/Library/Fonts/SFNS.ttf')
                  .readAsBytes()
                  .then(ByteData.sublistView),
            ))
            .load();
      }
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    });
  }
  for (final brightness in Brightness.values) {
    for (final surface in ['customer', 'owner', 'support']) {
      testWidgets('$surface at 320px large text $brightness', (tester) async {
        tester.view.physicalSize = const Size(320, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final order = Order.fromMap(
          orderMap({
            'order_cancellation_requests': {
              'status': 'requested',
              'reason':
                  'Ordered the wrong size. Please cancel before dispatch.',
            },
          }),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUserIdProvider.overrideWithValue('customer'),
              currentAppUserProvider.overrideWith(
                (ref) async => AppUser(
                  id: 'customer',
                  role: surface == 'owner' ? UserRole.owner : UserRole.customer,
                ),
              ),
              orderByIdProvider(order.id).overrideWith((ref) async => order),
              orderRepositoryProvider.overrideWithValue(
                CancellationRepository(),
              ),
              shopSettingsProvider.overrideWith(
                (ref) async => {
                  'support_contacts': [
                    {
                      'id': 'support-fixture',
                      'name': 'Alex Tan',
                      'category': 'Orders, delivery and cancellation support',
                      'whatsapp': '+6588889999',
                      'phone': '+6588889999',
                      'email': 'support@example.com',
                    },
                  ],
                },
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: brightness == Brightness.light
                  ? AppTheme.light
                  : AppTheme.dark,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: const ValueKey('capture'),
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(
                      surface == 'support'
                          ? 'Contact Support'
                          : 'Order details',
                    ),
                  ),
                  body: surface == 'support'
                      ? const SupportContactPicker()
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: OrderCancellationPanel(order: order),
                        ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (capture) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          await tester.runAsync(() async {
            final img = await boundary.toImage();
            final bytes = await img.toByteData(format: ImageByteFormat.png);
            await Directory('output/cancellation-support-qa')
                .create(recursive: true);
            await File(
              'output/cancellation-support-qa/$surface-${brightness.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            img.dispose();
          });
        }
      });
    }
  }
}
