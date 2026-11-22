// Page review 22 Nov 2026, admin product editor: the weight x size stock
// matrix follows its rows (duplicate / remove / rename), "Show price" works
// on products with options, a single fish has a Gender, and Save is pinned.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/products/admin_product_edit_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

const _cellPrefix = 'Stock for ';

/// The matrix as staff see it: "1kg, Small" -> "4".
Map<String, String> shownCells(WidgetTester tester) => {
  for (final element in find
      .byWidgetPredicate(
        (w) =>
            w is Semantics &&
            (w.properties.label ?? '').startsWith(_cellPrefix),
      )
      .evaluate())
    (element.widget as Semantics).properties.label!.substring(
      _cellPrefix.length,
    ): tester
        .widget<TextField>(
          find.descendant(
            of: find.byWidget(element.widget),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text,
};

void main() {
  late Map<String, dynamic> storedProduct;
  late List<Map<String, dynamic>> storedVariants;
  late List<Map<String, dynamic>> productWrites;
  late List<Map<String, dynamic>> variantCreates;
  late Map<String, Map<String, dynamic>> variantUpdates;
  late List<String> variantDeletes;
  late List<Map<String, dynamic>> stockUpserts;
  late List<String> stockDeletes;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://matrix.invalid',
      publishableKey: 'test-key',
      httpClient: MockClient((request) async {
        http.Response json(Object body) => http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
        final path = request.url.path;
        final query = request.url.queryParameters;
        if (request.method == 'GET') {
          if (path.endsWith('/products')) return json(storedProduct);
          if (path.endsWith('/product_variants')) return json(storedVariants);
          return json([]);
        }
        if (path.endsWith('/products')) {
          productWrites.add(
            (jsonDecode(request.body) as Map).cast<String, dynamic>(),
          );
        } else if (path.endsWith('/product_variants')) {
          if (request.method == 'DELETE') {
            variantDeletes.add(query['id']!.replaceFirst('eq.', ''));
          } else if (request.method == 'POST') {
            final body = (jsonDecode(request.body) as Map)
                .cast<String, dynamic>();
            variantCreates.add(body);
            return json({'id': 'new-${variantCreates.length}', ...body});
          } else {
            variantUpdates[query['id']!.replaceFirst('eq.', '')] =
                (jsonDecode(request.body) as Map).cast<String, dynamic>();
          }
        } else if (path.endsWith('/product_variant_size_stocks')) {
          if (request.method == 'DELETE') {
            stockDeletes.add(
              '${query['variant_id']!.replaceFirst('eq.', '')}/'
              '${query['size_label']!.replaceFirst('eq.', '')}',
            );
          } else {
            final body = jsonDecode(request.body);
            stockUpserts.add(
              ((body is List ? body.single : body) as Map)
                  .cast<String, dynamic>(),
            );
          }
        }
        return json([]);
      }),
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  Map<String, dynamic> variant(String id, String label, int small, int medium) =>
      {
        'id': id,
        'product_id': 'food-1',
        'label': label,
        'price': 20,
        'stock_quantity': 0,
        'sort_order': 0,
        'size_stocks': [
          {'size_label': 'Small', 'stock_quantity': small},
          {'size_label': 'Medium', 'stock_quantity': medium},
        ],
      };

  setUp(() {
    storedProduct = {
      'id': 'food-1',
      'name': 'Growth pellets',
      'category': 'fish_food',
      'stock_quantity': 0,
      'price': 20,
      'show_price': true,
      'size_options': ['Small', 'Medium'],
    };
    storedVariants = [
      variant('v1', '1kg', 1, 2),
      variant('v2', '2kg', 3, 4),
      variant('v3', '5kg', 5, 6),
    ];
    productWrites = [];
    variantCreates = [];
    variantUpdates = {};
    variantDeletes = [];
    stockUpserts = [];
    stockDeletes = [];
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/edit'),
              child: const Text('open editor'),
            ),
          ),
        ),
        GoRoute(
          path: '/edit',
          builder: (_, _) => AdminProductEditScreen(
            productId: storedProduct['id'] as String,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.tap(find.text('open editor'));
    await tester.pumpAndSettle();
  }

  final saveButton = find.widgetWithText(ElevatedButton, 'Save');

  Future<void> save(WidgetTester tester) async {
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(find.text('open editor'), findsOneWidget, reason: 'saved + closed');
  }

  /// What was written, in the same shape as [shownCells], with variant ids
  /// turned back into the labels they were saved with.
  Map<String, String> savedCells() {
    final labels = {
      for (final e in variantUpdates.entries) e.key: e.value['label'] as String,
      for (var i = 0; i < variantCreates.length; i++)
        'new-${i + 1}': variantCreates[i]['label'] as String,
    };
    return {
      for (final row in stockUpserts)
        '${labels[row['variant_id']]}, ${row['size_label']}':
            '${row['stock_quantity']}',
    };
  }

  const loaded = {
    '1kg, Small': '1',
    '1kg, Medium': '2',
    '2kg, Small': '3',
    '2kg, Medium': '4',
    '5kg, Small': '5',
    '5kg, Medium': '6',
  };

  testWidgets('duplicating the first of three weights leaves every other '
      'cell where it was, and the save writes what is shown', (tester) async {
    await open(tester);
    expect(shownCells(tester), loaded);

    await tester.tap(find.byTooltip('Duplicate option').first);
    await tester.pumpAndSettle();
    // The copy has no label yet, so it has no matrix row; nothing moved.
    expect(shownCells(tester), loaded);

    await tester.enterText(field('Label').at(1), '3kg');
    await tester.pumpAndSettle();
    final shown = shownCells(tester);
    expect(shown, {...loaded, '3kg, Small': '0', '3kg, Medium': '0'});

    await save(tester);
    expect(savedCells(), shown);
    expect(variantCreates.single['label'], '3kg');
    expect(variantCreates.single['sort_order'], 1);
    expect(stockDeletes, isEmpty);
  });

  testWidgets('renaming a size keeps its quantities and saves them under '
      'the new name', (tester) async {
    await open(tester);
    await tester.enterText(field('Size').first, 'Tiny');
    await tester.pumpAndSettle();
    final shown = shownCells(tester);
    expect(shown, {
      '1kg, Tiny': '1',
      '1kg, Medium': '2',
      '2kg, Tiny': '3',
      '2kg, Medium': '4',
      '5kg, Tiny': '5',
      '5kg, Medium': '6',
    });

    await save(tester);
    expect(savedCells(), shown);
    expect(productWrites.last['size_options'], ['Tiny', 'Medium']);
    // The old label's rows go; nothing under the new name is removed.
    expect(stockDeletes, ['v1/Small', 'v2/Small', 'v3/Small']);
  });

  testWidgets('removing a weight leaves the other weights their own stock', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Remove option').at(1));
    await tester.pumpAndSettle();
    final shown = shownCells(tester);
    expect(shown, {
      '1kg, Small': '1',
      '1kg, Medium': '2',
      '5kg, Small': '5',
      '5kg, Medium': '6',
    });

    await save(tester);
    expect(savedCells(), shown);
    expect(variantDeletes, ['v2']);
  });

  testWidgets('removing a size that has stock asks first', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Remove size').first);
    await tester.pumpAndSettle();
    expect(find.text('Remove size "Small"?'), findsOneWidget);
    expect(
      find.text('Its stock for every weight will be deleted when you save.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(shownCells(tester), loaded);

    await tester.tap(find.byTooltip('Remove size').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(shownCells(tester), {
      '1kg, Medium': '2',
      '2kg, Medium': '4',
      '5kg, Medium': '6',
    });

    // A size with no stock anywhere goes without a question.
    await tester.tap(find.text('Add Size'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Size').last, 'Large');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove size').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Remove size "'), findsNothing);
    expect(field('Size'), findsOneWidget);
  });

  testWidgets('a product with options can still hide its price, and is told '
      'why sale price is unavailable', (tester) async {
    await open(tester);
    expect(
      find.text(
        'This product has options below. Each option has its own price and '
        'stock; sale price is not available for products with options yet.',
      ),
      findsOneWidget,
    );
    // Save is pinned and waits for a change.
    expect(tester.widget<ElevatedButton>(saveButton).onPressed, isNull);

    final showPrice = find.widgetWithText(
      SwitchListTile,
      'Show price to customers',
    );
    expect(tester.widget<SwitchListTile>(showPrice).value, isTrue);
    await tester.tap(showPrice);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(showPrice).value, isFalse);
    expect(tester.widget<ElevatedButton>(saveButton).onPressed, isNotNull);

    await save(tester);
    expect(productWrites.last['show_price'], isFalse);
  });

  group('single live fish', () {
    setUp(() {
      storedProduct = {
        'id': 'fish-1',
        'name': 'Kohaku',
        'category': 'koi',
        'stock_quantity': 1,
        'price': 300,
        'fish_details': {'variety': 'Kohaku', 'size_cm': 45},
      };
      storedVariants = [];
    });

    bool chosen(WidgetTester tester, String label) =>
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

    testWidgets('gender defaults to Unknown, counts as a change and is '
        'written to fish_details', (tester) async {
      await open(tester);
      expect(find.text('Gender'), findsOneWidget);
      expect(chosen(tester, 'Unknown'), isTrue);
      expect(tester.widget<ElevatedButton>(saveButton).onPressed, isNull);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Male'));
      await tester.pumpAndSettle();
      expect(chosen(tester, 'Male'), isTrue);
      expect(tester.widget<ElevatedButton>(saveButton).onPressed, isNotNull);

      await save(tester);
      final fish = productWrites.last['fish_details'] as Map;
      expect(fish['gender'], 'Male');
      expect(fish['variety'], 'Kohaku');
      expect(fish['size_cm'], 45.0);
    });

    testWidgets('choosing Unknown again removes a stored gender', (
      tester,
    ) async {
      (storedProduct['fish_details'] as Map)['gender'] = 'female';
      await open(tester);
      expect(chosen(tester, 'Female'), isTrue);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Unknown'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(
        (productWrites.last['fish_details'] as Map).containsKey('gender'),
        isFalse,
      );
    });

    testWidgets('a size that is not a length is refused with an example', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(field('Size (cm)'), '4 5');
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      expect(find.text('Enter the length in cm, e.g. 45'), findsOneWidget);
      expect(productWrites, isEmpty);
      expect(find.text('open editor'), findsNothing);
    });
  });
}
