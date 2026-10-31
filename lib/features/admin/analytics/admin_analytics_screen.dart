import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'analytics_providers.dart';
import 'analytics_repository.dart';
import '../../../shared/utils/error_message.dart';
import '../../../shared/widgets/empty_state.dart';

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
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Builds the last [count] period buckets ending today (oldest first) and
/// adds each day's visits to the bucket it falls in.
List<_Bucket> _buildBuckets(
  _Period period,
  List<DailyActivity> days,
  int count,
) {
  final now = DateTime.now();
  final buckets = <_Bucket>[];
  for (var i = count - 1; i >= 0; i--) {
    switch (period) {
      case _Period.daily:
        final day = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: i));
        buckets.add(_Bucket('${day.day}/${day.month}', day));
      case _Period.weekly:
        final weekStart = _startOfWeek(now).subtract(Duration(days: i * 7));
        buckets.add(_Bucket('${weekStart.day}/${weekStart.month}', weekStart));
      case _Period.monthly:
        final month = DateTime(now.year, now.month - i, 1);
        buckets.add(_Bucket(_monthNames[month.month - 1], month));
    }
  }

  for (final d in days) {
    for (var i = buckets.length - 1; i >= 0; i--) {
      final start = buckets[i].start;
      final end = i + 1 < buckets.length ? buckets[i + 1].start : null;
      if (!d.day.isBefore(start) && (end == null || d.day.isBefore(end))) {
        buckets[i].count += d.visits;
        break;
      }
    }
  }
  return buckets;
}

Map<String, int> _topProducts(List<TopViewedProduct> rows) {
  final counts = <String, int>{};
  for (final row in rows) {
    counts.update(
      row.productName ?? '(deleted product)',
      (count) => count + row.views,
      ifAbsent: () => row.views,
    );
  }
  return counts;
}

class AdminAnalyticsScreen extends ConsumerStatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  ConsumerState<AdminAnalyticsScreen> createState() =>
      _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends ConsumerState<AdminAnalyticsScreen> {
  _Period _period = _Period.daily;

  int get _bucketCount => switch (_period) {
    _Period.daily => 14,
    _Period.weekly => 8,
    _Period.monthly => 6,
  };

  int get _sinceDays => switch (_period) {
    _Period.daily => 14,
    _Period.weekly => 56,
    _Period.monthly => 180,
  };

  @override
  Widget build(BuildContext context) {
    final visitsAsync = ref.watch(dailyActivityProvider);
    final viewsAsync = ref.watch(topViewedProductsProvider(_sinceDays));

    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: AppBar(title: const Text('ANALYTICS')),
      body: RefreshIndicator(
        color: AppPalette.of(context).accent,
        onRefresh: () async {
          ref.invalidate(dailyActivityProvider);
          ref.invalidate(topViewedProductsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_Period>(
                segments: const [
                  ButtonSegment(value: _Period.daily, label: Text('Daily')),
                  ButtonSegment(value: _Period.weekly, label: Text('Weekly')),
                  ButtonSegment(value: _Period.monthly, label: Text('Monthly')),
                ],
                selected: {_period},
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'APP VISITS',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
                color: AppPalette.of(context).textMuted,
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
                    color: AppPalette.of(context).surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: AppShadows.card,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$total visits',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
              error: (e, _) => InlineErrorState(
                message: friendlyErrorMessage(
                  e,
                  fallback: 'Could not load visits.',
                  context: 'admin.analytics',
                ),
                onRetry: () => ref.invalidate(dailyActivityProvider),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'TOP VIEWED PRODUCTS',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
                color: AppPalette.of(context).textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            viewsAsync.when(
              data: (views) {
                final top = _topProducts(views);
                if (top.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: AppPalette.of(context).surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'No product views in this period.',
                      style: TextStyle(color: AppPalette.of(context).textMuted),
                    ),
                  );
                }
                final maxCount = top.values.first;
                return Container(
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).surface,
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
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry.key,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${entry.value}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppPalette.of(context).accent,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: entry.value / maxCount,
                                  minHeight: 6,
                                  backgroundColor: AppPalette.of(context)
                                      .surfaceMuted,
                                  color: AppPalette.of(context).accent,
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
              error: (e, _) => InlineErrorState(
                message: friendlyErrorMessage(
                  e,
                  fallback: 'Could not load product views.',
                  context: 'admin.analytics',
                ),
                onRetry: () =>
                    ref.invalidate(topViewedProductsProvider(_sinceDays)),
              ),
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
    final scaler = MediaQuery.textScalerOf(context);
    final countWidth = maxCount.toString().length * scaler.scale(9) * 0.7 + 12;
    final labelWidth = buckets.fold<double>(0, (width, b) {
      final next = b.label.length * scaler.scale(9) * 0.7 + 12;
      return next > width ? next : width;
    });
    final bucketWidth = countWidth > labelWidth ? countWidth : labelWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minimumWidth = bucketWidth * buckets.length;
        final width = minimumWidth > constraints.maxWidth
            ? minimumWidth
            : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final b in buckets)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '${b.count}',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 9,
                              color: AppPalette.of(context).textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            height: 60 * (b.count / maxCount).clamp(0.03, 1.0),
                            decoration: BoxDecoration(
                              color: AppPalette.of(context).accent,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            b.label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 9,
                              color: AppPalette.of(context).textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
