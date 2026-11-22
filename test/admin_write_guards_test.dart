import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/core/theme/app_theme.dart';
import 'package:marugen_app/features/admin/knowledge/admin_knowledge_screen.dart';
import 'package:marugen_app/features/admin/products/admin_products_screen.dart';
import 'package:marugen_app/features/admin/reviews/admin_reviews_screen.dart';
import 'package:marugen_app/features/admin/services/admin_services_screen.dart';
import 'package:marugen_app/features/knowledge/data/knowledge_repository.dart';
import 'package:marugen_app/features/knowledge/presentation/knowledge_providers.dart';
import 'package:marugen_app/features/reviews/data/review_repository.dart';
import 'package:marugen_app/features/reviews/presentation/review_providers.dart';
import 'package:marugen_app/features/services/data/service_repository.dart';
import 'package:marugen_app/features/services/presentation/service_providers.dart';
import 'package:marugen_app/features/shop/data/product_repository.dart';
import 'package:marugen_app/features/shop/presentation/shop_providers.dart';
import 'package:marugen_app/shared/models/knowledge.dart';
import 'package:marugen_app/shared/models/product.dart';
import 'package:marugen_app/shared/models/review.dart';
import 'package:marugen_app/shared/models/service.dart';
import 'package:marugen_app/shared/providers/settings_providers.dart';
import 'package:marugen_app/shared/widgets/guarded_write.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A write the test finishes (or fails) when it chooses.
class HeldWrite {
  final calls = <String>[];
  Completer<void> _done = Completer<void>();

  Future<void> call(String what) {
    calls.add(what);
    return _done.future;
  }

  void succeed() => _settle((done) => done.complete());
  void fail([Object? error]) => _settle(
    (done) => done.completeError(
      error ?? const PostgrestException(message: 'relation "x" does not exist'),
    ),
  );

  void _settle(void Function(Completer<void>) settle) {
    final done = _done;
    _done = Completer<void>();
    settle(done);
  }
}

class Products implements ProductRepository {
  final write = HeldWrite();
  var stock = 1;

  @override
  Future<List<Product>> fetchProductsPage({
    ProductCategory? category,
    required int offset,
    required int limit,
  }) async => offset > 0
      ? []
      : [
          Product.fromMap({
            'id': 'kohaku',
            'name': 'Kohaku 45cm',
            'category': 'koi',
            'price': 800,
            'stock_quantity': stock,
          }),
        ];

  @override
  Future<List<Product>> fetchProducts({ProductCategory? category}) async => [];

