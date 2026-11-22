// Page review 22 Nov 2026, banner form: a failed check or save is never
// off-screen, and backing out of the time picker changes nothing.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/banners/admin_banners_screen.dart';
import 'package:marugen_app/features/banners/data/home_banner_repository.dart';
import 'package:marugen_app/features/banners/presentation/home_banner_providers.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/home_banner.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

class _Banners implements HomeBannerRepository {
  final saved = <Map<String, dynamic>>[];
  Object? failure;

  @override
  Future<String> upsertBanner(
    Map<String, dynamic> payload, {
    String? id,
  }) async {
    if (failure != null) throw failure!;
    saved.add(payload);
    return id ?? 'new';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<_Banners> open(
    WidgetTester tester,
    HomeBanner? existing, {
    Size size = const Size(390, 520),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _Banners();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeBannerRepositoryProvider.overrideWithValue(repo),
          adminHomeBannersProvider.overrideWith((ref) async => []),
          liveHomeBannersProvider.overrideWith((ref) async => []),
          adminAllProductsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: BannerFormScreen(existing: existing),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  bool onScreen(WidgetTester tester, Finder finder) {
    final rect = tester.getRect(finder);
    final screen = tester.view.physicalSize;
    return rect.top >= 0 && rect.bottom <= screen.height;
  }

  final snackBarText = find.descendant(
    of: find.byType(SnackBar),
    matching: find.byType(Text),
  );

  testWidgets('a schedule that ends before it starts is named in a '
      'snackbar and scrolled into view from the top of the form', (
    tester,
  ) async {
    final repo = await open(
      tester,
      HomeBanner(
        id: 'b1',
        imageUrl: '',
        startsAt: DateTime(2026, 12, 10, 9),
        endsAt: DateTime(2026, 12, 1, 9),
      ),
    );
    // The schedule is far below a short screen.
    expect(find.text('SCHEDULE (OPTIONAL)'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(repo.saved, isEmpty);
    expect(tester.widget<Text>(snackBarText).data, 'End must be after start.');
    expect(onScreen(tester, find.text('SCHEDULE (OPTIONAL)')), isTrue);
  });

  testWidgets('a missing photo is named and brought back into view from '
      'the bottom Save button', (tester) async {
    final repo = await open(tester, null);
    await tester.scrollUntilVisible(
      find.widgetWithText(ElevatedButton, 'Add Banner'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Banner'));
    await tester.pumpAndSettle();
    expect(repo.saved, isEmpty);
    expect(tester.widget<Text>(snackBarText).data, 'Add a photo.');
    expect(onScreen(tester, find.text('PREVIEW')), isTrue);
  });

  testWidgets('a failed save is shown as a snackbar as well as inline', (
    tester,
  ) async {
    final repo = await open(tester, const HomeBanner(id: 'b1', imageUrl: ''));
    repo.failure = const PostgrestException(message: 'relation "x" missing');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    const message = 'Could not save the banner. Please try again.';
    expect(tester.widget<Text>(snackBarText).data, message);
    expect(find.textContaining('relation'), findsNothing);
    // Still on the form, with the same message by the Save button.
    expect(find.byType(BannerFormScreen), findsOneWidget);
    expect(find.text(message, skipOffstage: false), findsWidgets);
  });

  testWidgets('cancelling the time picker leaves the schedule as it was', (
    tester,
  ) async {
    final repo = await open(
      tester,
      const HomeBanner(id: 'b1', imageUrl: ''),
      size: const Size(600, 2400),
    );
    expect(find.text('Immediately'), findsOneWidget);
    await tester.tap(find.text('Immediately'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // Now on the time picker: back out.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Immediately'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(repo.saved.single['starts_at'], isNull);
  });
}
