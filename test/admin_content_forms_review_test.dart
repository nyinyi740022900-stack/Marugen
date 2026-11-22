// Page review 22 Nov 2026, admin content: typed text is guarded on every
// form, guide and promo list actions cannot double-fire or fail silently,
// a used promo code is turned off instead of deleted, and the guide form
// says Save / Publish for what it does.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/knowledge/admin_knowledge_screen.dart';
import 'package:marugen_app/features/admin/promo/admin_promo_screen.dart';
import 'package:marugen_app/features/knowledge/data/knowledge_repository.dart';
import 'package:marugen_app/features/knowledge/presentation/knowledge_providers.dart';
import 'package:marugen_app/features/promo/data/promo_repository.dart';
import 'package:marugen_app/features/promo/presentation/promo_providers.dart';
import 'package:marugen_app/features/services/data/service_repository.dart';
import 'package:marugen_app/features/services/presentation/service_providers.dart';
import 'package:marugen_app/shared/models/knowledge.dart';
import 'package:marugen_app/shared/models/promo_code.dart';
import 'package:marugen_app/shared/models/service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

class _Knowledge implements KnowledgeRepository {
  List<Variety> varieties = [];
  List<KnowledgeArticle> articles = [];
  final articleWrites = <(String?, Map<String, dynamic>)>[];
  final deletes = <String>[];
  Completer<void>? hold;
  Object? failure;

  @override
  Future<List<Variety>> fetchVarieties({String? category}) async => varieties;
  @override
  Future<List<KnowledgeArticle>> fetchArticles() async => articles;

  @override
  Future<String> upsertArticle(
    Map<String, dynamic> payload, {
    String? id,
  }) async {
    articleWrites.add((id, payload));
    await hold?.future;
    if (failure != null) throw failure!;
    return id ?? 'new-guide';
  }

