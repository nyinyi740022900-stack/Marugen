import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/knowledge/admin_article_form.dart';
import 'package:marugen_app/features/admin/knowledge/admin_variety_form.dart';
import 'package:marugen_app/features/admin/services/admin_services_screen.dart';
import 'package:marugen_app/features/admin/promo/admin_promo_screen.dart';
import 'package:marugen_app/features/services/presentation/service_providers.dart';
import 'package:marugen_app/features/knowledge/presentation/knowledge_providers.dart';
import 'package:marugen_app/features/promo/presentation/promo_providers.dart';
import 'package:marugen_app/shared/models/knowledge.dart';
import 'package:marugen_app/shared/models/service.dart';
import 'package:marugen_app/shared/models/promo_code.dart';

final _screenshots = Platform.environment['UI_OWNER_CAPTURE'] == '1';
var _writes = 0;
Future<http.Response> Function(http.Request)? _handler;
final _loads = <String, int>{};
void _loaded(String kind) => _loads[kind] = (_loads[kind] ?? 0) + 1;
void main() {
  setUp(() {
    _handler = null;
    _loads.clear();
  });
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://owner-fixtures.invalid',
      publishableKey: 'fixture',
      httpClient: MockClient((request) async {
        if (request.method != 'GET') _writes++;
        if (_handler != null) {
          final response = await _handler!(request);
          return http.Response.bytes(
            response.bodyBytes,
            response.statusCode,
            headers: response.headers,
            request: request,
          );
        }
        return http.Response(
          '{"message":"Fixture save unavailable"}',
          400,
          headers: {'content-type': 'application/json'},
        );
      }),
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
    if (_screenshots) {
      await (FontLoader('.SF Pro Text')..addFont(
            File('/System/Library/Fonts/SFNS.ttf')
                .readAsBytes()
                .then(ByteData.sublistView),
          ))
          .load();
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  tearDownAll(() => Supabase.instance.dispose());
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    for (final kind in ['variety', 'guide', 'service', 'promo']) {
      for (final edit in [false, true]) {
        testWidgets(
          '$kind ${edit ? 'edit' : 'create'} compact 2x ${theme.brightness}',
          (tester) async {
            await _open(tester, theme, kind, edit: edit, keyboard: true);
            expect(tester.takeException(), isNull);
            final action = find.widgetWithText(
              ElevatedButton,
              kind == 'guide' ? 'Publish' : 'Save',
            );
            await _reach(tester, action);
            expect(action.hitTestable(), findsOneWidget);
            if (!edit) {
              final writesBefore = _writes;
              await tester.tap(action);
              await tester.pumpAndSettle();
              expect(
                _writes,
                writesBefore,
                reason: 'Empty required fields must not send a save',
              );
              expect(
                find.textContaining(
                  kind == 'guide'
                      ? 'Enter a title'
                      : kind == 'variety'
                      ? 'Enter a name'
                      : kind == 'service'
                      ? 'Enter a service name'
                      : 'Enter a code',
                ),
                findsWidgets,
              );
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
          },
        );
      }
    }
    for (final kind in ['variety', 'guide', 'service', 'promo']) {
      testWidgets(
        '$kind failed save remains visible and retryable ${theme.brightness}',
        (tester) async {
          await _open(tester, theme, kind, edit: true, keyboard: true);
          final action = find.widgetWithText(
            ElevatedButton,
            kind == 'guide' ? 'Publish' : 'Save',
          );
          await _reach(tester, action);
          final before = _writes;
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(_writes, before + 1);
          expect(find.byType(BottomSheet), findsOneWidget);
          await _reach(tester, action);
          expect(
            find.textContaining('Could not save').hitTestable(),
            findsOneWidget,
          );
          expect(action.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'service rejects malformed optional price ${theme.brightness}',
      (tester) async {
        await _open(tester, theme, 'service', edit: true, keyboard: true);
        final fields = find.byType(TextField);
        await _reach(tester, fields.at(3));
        await tester.enterText(fields.at(3), 'not a price');
        final action = find.widgetWithText(ElevatedButton, 'Save');
        await _reach(tester, action);
        final before = _writes;
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(_writes, before);
        expect(find.text('Enter a valid price of 0 or more.'), findsOneWidget);
      },
    );
    testWidgets('promo rejects malformed usage limit ${theme.brightness}', (
      tester,
    ) async {
      await _open(tester, theme, 'promo', edit: true, keyboard: true);
      await _reach(tester, find.byType(TextField).at(2));
      await tester.enterText(find.byType(TextField).at(2), '-5');
      final action = find.widgetWithText(ElevatedButton, 'Save');
      await _reach(tester, action);
      final before = _writes;
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(_writes, before);
      expect(find.textContaining('whole-number usage limit'), findsOneWidget);
    });
    testWidgets(
      'enlarged variety stage fields retain usable width ${theme.brightness}',
      (tester) async {
        await _open(tester, theme, 'variety', edit: true);
        final stage = find.widgetWithText(TextField, 'Stage label');
        await _reach(tester, stage);
        expect(tester.getSize(stage).width, greaterThanOrEqualTo(220));
      },
    );
    testWidgets('variety stages can be added and removed ${theme.brightness}', (
      tester,
    ) async {
      await _open(tester, theme, 'variety');
      final add = find.text('Add stage');
      await _reach(tester, add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      final label = find.widgetWithText(TextField, 'Stage label');
      await _reach(tester, label);
      await tester.enterText(label, 'Nisai');
      final remove = find.byTooltip('Remove stage');
      await _reach(tester, remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(label, findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('promo expiry clears without saving ${theme.brightness}', (
      tester,
    ) async {
      await _open(tester, theme, 'promo', edit: true);
      final clear = find.byTooltip('Clear expiry date');
      await _reach(tester, clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(find.text('No expiry'), findsOneWidget);
      expect(find.byTooltip('Clear expiry date'), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'promo percentage over 100 is explained without saving ${theme.brightness}',
      (tester) async {
        await _open(tester, theme, 'promo');
        await tester.enterText(find.byType(TextField).at(0), 'CHECK101');
        await _reach(tester, find.byType(TextField).at(1));
        await tester.enterText(find.byType(TextField).at(1), '101');
        final action = find.widgetWithText(ElevatedButton, 'Save');
        await _reach(tester, action);
        final before = _writes;
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(_writes, before);
        await _reach(tester, action);
        expect(
          find.textContaining('more than 100%').hitTestable(),
          findsOneWidget,
        );
      },
    );
    testWidgets('promo old expiry date picker ${theme.brightness}', (
      tester,
    ) async {
      await _open(tester, theme, 'promo', edit: true);
      final calendar = find.byIcon(Icons.calendar_today_outlined);
      await _reach(tester, calendar);
      await tester.tap(calendar);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
    });
  }
  for (final kind in ['variety', 'guide', 'service', 'promo']) {
    testWidgets('$kind success after dismissal refreshes list', (tester) async {
      final pending = Completer<http.Response>();
      _handler = (_) => pending.future;
      await _open(tester, AppTheme.light, kind, edit: true);
      final action = find.widgetWithText(
        ElevatedButton,
        kind == 'guide' ? 'Publish' : 'Save',
      );
      await _reach(tester, action);
      final loadsBefore = _loads[kind]!;
      await tester.tap(action);
      await tester.pump();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      pending.complete(http.Response('', 204));
      await tester.pumpAndSettle();
      expect(
        _loads[kind],
        loadsBefore + 1,
        reason: 'A completed save must refresh the surviving list',
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('variety save snapshots stage drafts before awaiting', (
    tester,
  ) async {
    final firstWrite = Completer<http.Response>();
    var requests = 0;
    List<dynamic>? savedStages;
    _handler = (request) async {
      requests++;
      if (requests == 1) return firstWrite.future;
      savedStages =
          (jsonDecode(request.body) as Map<String, dynamic>)['stages']
              as List<dynamic>;
      return http.Response('', 204);
    };
    await _open(tester, AppTheme.light, 'variety', edit: true);
    final save = find.widgetWithText(ElevatedButton, 'Save');
    await _reach(tester, save);
    await tester.tap(save);
    await tester.pump();
    await tester.ensureVisible(find.byTooltip('Remove stage'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Remove stage'));
    await tester.pump();
    firstWrite.complete(http.Response('', 204));
    await tester.pumpAndSettle();
    expect(
      savedStages,
      hasLength(1),
      reason: 'Submitted stage data must not change during the request',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('variety partial create retry reuses inserted row', (
    tester,
  ) async {
    final secondWrite = Completer<http.Response>();
    var inserts = 0;
    var patches = 0;
    _handler = (request) async {
      if (request.method == 'POST') {
        inserts++;
        return http.Response(
          '{"id":"saved-variety"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      patches++;
      if (patches == 1) return secondWrite.future;
      return http.Response('', 204);
    };
    await _open(tester, AppTheme.light, 'variety');
    await tester.enterText(find.byType(TextField).first, 'Kohaku');
    final save = find.widgetWithText(ElevatedButton, 'Save');
    await _reach(tester, save);
    await tester.tap(save);
    await tester.pump();
    secondWrite.complete(
      http.Response(
        '{"message":"Fixture second-write failure"}',
        400,
        headers: {'content-type': 'application/json'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save'), findsOneWidget);
    await _reach(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(inserts, 1, reason: 'Retry must update the row already created');
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
  if (_screenshots) {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      for (final kind in ['variety', 'guide', 'service', 'promo']) {
        testWidgets('capture owner $kind ${theme.brightness}', (tester) async {
          await _open(tester, theme, kind, edit: true, visual: true);
          await _snap(tester, '$kind-${theme.brightness.name}');
          await _reach(
            tester,
            find.widgetWithText(
              ElevatedButton,
              kind == 'guide' ? 'Publish' : 'Save',
            ),
          );
          await _snap(tester, '$kind-bottom-${theme.brightness.name}');
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

Future<void> _reach(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    target,
    160,
    maxScrolls: 50,
    scrollable: find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _open(
  WidgetTester tester,
  ThemeData theme,
  String kind, {
  bool edit = false,
  bool keyboard = false,
  bool visual = false,
}) async {
  tester.view.physicalSize = Size(320, visual ? 900 : 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        servicesProvider.overrideWith((ref) async {
          _loaded('service');
          return edit
              ? const [
                  Service(
                    id: 's',
                    name: 'Fish recovery and quarantine',
                    description: 'A quiet recovery space for koi.',
                    price: 1234.56,
                    category: 'Health care',
                  ),
                ]
              : [];
        }),
        adminPromoCodesProvider.overrideWith((ref) async {
          _loaded('promo');
          return edit
              ? [
                  PromoCode(
                    id: 'p',
                    code: 'LOYAL2026',
                    discountType: DiscountType.fixed,
                    discountValue: 12,
                    active: true,
                    expiresAt: DateTime(2020),
                    maxRedemptions: 100,
                    timesRedeemed: 4,
                  ),
                ]
              : [];
        }),
        articlesProvider.overrideWith((ref) async {
          _loaded('guide');
          return [];
        }),
        varietiesProvider(null).overrideWith((ref) async {
          _loaded('variety');
          return [];
        }),
      ],
      child: RepaintBoundary(
        key: const ValueKey('capture-owner'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              viewInsets: EdgeInsets.only(bottom: keyboard ? 250 : 0),
            ),
            child: child!,
          ),
          home: kind == 'service'
              ? const AdminServicesTab()
              : kind == 'promo'
              ? const AdminPromoScreen()
              : Consumer(
                  builder: (context, ref, _) {
                    if (kind == 'guide') {
                      ref.watch(articlesProvider);
                    } else {
                      ref.watch(varietiesProvider(null));
                    }
                    return Scaffold(
                      body: Center(
                        child: TextButton(
                          onPressed: () {
                            if (kind == 'variety') {
                              showVarietyForm(
                                context,
                                ref,
                                existing: edit
                                    ? const Variety(
                                        id: 'v',
                                        name: 'Premium Kohaku',
                                        category: 'koi',
                                        description: 'Red and white koi',
                                        traits: ['Red', 'White'],
                                        stages: [
                                          VarietyStage(
                                            label: 'Tosai — under one year',
                                            description: 'Early growth stage',
                                          ),
                                        ],
                                      )
                                    : null,
                              );
                            } else {
                              showArticleForm(
                                context,
                                ref,
                                existing: edit
                                    ? const KnowledgeArticle(
                                        id: 'g',
                                        title: 'Keeping healthy koi',
                                        bodyMarkdown: 'Test ammonia and monitor water quality daily.',
                                      )
                                    : null,
                              );
                            }
                          },
                          child: const Text('Open'),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    kind == 'service' || kind == 'promo'
        ? edit
              ? find.byType(ListTile).first
              : find.byType(FloatingActionButton)
        : find.text('Open'),
  );
  await tester.pumpAndSettle();
}

Future<void> _snap(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('capture-owner')),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    await Directory('output/ui-final-owner').create(recursive: true);
    await File('output/ui-final-owner/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
