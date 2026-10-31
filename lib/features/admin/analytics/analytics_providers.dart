import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics_repository.dart';

final analyticsRepositoryProvider = Provider<AnalyticsRepository>(
  (ref) => AnalyticsRepository(),
);

/// Enough days for the monthly view's six months.
final dailyActivityProvider = FutureProvider<List<DailyActivity>>((ref) {
  return ref.watch(analyticsRepositoryProvider).fetchDailyActivity();
});

/// Most viewed products over the last N days.
final topViewedProductsProvider =
    FutureProvider.family<List<TopViewedProduct>, int>((ref, days) {
      return ref
          .watch(analyticsRepositoryProvider)
          .fetchTopViewedProducts(days: days);
    });
