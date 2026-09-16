import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/skeleton.dart';
import 'knowledge_providers.dart';

/// Two tabs: "Varieties" (koi/arowana catalog with photos, no prices — pure
/// education) and "Guides" (care articles authored by admin).
class KnowledgeScreen extends ConsumerWidget {
  const KnowledgeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Koi & Arowana Guide'),
          bottom: const TabBar(
            indicatorColor: AppColors.red,
            tabs: [Tab(text: 'Varieties'), Tab(text: 'Care Guides')],
          ),
        ),
        body: const TabBarView(
          children: [_VarietiesTab(), _ArticlesTab()],
        ),
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
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.offWhite,
                  backgroundImage: v.imageUrl != null ? NetworkImage(v.imageUrl!) : null,
                  child: v.imageUrl == null
                      ? const Icon(Icons.water, color: AppColors.grey)
                      : null,
                ),
                title: Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  v.category.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.grey),
                ),
                onTap: () => showModalBottomSheet(
                  context: context,
                  showDragHandle: true,
                  builder: (_) => Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (v.description != null) Text(v.description!),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          children: [for (final t in v.traits) Chip(label: Text(t))],
                        ),
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
            return Card(
              child: ListTile(
                title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  a.bodyMarkdown,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
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
                          Text(a.title,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Text(a.bodyMarkdown),
                        ],
                      ),
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
