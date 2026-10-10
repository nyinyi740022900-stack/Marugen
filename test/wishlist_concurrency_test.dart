import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/features/auth/presentation/auth_providers.dart';
import 'package:marugen_app/features/wishlist/data/wishlist_repository.dart';
import 'package:marugen_app/features/wishlist/presentation/wishlist_providers.dart';

class DelayedWishlist implements WishlistRepository {
  final removes = <String, Completer<void>>{};
  @override
  Future<Set<String>> fetchMyWishlistProductIds() async => {'a', 'b'};
  @override
  Future<void> remove(String productId) =>
      (removes[productId] = Completer<void>()).future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'One failed favorite update preserves other successful changes',
    () async {
      final repository = DelayedWishlist();
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => const Stream.empty()),
          currentUserIdProvider.overrideWithValue('customer'),
          wishlistRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final wishlist = container.read(wishlistProductIdsProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(wishlistProductIdsProvider).requireValue, {
        'a',
        'b',
      });
      final removeA = wishlist.toggle('a', true);
      final failedA = expectLater(removeA, throwsA(isA<StateError>()));
      final removeB = wishlist.toggle('b', true);
      repository.removes['b']!.complete();
      await removeB;
      repository.removes['a']!.completeError(StateError('network failed'));
      await failedA;
      expect(container.read(wishlistProductIdsProvider).requireValue, {'a'});
    },
  );
}
