import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/shared/providers/paged_notifier.dart';

final filterProvider = StateProvider<String>((ref) => 'all');

/// Every page request is held until the test answers it.
class HeldPages extends PagedNotifier<String> {
  final requests =
      <({String filter, int offset, Completer<List<String>> done})>[];

  @override
  Future<List<String>> fetchPage(int offset, int limit) {
    final request = (
      filter: ref.watch(filterProvider),
      offset: offset,
      done: Completer<List<String>>(),
    );
    requests.add(request);
    return request.done.future;
  }
}

final heldPagesProvider =
    NotifierProvider<HeldPages, AsyncValue<PagedListState<String>>>(
      HeldPages.new,
    );

List<String> page(String prefix, [int count = kAdminPageSize]) => [
  for (var i = 0; i < count; i++) '$prefix$i',
];

void main() {
  late ProviderContainer container;
  late HeldPages pages;
  List<String>? shown() => container.read(heldPagesProvider).valueOrNull?.items;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(heldPagesProvider, (_, _) {});
    pages = container.read(heldPagesProvider.notifier);
  });

  test('a slow answer for the previous filter never replaces the current '
      'filter\'s rows', () async {
    container.read(filterProvider.notifier).state = 'shipped';
    container.read(heldPagesProvider);
    expect(pages.requests.map((r) => r.filter), ['all', 'shipped']);

    pages.requests[1].done.complete(['shipped-order']);
    await pumpEventQueue();
    expect(shown(), ['shipped-order']);

    // The request for "all" finally lands.
    pages.requests[0].done.complete(['old-order']);
    await pumpEventQueue();
    expect(shown(), ['shipped-order']);
  });

  test('a next page that finishes after a refresh is dropped', () async {
    pages.requests.single.done.complete(page('a'));
    await pumpEventQueue();

    unawaited(pages.loadNextPage());
    unawaited(pages.refresh());
    expect(pages.requests.map((r) => r.offset), [0, kAdminPageSize, 0]);

    pages.requests[2].done.complete(['fresh']);
    await pumpEventQueue();
    expect(shown(), ['fresh']);

    // Page two of the list that was thrown away.
    pages.requests[1].done.complete(page('b'));
    await pumpEventQueue();
    final state = container.read(heldPagesProvider).requireValue;
    expect(state.items, ['fresh']);
    expect(state.isLoadingMore, isFalse);
    expect(state.hasMore, isFalse);
  });

  test('a failed next page from before a refresh does not bring back the '
      'old rows', () async {
    pages.requests.single.done.complete(page('a'));
    await pumpEventQueue();
    unawaited(pages.loadNextPage());
    unawaited(pages.refresh());
    pages.requests[2].done.complete(['fresh']);
    await pumpEventQueue();
    pages.requests[1].done.completeError(Exception('offline'));
    await pumpEventQueue();
    expect(shown(), ['fresh']);
  });

  test('an older refresh that fails late does not hide newer rows', () async {
    pages.requests.single.done.complete(page('a'));
    await pumpEventQueue();
    unawaited(pages.refresh());
    unawaited(pages.refresh());
    pages.requests[2].done.complete(['newest']);
    await pumpEventQueue();
    pages.requests[1].done.completeError(Exception('offline'));
    await pumpEventQueue();
    expect(container.read(heldPagesProvider).hasError, isFalse);
    expect(shown(), ['newest']);
  });

  test('pages still append in order when nothing races', () async {
    pages.requests.single.done.complete(page('a'));
    await pumpEventQueue();
    final loading = pages.loadNextPage();
    expect(
      container.read(heldPagesProvider).requireValue.isLoadingMore,
      isTrue,
    );
    pages.requests[1].done.complete(['b0']);
    await loading;
    final state = container.read(heldPagesProvider).requireValue;
    expect(state.items, [...page('a'), 'b0']);
    expect(state.hasMore, isFalse);
  });
}
