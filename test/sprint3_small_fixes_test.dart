import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/banners/admin_banners_screen.dart';
import 'package:marugen_app/features/banners/presentation/hero_banner_carousel.dart';
import 'package:marugen_app/features/banners/presentation/home_banner_providers.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/home_banner.dart';

void main() {
  testWidgets('the banner photo button and its hint stay readable on a '
      'phone at 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const existing = HomeBanner(id: 'b1', imageUrl: '');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminHomeBannersProvider.overrideWith((ref) async => [existing]),
          liveHomeBannersProvider.overrideWith((ref) async => [existing]),
          adminAllProductsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const BannerFormScreen(existing: existing),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final button = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Replace photo'),
    );
    final hint = tester.getRect(
      find.text('Landscape photo, about 2:1. Resized to 1600 px.'),
    );
    // The hint has a line of its own under the button, not the few pixels
    // left beside it.
    expect(hint.top, greaterThanOrEqualTo(button.bottom));
    expect(hint.width, greaterThan(200));
    expect(button.right, lessThanOrEqualTo(320));
    expect(hint.right, lessThanOrEqualTo(320));
  });

  testWidgets('a banner headline is announced once', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: BannerCarousel(
            banners: [
              HomeBanner(
                id: 'a',
                imageUrl: '',
                title: 'New Kohaku arrivals',
                subtitle: 'From Niigata',
                ctaLabel: 'Shop now',
                linkUrl: '/product/1',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    // Still on screen for sighted users.
    expect(find.text('New Kohaku arrivals'), findsOneWidget);

    final spoken = <String>[];
    void collect(SemanticsNode node) {
      if (node.label.isNotEmpty) spoken.add(node.label);
      node.visitChildren((child) {
        collect(child);
        return true;
      });
    }

    collect(
      tester
          .binding
          .renderViews
          .first
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!,
    );
    final all = spoken.join('\n');
    expect('New Kohaku arrivals'.allMatches(all), hasLength(1));
    expect(all, contains('Banner 1 of 1: New Kohaku arrivals. Shop now'));
    // The subtitle is not in the label, so it is still read.
    expect(all, contains('From Niigata'));
    semantics.dispose();
  });

  testWidgets('the admin preview still announces the headline it shows', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: BannerSlide(
              banner: HomeBanner(id: 'a', imageUrl: '', title: 'Preview title'),
            ),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Preview title'), findsOneWidget);
    semantics.dispose();
  });

  test('startup no longer prints boot progress to the device log', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, isNot(contains('[BOOT]')));
  });
}
