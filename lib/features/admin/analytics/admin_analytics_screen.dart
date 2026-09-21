import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'analytics_providers.dart';
import 'analytics_repository.dart';

enum _Period { daily, weekly, monthly }

/// One aggregated bucket (a day/week/month) with its visit count.
class _Bucket {
  final String label;
  final DateTime start;
  int count = 0;
  _Bucket(this.label, this.start);
}

DateTime _startOfWeek(DateTime d) =>
    DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Builds the last [count] period buckets ending today (oldest first) and
/// fills each with how many of [timestamps] fall inside it.
List<_Bucket> _buildBuckets(_Period period, List<DateTime> timestamps, int count) {
  final now = DateTime.now();
  final buckets = <_Bucket>[];
  for (var i = count - 1; i >= 0; i--) {
    switch (period) {
      case _Period.daily:
        final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
        buckets.add(_Bucket('${day.day}/${day.month}', day));
      case _Period.weekly:
        final weekStart = _startOfWeek(now).subtract(Duration(days: i * 7));
        buckets.add(_Bucket('${weekStart.day}/${weekStart.month}', weekStart));
      case _Period.monthly:
        final month = DateTime(now.year, now.month - i, 1);
        buckets.add(_Bucket(_monthNames[month.month - 1], month));
    }
  }

  for (final ts in timestamps) {
    for (var i = buckets.length - 1; i >= 0; i--) {
      final start = buckets[i].start;
      final end = i + 1 < buckets.length ? buckets[i + 1].start : null;
      if (!ts.isBefore(start) && (end == null || ts.isBefore(end))) {
        buckets[i].count++;
        break;
      }
    }
  }
  return buckets;
}

Map<String, int> _topProducts(List<ProductViewRow> views, DateTime since, {int take = 10}) {
  final counts = <String, int>{};
  for (final v in views) {
    if (v.viewedAt.isBefore(since)) continue;
    final name = v.productName ?? '(deleted product)';
    counts[name] = (counts[name] ?? 0) + 1;
  }
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return {for (final e in sorted.take(take)) e.key: e.value};
}

class AdminAnalyticsScreen extends ConsumerStatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  ConsumerState<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends ConsumerState<AdminAnalyticsScreen> {
  _Period _period = _Period.daily;

  int get _bucketCount => switch (_period) {
        _Period.daily => 14,
        _Period.weekly => 8,
        _Period.monthly => 6,
      };

  DateTime get _since => switch (_period) {
        _Period.daily => DateTime.now().subtract(const Duration(days: 14)),
        _Period.weekly => DateTime.now().subtract(const Duration(days: 56)),
        _Period.monthly => DateTime.now().subtract(const Duration(days: 180)),
      };

  @override
  Widget build(BuildContext context) {
    final visitsAsync = ref.watch(appVisitsProvider);
    final viewsAsync = ref.watch(productViewsProvider);

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(title: const Text('ANALYTICS')),
      body: RefreshIndicator(
        color: AppColors.red,
        onRefresh: () async {
          ref.invalidate(appVisitsProvider);
          ref.invalidate(productViewsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            SegmentedButton<_Period>(
              segments: const [
                ButtonSegment(value: _Period.daily, label: Text('Daily')),
                ButtonSegment(value: _Period.weekly, label: Text('Weekly')),
                ButtonSegment(value: _Period.monthly, label: Text('Monthly')),
              ],
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.first),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'APP VISITS',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
                color: AppColors.grey,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            visitsAsync.when(
              data: (visits) {
                final buckets = _buildBuckets(_period, visits, _bucketCount);
                final total = buckets.fold<int>(0, (s, b) => s + b.count);
                return Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: AppShadows.card,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$total visits',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                      const SizedBox(height: AppSpacing.md),
                      _BarChart(buckets: buckets),
                    ],
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) =>
                  Text('Error: $e', style: const TextStyle(color: AppColors.error)),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'TOP VIEWED PRODUCTS',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
                color: AppColors.grey,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            viewsAsync.when(
              data: (views) {
                final top = _topProducts(views, _since);
                if (top.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: const Text('No product views in this period.',
                        style: TextStyle(color: AppColors.grey)),
                  );
                }
                final maxCount = top.values.first;
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: AppShadows.card,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final entry in top.entries) ...[
                        if (entry.key != top.keys.first)
                          const Divider(height: 1, indent: 16, endIndent: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(entry.key,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                                  Text('${entry.value}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700, color: AppColors.red)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: entry.value / maxCount,
                                  minHeight: 6,
                                  backgroundColor: AppColors.offWhite,
                                  color: AppColors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) =>
                  Text('Error: $e', style: const TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimal bar chart (no charting dependency) — a row of proportionally
/// tall bars with period labels underneath.
class _BarChart extends StatelessWidget {
  final List<_Bucket> buckets;
  const _BarChart({required this.buckets});

  @override
  Widget build(BuildContext context) {
    final maxCount = buckets.fold<int>(1, (m, b) => b.count > m ? b.count : m);
    return SizedBox(
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final b in buckets)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${b.count}', style: const TextStyle(fontSize: 9, color: AppColors.grey)),
                    const SizedBox(height: 2),
                    Container(
                      height: 60 * (b.count / maxCount).clamp(0.03, 1.0),
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(b.label, style: const TextStyle(fontSize: 9, color: AppColors.grey)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