  @override
  Future<void> deleteArticle(String id) async {
    deletes.add(id);
    if (failure != null) throw failure!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Services implements ServiceRepository {
  @override
  Future<List<Service>> fetchServices() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Promos implements PromoRepository {
  _Promos(this.codes);
  List<PromoCode> codes;
  final writes = <(String?, Map<String, dynamic>)>[];
  final deletes = <String>[];
  Object? deleteFailure;

  @override
  Future<List<PromoCode>> fetchAll() async => codes;

  @override
  Future<void> upsert(Map<String, dynamic> payload, {String? id}) async {
    writes.add((id, payload));
  }

  @override
  Future<void> delete(String id) async {
    deletes.add(id);
    if (deleteFailure != null) throw deleteFailure!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PromoCode _promo(String code, {int used = 0, bool active = true}) => PromoCode(
  id: 'id-$code',
  code: code,
  discountType: DiscountType.percent,
  discountValue: 10,
  active: active,
  timesRedeemed: used,
);

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

void main() {
  Future<void> show(
    WidgetTester tester,
    Widget screen, {
    _Knowledge? knowledge,
    _Promos? promos,
  }) async {
    tester.view.physicalSize = const Size(500, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          knowledgeRepositoryProvider.overrideWithValue(
            knowledge ?? _Knowledge(),
          ),
          serviceRepositoryProvider.overrideWithValue(_Services()),
          promoRepositoryProvider.overrideWithValue(promos ?? _Promos([])),
        ],
        child: MaterialApp(theme: AppTheme.light, home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAddForm(WidgetTester tester, {String? tab}) async {
    if (tab != null) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byType(FloatingActionButton).hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
  }

  group('typed text is guarded', () {
    for (final (name, tab, label) in [
      ('variety', null, 'Name'),
      ('guide', 'Guides', 'Title'),
      ('service', 'Services', 'Service name'),
    ]) {
      testWidgets('$name form: type, tap close, and the discard question '
          'comes up', (tester) async {
        await show(tester, const AdminKnowledgeScreen());
        await openAddForm(tester, tab: tab);
        await tester.enterText(field(label), 'Typed');
        await tester.pump();
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsOneWidget);
        // Keep editing: the form and the text are still there.
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.text('Typed'), findsOneWidget);

        // Deleting the text again leaves nothing to discard.
        await tester.enterText(field(label), '');
        await tester.pump();
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
      });
    }

    testWidgets('promo form: type, tap close, and the discard question '
        'comes up', (tester) async {
      await show(tester, const AdminPromoScreen());
      await openAddForm(tester);
      await tester.enterText(field('Code'), 'SAVE10');
      await tester.pump();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('a typed variety stage is guarded too', (tester) async {
      await show(tester, const AdminKnowledgeScreen());
      await openAddForm(tester);
      await tester.ensureVisible(find.textContaining('Add').last);
      await tester.tap(find.textContaining('Add').last);
      await tester.pumpAndSettle();
      // Adding an empty stage is already a change; fill it and close.
      await tester.enterText(field('Stage label').first, 'Tosai');
      await tester.pump();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
    });
  });

  group('guide form', () {
    testWidgets('a new guide is published, shown to customers by default; '
        'switching that off makes it a plain Save', (tester) async {
      final knowledge = _Knowledge();
      await show(tester, const AdminKnowledgeScreen(), knowledge: knowledge);
      await openAddForm(tester, tab: 'Guides');
      expect(find.widgetWithText(ElevatedButton, 'Publish'), findsOneWidget);
      final toggle = find.widgetWithText(SwitchListTile, 'Show to customers');
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ElevatedButton, 'Publish'), findsNothing);
      await tester.enterText(field('Title'), 'Winter feeding');
      await tester.enterText(field('Content'), 'Feed less below 15C.');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();
      final (id, payload) = knowledge.articleWrites.single;
      expect(id, isNull);
      expect(payload['active'], isFalse);
      expect(payload['title'], 'Winter feeding');
    });

    testWidgets('editing a hidden guide says Save, and can show it to '
        'customers', (tester) async {
      final knowledge = _Knowledge()
        ..articles = [
          const KnowledgeArticle(
            id: 'g1',
            title: 'Quarantine',
            bodyMarkdown: 'Two weeks.',
            active: false,
          ),
        ];
      await show(tester, const AdminKnowledgeScreen(), knowledge: knowledge);
      await tester.tap(find.text('Guides'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quarantine'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ElevatedButton, 'Publish'), findsNothing);
      final toggle = find.widgetWithText(SwitchListTile, 'Show to customers');
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();
      final (id, payload) = knowledge.articleWrites.single;
      expect(id, 'g1');
      expect(payload['active'], isTrue);
      // An edit never re-stamps the publish date.
      expect(payload.containsKey('published_at'), isFalse);
    });
  });

  group('knowledge lists', () {
    testWidgets('empty Varieties and Guides say what to do', (tester) async {
      await show(tester, const AdminKnowledgeScreen());
      expect(find.text('No varieties yet'), findsOneWidget);
      await tester.tap(find.text('Guides'));
      await tester.pumpAndSettle();
      expect(find.text('No guides yet'), findsOneWidget);
    });

    testWidgets('hiding a guide cannot be double-tapped, and a failure is '
        'shown', (tester) async {
      final knowledge = _Knowledge()
        ..articles = [
          const KnowledgeArticle(
            id: 'g1',
            title: 'Quarantine',
            bodyMarkdown: '',
          ),
        ]
        ..hold = Completer<void>()
        ..failure = const PostgrestException(message: 'relation "x" missing');
      await show(tester, const AdminKnowledgeScreen(), knowledge: knowledge);
      await tester.tap(find.text('Guides'));
      await tester.pumpAndSettle();
      final hide = find.byTooltip('Hide from customers');
      await tester.tap(hide);
      await tester.tap(hide, warnIfMissed: false);
      await tester.pump();
      expect(knowledge.articleWrites, hasLength(1));
      // Delete is locked while the row is saving.
      await tester.tap(find.byTooltip('Delete'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Delete guide?'), findsNothing);

      knowledge.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Could not update the guide.'), findsOneWidget);
      expect(find.textContaining('relation'), findsNothing);
    });

    testWidgets('a failed guide delete is shown, not thrown away', (
      tester,
    ) async {
      final knowledge = _Knowledge()
        ..articles = [
          const KnowledgeArticle(
            id: 'g1',
            title: 'Quarantine',
            bodyMarkdown: '',
          ),
        ]
        ..failure = const PostgrestException(message: 'boom');
      await show(tester, const AdminKnowledgeScreen(), knowledge: knowledge);
      await tester.tap(find.text('Guides'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
      await tester.pumpAndSettle();
      expect(knowledge.deletes, ['g1']);
      expect(find.text('Could not update the guide.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('promo codes', () {
    testWidgets('a used code is turned off, not deleted', (tester) async {
      final promos = _Promos([_promo('SAVE10', used: 3)]);
      await show(tester, const AdminPromoScreen(), promos: promos);
      expect(find.byTooltip('Delete'), findsNothing);
      await tester.tap(find.byTooltip('Turn off'));
      await tester.pumpAndSettle();
      expect(find.text('Turn off SAVE10?'), findsOneWidget);
      expect(
        find.text(
          'It has been used 3 times, so it is kept for your records. '
          'Customers can no longer apply it.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Turn off'));
      await tester.pumpAndSettle();
      expect(promos.writes.single.$1, 'id-SAVE10');
      expect(promos.writes.single.$2, {'active': false});
      expect(promos.deletes, isEmpty);
    });

    testWidgets('"1 time" is singular, and a code that is used and already '
        'off offers nothing', (tester) async {
      final promos = _Promos([
        _promo('ONCE', used: 1),
        _promo('OLD', used: 5, active: false),
      ]);
      await show(tester, const AdminPromoScreen(), promos: promos);
      expect(find.byTooltip('Turn off'), findsOneWidget);
      expect(find.byTooltip('Delete'), findsNothing);
      await tester.tap(find.byTooltip('Turn off'));
      await tester.pumpAndSettle();
      expect(find.textContaining('It has been used 1 time,'), findsOneWidget);
    });

    testWidgets('an unused code can be deleted; if the database refuses '
        'because it was used meanwhile, its own message is shown', (
      tester,
    ) async {
      const refusal =
          'This promo code has been used and cannot be deleted. '
          'Turn it off instead.';
      final promos = _Promos([_promo('FRESH')])
        ..deleteFailure = const PostgrestException(
          message: refusal,
          code: '23503',
        );
      await show(tester, const AdminPromoScreen(), promos: promos);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
      await tester.pumpAndSettle();
      expect(promos.deletes, ['id-FRESH']);
      expect(find.text(refusal), findsOneWidget);
      expect(
        find.text("This item is still in use, so it can't be changed."),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      // Any other failure keeps the plain fallback, never raw SQL text.
      ScaffoldMessenger.of(tester.element(find.byTooltip('Delete')))
          .clearSnackBars();
      await tester.pumpAndSettle();
      promos.deleteFailure = const PostgrestException(
        message: 'relation "promo_codes" does not exist',
      );
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Could not delete the promo code. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('relation'), findsNothing);
    });
  });
}
