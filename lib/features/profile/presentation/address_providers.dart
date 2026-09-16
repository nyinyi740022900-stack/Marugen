import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/address.dart';
import '../data/address_repository.dart';

final addressRepositoryProvider = Provider<AddressRepository>((ref) => AddressRepository());

final myAddressesProvider = FutureProvider<List<Address>>((ref) {
  return ref.watch(addressRepositoryProvider).fetchMyAddresses();
});
