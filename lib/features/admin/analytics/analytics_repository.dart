import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';

/// App opens and product views on one Singapore calendar day.
class DailyActivity {
  final DateTime day;
  final int visits;
  final int productViews;

  const DailyActivity({
    required this.day,
    required this.visits,
    this.productViews = 0,
  });
}

/// One row of the most-viewed list; the name is null if the product was
/// since deleted.
class TopViewedProduct {
  final String? productId;
  final String? productName;
  final int views;

  const TopViewedProduct({
    this.productId,
    this.productName,
    required this.views,
  });
}

/// Counts are added up on the server (migration 0074, admin-only): fetching
/// raw events stopped at PostgREST's 1000-row limit.
class AnalyticsRepository {
  final SupabaseClient _client;
  AnalyticsRepository({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  /// One row per day for the last [days] days, oldest first.
  Future<List<DailyActivity>> fetchDailyActivity({int days = 190}) async {
    final rows = await _client.rpc(
      'admin_daily_activity',
      params: {'p_days': days},
    ) as List;
    return rows.map((e) {
      final row = e as Map<String, dynamic>;
      return DailyActivity(
        day: DateTime.parse(row['day'] as String),
        visits: (row['visits'] as num).toInt(),
        productViews: (row['product_views'] as num).toInt(),
      );
    }).toList();
  }

  /// The [limit] most viewed products over the last [days] days.
  Future<List<TopViewedProduct>> fetchTopViewedProducts({
    required int days,
    int limit = 10,
  }) async {
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .toUtc()
        .toIso8601String();
    final rows = await _client.rpc(
      'admin_top_viewed_products',
      params: {'p_since': since, 'p_limit': limit},
    ) as List;
    return rows.map((e) {
      final row = e as Map<String, dynamic>;
      return TopViewedProduct(
        productId: row['product_id'] as String?,
        productName: row['product_name'] as String?,
        views: (row['views'] as num).toInt(),
      );
    }).toList();
  }
}
