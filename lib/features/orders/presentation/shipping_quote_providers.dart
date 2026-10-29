import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/shipping_quote_repository.dart';
import '../domain/shipping_quote.dart';

final shippingQuoteRepositoryProvider = Provider<ShippingQuoteRepository>(
  (ref) => ShippingQuoteRepository(),
);

/// Key includes account, exact cart choices, address and promotion. A changed
/// checkout can never reuse a cached fee from another address or account.
final checkoutShippingQuoteProvider = FutureProvider.autoDispose
    .family<ShippingQuote, String>((ref, key) async {
      final request = Map<String, dynamic>.from(jsonDecode(key) as Map);
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null || request.remove('user_id') != userId) {
        throw StateError('Choose a delivery address for your current account.');
      }
      final quote = await ref
          .watch(shippingQuoteRepositoryProvider)
          .fetchQuote(request);
      if (quote.isExpired) {
        throw StateError('Delivery quote expired. Please refresh.');
      }
      final timer = Timer(
        quote.expiresAt.difference(DateTime.now().toUtc()),
        ref.invalidateSelf,
      );
      ref.onDispose(timer.cancel);
      return quote;
    });
