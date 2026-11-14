import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/banners/presentation/hero_banner_carousel.dart';
import 'package:marugen_app/shared/models/home_banner.dart';

// Empty image URLs render the local placeholder, so no network is touched.
const _slides = [
  HomeBanner(id: 'a', imageUrl: '', title: 'First', linkUrl: '/product/1'),
  HomeBanner(id: 'b', imageUrl: '', title: 'Second'),
  HomeBanner(id: 'c', imageUrl: '', title: 'Third', ctaLabel: 'Shop'),
];

Widget _host(
  Widget child, {
  bool reduceMotion = false,
  Size size = const Size(390, 844),
}) => MaterialApp(
  theme: AppTheme.light,
  home: MediaQuery(
    data: MediaQueryData(size: size, disableAnimations: reduceMotion),
    child: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
  ),
);

void main() {
  group('HomeBanner schedule', () {
    final now = DateTime(2026, 11, 14, 12);
    test('live inside an open-ended or bounded window', () {
      expect(const HomeBanner(id: 'x', imageUrl: 'u').isLiveAt(now), isTrue);
      expect(
        HomeBanner(
          id: 'x',
          imageUrl: 'u',
          startsAt: now.subtract(const Duration(hours: 1)),
          endsAt: now.add(const Duration(hours: 1)),
        ).scheduleAt(now),
        BannerSchedule.live,
      );
    });
    test('scheduled, ended and hidden are told apart', () {
      expect(
        HomeBanner(
          id: 'x',
          imageUrl: 'u',
          startsAt: now.add(const Duration(minutes: 1)),
        ).scheduleAt(now),
        BannerSchedule.scheduled,
      );
      expect(
        HomeBanner(id: 'x', imageUrl: 'u', endsAt: now).scheduleAt(now),
        BannerSchedule.ended,
      );
      expect(
        const HomeBanner(id: 'x', imageUrl: 'u', active: false).scheduleAt(now),
        BannerSchedule.hidden,
      );
    });
    test('in-app paths are told apart from web links', () {
      expect(_slides[0].linksInsideApp, isTrue);
      expect(
        const HomeBanner(id: 'w', imageUrl: 'u', linkUrl: 'https://x.y')
            .linksInsideApp,
        isFalse,
      );
    });
  });

  group('BannerCarousel', () {
    testWidgets('auto-advances, wraps, and shows one dot per slide', (
      tester,
    ) async {
      // The interval leaves room for the 420 ms page animation plus the
      // frames pumpAndSettle itself advances, so each step lands on one tick.
      await tester.pumpWidget(
        _host(
          const BannerCarousel(
            banners: _slides,
            interval: Duration(seconds: 2),
          ),
        ),
      );
      expect(find.text('First'), findsOneWidget);
      expect(find.bySemanticsLabel('Banner 1 of 3'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      expect(find.bySemanticsLabel('Banner 2 of 3'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Third'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      // Third → wraps to First.
      expect(find.text('First'), findsOneWidget);
    });

    testWidgets('a swipe pauses auto-advance and the reader keeps the slide', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const BannerCarousel(
            banners: _slides,
            interval: Duration(seconds: 1),
            resumeAfterTouch: Duration(seconds: 5),
          ),
        ),
      );
      await tester.fling(find.text('First'), const Offset(-300, 0), 1200);
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      // Two intervals pass; the timer is paused by the touch.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      // After the pause it moves on again.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Third'), findsOneWidget);
    });

    testWidgets('tapping a slide opens its link; tapping a dot jumps', (
      tester,
    ) async {
      HomeBanner? opened;
      await tester.pumpWidget(
        _host(
          BannerCarousel(
            banners: _slides,
            interval: const Duration(minutes: 1),
            onOpen: (b) => opened = b,
          ),
        ),
      );
      await tester.tap(find.text('First'));
      expect(opened?.id, 'a');

      final dots = find.byType(AnimatedContainer);
      expect(dots, findsNWidgets(3));
      await tester.tap(dots.at(2));
      await tester.pumpAndSettle();
      expect(find.text('Third'), findsOneWidget);
      expect(find.text('Shop'), findsOneWidget);
    });

    testWidgets('Reduce Motion turns auto-advance off', (tester) async {
      await tester.pumpWidget(
        _host(
          const BannerCarousel(
            banners: _slides,
            interval: Duration(seconds: 1),
          ),
          reduceMotion: true,
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('First'), findsOneWidget);
    });

    testWidgets('a single slide shows no dots and does not advance', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          BannerCarousel(
            banners: [_slides.first],
            interval: const Duration(seconds: 1),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(AnimatedContainer), findsNothing);
      expect(find.text('First'), findsOneWidget);
    });

    testWidgets('headline stays readable at large text on a narrow phone', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: BannerCarousel(
                banners: const [
                  HomeBanner(
                    id: 'l',
                    imageUrl: '',
                    title: 'A fairly long headline about autumn koi',
                    subtitle: 'Subtitle that is hidden at this size',
                    ctaLabel: 'Shop now',
                  ),
                ],
                interval: const Duration(minutes: 1),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('A fairly long'), findsOneWidget);
      expect(find.text('Subtitle that is hidden at this size'), findsNothing);
    });
  });
}
