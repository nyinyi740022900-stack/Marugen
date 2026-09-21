import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics_repository.dart';

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) => AnalyticsRepository());

final productViewsProvider = FutureProvider((ref) {
  return ref.watch(analyticsRepositoryProvider).fetchProductViews();
});

final appVisitsProvider = FutureProvider((ref) {
  return ref.watch(analyticsRepositoryProvider).fetchAppVisits();
});
