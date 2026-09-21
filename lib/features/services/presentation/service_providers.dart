import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/service_repository.dart';

final serviceRepositoryProvider = Provider<ServiceRepository>((ref) => ServiceRepository());

final servicesProvider = FutureProvider((ref) {
  return ref.watch(serviceRepositoryProvider).fetchServices();
});
