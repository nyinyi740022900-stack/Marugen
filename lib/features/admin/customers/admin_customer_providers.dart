import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/address.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/order.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../orders/presentation/orders_providers.dart';
import '../../profile/presentation/address_providers.dart';

/// The three pieces of data the admin "view customer" screen needs, keyed
/// by the target customer's user id — separate providers (rather than one
/// combined fetch) so each section can show its own loading/error state
/// and a slow one (e.g. a customer with a long order history) doesn't
/// block the others.
final customerProfileProvider =
    FutureProvider.family<AppUser?, String>((ref, userId) {
  return ref.watch(authRepositoryProvider).fetchAppUserById(userId);
});

final customerAddressesProvider =
    FutureProvider.family<List<Address>, String>((ref, userId) {
  return ref.watch(addressRepositoryProvider).fetchAddressesForUser(userId);
});

final customerOrdersProvider =
    FutureProvider.family<List<Order>, String>((ref, userId) {
  return ref.watch(orderRepositoryProvider).fetchOrdersForUser(userId);
});
