import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/knowledge.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/fullscreen_image_gallery.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../services/presentation/services_tab.dart';
import 'knowledge_providers.dart';

/// `Image.network` with a fallback icon instead of the framework's default
/// red error box when a stale/broken URL (deleted storage object, bad
/// data) fails to load — every knowledge image below goes through this
/// rather than a bare `Image.network(...)`.
Widget _networkImage(String url, {required BoxFit fit}) {
  return Image.network(
    url,
    fit: fit,
    errorBuilder: (_, _, _) => const ColoredBox(
      color: AppColors.offWhite,
      child: Icon(Icons.image_not_supported_outlined, color: AppColors.greySoft),
    ),
  );
}

/// Three tabs: "Varieties" (koi/arowana catalog with photos + growth-stage
/// gallery — pure education, no prices), "Guides" (care articles authored
/// by admin), and "Services" (farm services like recovery/quarantine or
/// pond-renovation boarding, contact-to-book).
class KnowledgeScreen extends ConsumerWidget {
  const KnowledgeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Koi & Arowana Guide'),
          bottom: const TabBar(
            indicatorColor: AppColors.red,
            tabs: [Tab(text: 'Varieties'), Tab(text: 'Care Guides'), Tab(text: 'Services')],
          ),
        ),
        body: const TabBarView(
          children: [_VarietiesTab(), _ArticlesTab(), ServicesTab()],
        ),
      ),
    );
  }
}

/// One growth-stage photo card in the variety detail sheet's horizontal
/// gallery (e.g. "Tosai" → "Nisai" → "Sansai").
class _StageCard extends StatelessWidget {
  final VarietyStage stage;
  final VoidCallback? onTap;
  const _StageCard({required this.stage, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: stage.imageUrl != null
                ? GestureDetector(
                    onTap: onTap,
                    child: _networkImage(stage.imageUrl!, fit: BoxFit.cover),
                  )
                : const ColoredBox(
                    color: AppColors.lightGrey,
                    child: Icon(Icons.water, color: AppColors.grey),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
                if (stage.description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    stage.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.grey),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VarietiesTab extends ConsumerWidget {
  const _VarietiesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final varietiesAsync = ref.watch(varietiesProvider(null));
    return varietiesAsync.when(
      data: (varieties) {
        if (varieties.isEmpty) {
          return const EmptyState(
            icon: Icons.water_outlined,
            title: 'No varieties added yet',
            subtitle: 'Koi & arowana varieties will appear here once published.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: varieties.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, i) {
            final v = varieties[i];
            // All photos for this variety (cover + growth stages), in the
            // order they should page through in the fullscreen gallery.
            final galleryUrls = [
              if (v.imageUrl != null) v.imageUrl!,
              for (final s in v.stages)
                if (s.imageUrl != null) s.imageUrl!,
            ];
            return Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: AppShadows.card,
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => showModalBottomSheet(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (_) => DraggableScrollableSheet(
                      initialChildSize: 0.65,
                      maxChildSize: 0.9,
                      expand: false,
                      builder: (_, scrollController) => SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (v.imageUrl != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                child: GestureDetector(
                                  onTap: () => FullscreenImageGallery.open(
                                    context,
                                    imageUrls: galleryUrls,
                                  ),
                                  // BoxFit.contain (not .cover) so the whole
                                  // photo is visible up-front — previously
                                  // .cover cropped it, and seeing the full
                                  // image meant tapping into the fullscreen
                                  // gallery. Background fills the letterbox
                                  // when the photo isn't exactly 4:3.
                                  child: AspectRatio(
                                    aspectRatio: 4 / 3,
                                    child: ColoredBox(
                                      color: AppColors.offWhite,
                                      child: _networkImage(v.imageUrl!, fit: BoxFit.contain),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                            ],
                            Text(v.name,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            if (v.description != null) Text(v.description!),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 6,
                              children: [for (final t in v.traits) Chip(label: Text(t))],
                            ),
                            if (v.stages.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.lg),
                              const Text(
                                'GROWTH STAGES',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  letterSpacing: 0.8,
                                  color: AppColors.grey,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              SizedBox(
                                height: 190,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: v.stages.length,
                                  separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                                  itemBuilder: (_, i) => _StageCard(
                                    stage: v.stages[i],
                                    onTap: v.stages[i].imageUrl == null
                                        ? null
                                        : () => FullscreenImageGallery.open(
                                              context,
                                              imageUrls: galleryUrls,
                                              initialIndex: galleryUrls.indexOf(v.stages[i].imageUrl!),
                                            ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          child: SizedBox(
                            width: 64,
                            height: 64,
                            child: v.imageUrl != null
                                ? _networkImage(v.imageUrl!, fit: BoxFit.cover)
                                : const ColoredBox(
                                    color: AppColors.offWhite,
                                    child: Icon(Icons.water, color: AppColors.grey),
                                  ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.redSoft,
                                      borderRadius: BorderRadius.circular(AppRadius.pill),
                                    ),
                                    child: Text(
                                      v.category.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.redDark,
                                      ),
                                    ),
                                  ),
                                  if (v.stages.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '${v.stages.length} stages',
                                      style: const TextStyle(
                                          fontSize: 11.5, color: AppColors.grey),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.grey),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () => ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListRowSkeleton(),
          SizedBox(height: 10),
          ListRowSkeleton(),
          SizedBox(height: 10),
          ListRowSkeleton(),
        ],
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _ArticlesTab extends ConsumerWidget {
  const _ArticlesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articlesAsync = ref.watch(articlesProvider);
    return articlesAsync.when(
      data: (articles) {
        if (articles.isEmpty) {
          return const EmptyState(
            icon: Icons.menu_book_outlined,
            title: 'No guides published yet',
            subtitle: 'Care guides from the Marugen team will show up here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: articles.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, i) {
            final a = articles[i];
            return Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: AppShadows.card,
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => showModalBottomSheet(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (_) => DraggableScrollableSheet(
                      initialChildSize: 0.7,
                      expand: false,
                      builder: (_, controller) => SingleChildScrollView(
                        controller: controller,
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (a.coverImageUrl != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                // BoxFit.contain (not .cover) so the whole
                                // cover photo is visible up-front, plus a
                                // tap-to-fullscreen gesture (matching the
                                // variety image above) for a closer look.
                                child: GestureDetector(
                                  onTap: () => FullscreenImageGallery.open(
                                    context,
                                    imageUrls: [a.coverImageUrl!],
                                  ),
                                  child: SizedBox(
                                    height: 160,
                                    width: double.infinity,
                                    child: ColoredBox(
                                      color: AppColors.offWhite,
                                      child: _networkImage(a.coverImageUrl!, fit: BoxFit.contain),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                            ],
                            Text(a.title,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Text(a.bodyMarkdown),
                          ],
                        ),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (a.coverImageUrl != null)
                        SizedBox(
                          width: 88,
                          height: 88,
                          child: _networkImage(a.coverImageUrl!, fit: BoxFit.cover),
                        )
                      else
                        Container(
                          width: 88,
                          height: 88,
                          color: AppColors.offWhite,
                          child: const Icon(Icons.menu_book_outlined, color: AppColors.grey),
                        ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 15)),
                              const SizedBox(height: 4),
                              Text(
                                a.bodyMarkdown,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: AppSpacing.sm),
                        child: Icon(Icons.chevron_right, color: AppColors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () => ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListRowSkeleton(),
          SizedBox(height: 10),
          ListRowSkeleton(),
          SizedBox(height: 10),
          ListRowSkeleton(),
        ],
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}