  @override
  Future<void> updateProduct(String id, Map<String, dynamic> payload) async {
    await write('$id ${payload['stock_quantity']}');
    stock = payload['stock_quantity'] as int;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Reviews implements ReviewRepository {
  final write = HeldWrite();
  var hidden = false;

  @override
  Future<List<ProductReview>> fetchAllReviewsForAdminPage({
    required int offset,
    required int limit,
  }) async => offset > 0
      ? []
      : [
          ProductReview(
            id: 'review',
            productId: 'kohaku',
            userId: 'buyer',
            rating: 5,
            comment: 'Healthy fish',
            createdAt: DateTime.utc(2026, 11, 1),
            authorName: 'Buyer',
            isHidden: hidden,
          ),
        ];

  @override
  Future<void> setHidden(String reviewId, bool value) async {
    await write('$reviewId $value');
    hidden = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Services implements ServiceRepository {
  final write = HeldWrite();
  final services = [const Service(id: 'boarding', name: 'Pond boarding')];

  @override
  Future<List<Service>> fetchServices() async => List.of(services);

  @override
  Future<void> deleteService(String id) async {
    await write(id);
    services.removeWhere((s) => s.id == id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Knowledge implements KnowledgeRepository {
  final write = HeldWrite();
  var varieties = [const Variety(id: 'showa', name: 'Showa', category: 'koi')];

  @override
  Future<List<Variety>> fetchVarieties({String? category}) async =>
      List.of(varieties);

  @override
  Future<List<KnowledgeArticle>> fetchArticles() async => [];

  @override
  Future<String> upsertVariety(
    Map<String, dynamic> payload, {
    String? id,
  }) async {
    await write('active ${payload['active']}');
    varieties = [
      Variety(
        id: 'showa',
        name: 'Showa',
        category: 'koi',
        active: payload['active'] as bool,
      ),
    ];
    return 'showa';
  }

  @override
  Future<void> deleteVariety(String id) async {
    await write('delete $id');
    varieties = [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> show(
  WidgetTester tester,
  Widget screen,
  List<Override> overrides,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: AppTheme.light, home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('GuardedWrite runs one write at a time and reports a failure '
      'in safe words', (tester) async {
    final write = HeldWrite();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuardedWrite(
            errorFallback: 'Could not save.',
            errorContext: 'test',
            builder: (context, busy, run) => TextButton(
              onPressed: busy ? null : () => run(() => write('save')),
              child: Text(busy ? 'Saving' : 'Save'),
            ),
          ),
        ),
      ),
    );
    final button = find.byType(TextButton);
    // Two taps inside one frame: the button has not been disabled yet.
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();
    expect(write.calls, ['save']);
    expect(find.text('Saving'), findsOneWidget);
    expect(tester.widget<TextButton>(button).onPressed, isNull);

    write.fail();
    await tester.pump();
    await tester.pump();
    expect(find.text('Could not save.'), findsOneWidget);
    expect(find.textContaining('relation'), findsNothing);
    // Usable again after the failure.
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(write.calls, ['save', 'save']);
    write.succeed();
    await tester.pumpAndSettle();
  });

  testWidgets('marking a fish sold cannot be double-tapped, and a failure '
      'is shown', (tester) async {
    final products = Products();
    await show(tester, const AdminProductsScreen(), [
      productRepositoryProvider.overrideWithValue(products),
      shopSettingsProvider.overrideWith((ref) async => <String, dynamic>{}),
    ]);
    final toggle = find.byTooltip('Mark as sold');
    expect(toggle, findsOneWidget);
    final ink = find.descendant(of: toggle, matching: find.byType(InkWell));
    // A full-size touch target around the small pill.
    expect(tester.getSize(ink), const Size(48, 48));
    await tester.tap(ink);
    await tester.tap(ink);
    await tester.pump();
    expect(products.write.calls, ['kohaku 0']);
    expect(tester.widget<InkWell>(ink).onTap, isNull);

    products.write.fail();
    await tester.pumpAndSettle();
    expect(
      find.text('Could not update this fish. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('marked sold'), findsNothing);
    expect(find.byTooltip('Mark as sold'), findsOneWidget);

    // A second attempt goes through and offers Undo.
    ScaffoldMessenger.of(tester.element(toggle)).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(ink);
    await tester.pump();
    products.write.succeed();
    await tester.pumpAndSettle();
    expect(find.text('Kohaku 45cm marked sold'), findsOneWidget);
    expect(find.byTooltip('Mark as available'), findsOneWidget);
  });

  testWidgets('hiding a review cannot be double-tapped, and a failure is '
      'shown', (tester) async {
    final reviews = Reviews();
    await show(tester, const AdminReviewsScreen(), [
      reviewRepositoryProvider.overrideWithValue(reviews),
    ]);
    final hide = find.widgetWithText(TextButton, 'Hide');
    await tester.tap(hide);
    await tester.tap(hide);
    await tester.pump();
    expect(reviews.write.calls, ['review true']);
    expect(tester.widget<TextButton>(hide).onPressed, isNull);

    reviews.write.fail();
    await tester.pumpAndSettle();
    expect(find.text('Could not hide the review.'), findsOneWidget);
    expect(tester.widget<TextButton>(hide).onPressed, isNotNull);

    await tester.tap(hide);
    await tester.pump();
    reviews.write.succeed();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Unhide'), findsOneWidget);
  });

  testWidgets('a service that could not be deleted stays listed with a '
      'message', (tester) async {
    final services = Services();
    await show(tester, const AdminServicesTab(), [
      serviceRepositoryProvider.overrideWithValue(services),
    ]);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
    await tester.pump();
    expect(services.write.calls, ['boarding']);
    // Disabled while the delete is in flight.
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.delete_outline),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );

    services.write.fail(
      const PostgrestException(message: 'fk violation', code: '23503'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text("This item is still in use, so it can't be changed."),
      findsOneWidget,
    );
    expect(find.text('Pond boarding'), findsOneWidget);
  });

  testWidgets('showing, hiding and deleting a variety are guarded the same '
      'way', (tester) async {
    final knowledge = Knowledge();
    await show(tester, const AdminKnowledgeScreen(), [
      knowledgeRepositoryProvider.overrideWithValue(knowledge),
      serviceRepositoryProvider.overrideWithValue(Services()),
    ]);
    final hide = find.byTooltip('Hide from customers');
    await tester.tap(hide);
    await tester.tap(hide);
    await tester.pump();
    expect(knowledge.write.calls, ['active false']);
    // Delete is locked too while the row is saving, and the tap does not
    // fall through to the row and open the edit form.
    await tester.tap(find.byTooltip('Delete'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Delete variety?'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);

    knowledge.write.fail();
    await tester.pumpAndSettle();
    expect(find.text('Could not update the variety.'), findsOneWidget);
    expect(find.byTooltip('Hide from customers'), findsOneWidget);

    ScaffoldMessenger.of(tester.element(hide)).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(hide);
    await tester.pump();
    knowledge.write.succeed();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show to customers'), findsOneWidget);
    expect(find.text('Hidden from customers'), findsOneWidget);

    ScaffoldMessenger.of(tester.element(find.byTooltip('Delete')))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
    await tester.pump();
    expect(knowledge.write.calls.last, 'delete showa');
    knowledge.write.fail();
    await tester.pumpAndSettle();
    expect(find.text('Could not update the variety.'), findsOneWidget);
    expect(find.text('Showa'), findsOneWidget);
  });
}
