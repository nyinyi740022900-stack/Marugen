// Code review 22 Nov 2026, terms: the GST sentence follows the rate set in
// Admin > Settings instead of always saying the shop charges none.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/legal/terms_screen.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';

const notRegistered =
    'Marugen Fish Farm is not GST-registered, so no GST is charged.';

String paragraph(String sentence) =>
    'All prices are shown in Singapore Dollars (SGD). $sentence Some products '
    'may be marked "Contact us for price" and require you to reach out to the '
    'shop directly. We reserve the right to correct pricing errors and to '
    'cancel or refuse an order at our discretion, for example when a product '
    'is no longer available.';

Future<void> showTerms(
  WidgetTester tester,
  FutureOr<Map<String, dynamic>> Function() settings,
) async {
  tester.view.physicalSize = const Size(390, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [shopSettingsProvider.overrideWith((ref) => settings())],
      child: const MaterialApp(home: TermsScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  test('the sentence for each setting', () {
    expect(termsGstSentence(null), notRegistered);
    expect(termsGstSentence(const {}), notRegistered);
    expect(
      termsGstSentence(const {'gst_percent': 0, 'gst_included_in_price': false}),
      notRegistered,
    );
    expect(
      termsGstSentence(const {'gst_percent': 9, 'gst_included_in_price': true}),
      'Prices include Goods and Services Tax (GST) at 9%.',
    );
    expect(
      termsGstSentence(const {'gst_percent': 9, 'gst_included_in_price': false}),
      'Goods and Services Tax (GST) at 9% is added at checkout.',
    );
    // The stored rate, written as everywhere else.
    expect(
      termsGstSentence(const {'gst_percent': 8.5, 'gst_included_in_price': true}),
      'Prices include Goods and Services Tax (GST) at 8.5%.',
    );
    expect(
      termsGstSentence(const {'gst_percent': 9.0, 'gst_included_in_price': false}),
      'Goods and Services Tax (GST) at 9% is added at checkout.',
    );
  });

  testWidgets('9% inside the prices', (tester) async {
    await showTerms(
      tester,
      () => {'gst_percent': 9, 'gst_included_in_price': true},
    );
    expect(
      find.text(
        paragraph('Prices include Goods and Services Tax (GST) at 9%.'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('not GST-registered'), findsNothing);
  });

  testWidgets('9% added at checkout', (tester) async {
    await showTerms(
      tester,
      () => {'gst_percent': 9, 'gst_included_in_price': false},
    );
    expect(
      find.text(
        paragraph('Goods and Services Tax (GST) at 9% is added at checkout.'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('not GST-registered'), findsNothing);
  });

  testWidgets('0%: not GST-registered, the rest of the paragraph unchanged', (
    tester,
  ) async {
    await showTerms(
      tester,
      () => {'gst_percent': 0, 'gst_included_in_price': true},
    );
    expect(find.text(paragraph(notRegistered)), findsOneWidget);
    expect(find.textContaining('Goods and Services Tax'), findsNothing);
  });

  testWidgets('settings still loading: not GST-registered', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    await showTerms(tester, () => pending.future);
    expect(find.text(paragraph(notRegistered)), findsOneWidget);

    pending.complete({'gst_percent': 9, 'gst_included_in_price': true});
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('at 9%.'), findsOneWidget);
  });

  testWidgets('settings unavailable: not GST-registered', (tester) async {
    await showTerms(tester, () => throw Exception('offline'));
    expect(find.text(paragraph(notRegistered)), findsOneWidget);
  });
}
