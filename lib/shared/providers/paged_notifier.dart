import 'package:flutter/widgets.dart' show ScrollController;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Page size used by every paged admin list — one place to tune it.
const int kAdminPageSize = 20;

/// Accumulated state for an infinite-scroll list: everything loaded so
/// far, plus whether there's more to fetch and whether a "load next page"
/// request is currently in flight.
class PagedListState<T> {
  final List<T> items;
  final bool hasMore;
  final bool isLoadingMore;

  const PagedListState({
    this.items = const [],
    this.hasMore = true,
    this.isLoadingMore = false,
  });

  PagedListState<T> copyWith({
    List<T>? items,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return PagedListState<T>(
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// Base class for an infinite-scroll admin list — fetches page 0 on
/// build, appends further pages via [loadNextPage] (call this from a
/// `ScrollController` listener once the view nears the bottom), and
/// supports [refresh] after a mutation (delete/update/reply) instead of
/// the old pattern of `ref.invalidate`-ing an unbounded full-table fetch.
///
/// No pagination pattern existed anywhere in this codebase before this —
/// every admin list previously fetched its entire table in one
/// unbounded query (`fetchAllOrders`, `fetchProducts`, etc. with no
/// `.range()`), which works fine at today's data volumes but would get
/// slower and heavier with every order/product ever created, forever.
abstract class PagedNotifier<T> extends Notifier<AsyncValue<PagedListState<T>>> {
  /// Fetches exactly one page: rows `[offset, offset + limit)`, in the
  /// list's stable sort order (so pages don't overlap/skip as new rows
  /// are added between fetches).
  Future<List<T>> fetchPage(int offset, int limit);

  /// Identifies the list the state currently belongs to. Every first-page
  /// load (the initial build, a filter change, [refresh]) starts a new
  /// generation; a response that comes back for an older one is dropped,
  /// so a slow request for a previous filter, or a [loadNextPage] that
  /// finishes after a [refresh], can never overwrite newer rows.
  int _generation = 0;

  @override
  AsyncValue<PagedListState<T>> build() {
    // Also covers responses that arrive after the provider is disposed.
    ref.onDispose(() => _generation++);
    _loadFirstPage();
    return const AsyncLoading();
  }

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    try {
      final items = await fetchPage(0, kAdminPageSize);
      if (generation != _generation) return;
      state = AsyncData(PagedListState(items: items, hasMore: items.length == kAdminPageSize));
    } catch (e, st) {
      if (generation != _generation) return;
      state = AsyncError(e, st);
    }
  }

  /// Re-fetches from page 0, discarding whatever was accumulated —
  /// call after a mutation (delete/hide/status-change) instead of
  /// appending, since the mutated row's position in the sort order may
  /// have moved and a stale item shouldn't linger in the middle of the list.
  Future<void> refresh() => _loadFirstPage();

  Future<void> loadNextPage() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;
    final generation = _generation;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final next = await fetchPage(current.items.length, kAdminPageSize);
      if (generation != _generation) return;
      state = AsyncData(PagedListState(
        items: [...current.items, ...next],
        hasMore: next.length == kAdminPageSize,
      ));
    } catch (_) {
      if (generation != _generation) return;
      // A transient failure loading page N+1 shouldn't wipe the N pages
      // already showing — just stop the spinner; scrolling again retries.
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }
}

/// Drop-in `ScrollController` helper: call from `initState`, and it calls
/// [loadNextPage] once the user scrolls within [threshold] pixels of the
/// bottom. Kept tiny/inline-able rather than a shared widget, since each
/// screen already owns its own `ScrollController`/`GridView`/`ListView`.
extension PagedScrollTrigger on ScrollController {
  void attachPagination(Future<void> Function() loadNextPage, {double threshold = 400}) {
    addListener(() {
      if (!hasClients) return;
      if (position.pixels >= position.maxScrollExtent - threshold) {
        loadNextPage();
      }
    });
  }
}
