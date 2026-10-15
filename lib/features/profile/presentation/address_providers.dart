import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/address.dart';
import '../data/address_repository.dart';
import '../../auth/presentation/auth_providers.dart';

final addressRepositoryProvider = Provider<AddressRepository>(
  (ref) => AddressRepository(),
);

final myAddressesProvider = FutureProvider<List<Address>>((ref) async {
  final owner = ref.watch(currentUserIdProvider);
  if (owner == null) return [];
  final addresses = await ref
      .watch(addressRepositoryProvider)
      .fetchMyAddresses();
  return addresses.where((address) => address.userId == owner).toList();
});
