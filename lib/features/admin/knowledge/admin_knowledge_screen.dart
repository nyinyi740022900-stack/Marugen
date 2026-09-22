import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../knowledge/presentation/knowledge_providers.dart';
import '../services/admin_services_screen.dart';
import 'admin_article_form.dart';
import 'admin_variety_form.dart';

class AdminKnowledgeScreen extends ConsumerWidget {
  const AdminKnowledgeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Knowledge'),
          bottom: const TabBar(
            indicatorColor: AppColors.red,
            tabs: [Tab(text: 'Varieties'), Tab(text: 'Guides'), Tab(text: 'Services')],
          ),
        ),
        body: const TabBarView(
          children: [_AdminVarieties(), _AdminArticles(), AdminServicesTab()],
        ),
      ),
    );
  }
}

class _AdminVarieties extends ConsumerWidget {
  const _AdminVarieties();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final varietiesAsync = ref.watch(varietiesProvider(null));
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.red,
        onPressed: () => showVarietyForm(context, ref),
        child: const Icon(Icons.add, color: AppColors.white),
      ),
      body: varietiesAsync.when(
        data: (varieties) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: varieties.length,
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
                  v.active
                      ? '${v.category.toUpperCase()}'
                          '${v.stages.isNotEmpty ? ' · ${v.stages.length} stages' : ''}'
                      : 'Hidden from customers',
                  style: TextStyle(color: v.active ? null : AppColors.error),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: v.active ? 'Hide from customers' : 'Show to customers',
                      icon: Icon(
                        v.active ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: v.active ? AppColors.grey : AppColors.error,
                      ),
                      onPressed: () async {
                        await ref
                            .read(knowledgeRepositoryProvider)
                            .upsertVariety({'active': !v.active}, id: v.id);
                        ref.invalidate(varietiesProvider);
                      },
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline, color: AppColors.error),
                      onPressed: () async {
                        final confirmed = await confirmDestructiveAction(
                          context,
                          title: 'Delete variety?',
                          message: 'This permanently removes "${v.name}". This cannot be undone.',
                        );
                        if (!confirmed) return;
                        await ref.read(knowledgeRepositoryProvider).deleteVariety(v.id);
                        ref.invalidate(varietiesProvider);
                      },
                    ),
                  ],
                ),
                onTap: () => showVarietyForm(context, ref, existing: v),
              ),
            );
          },
        ),
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.red),
        ),
        error: (e, _) => ErrorState(onRetry: () => ref.invalidate(varietiesProvider)),
      ),
    );
  }
}

class _AdminArticles extends ConsumerWidget {
  const _AdminArticles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articlesAsync = ref.watch(articlesProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.red,
        onPressed: () => showArticleForm(context, ref),
        child: const Icon(Icons.add, color: AppColors.white),
      ),
      body: articlesAsync.when(
        data: (articles) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: articles.length,
          itemBuilder: (context, i) {
            final a = articles[i];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.offWhite,
                  backgroundImage:
                      a.coverImageUrl != null ? NetworkImage(a.coverImageUrl!) : null,
                  child: a.coverImageUrl == null
                      ? const Icon(Icons.menu_book_outlined, color: AppColors.grey)
                      : null,
                ),
                title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  a.active ? a.bodyMarkdown : 'Hidden from customers',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: a.active ? null : AppColors.error),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: a.active ? 'Hide from customers' : 'Show to customers',
                      icon: Icon(
                        a.active ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: a.active ? AppColors.grey : AppColors.error,
                      ),
                      onPressed: () async {
                        await ref
                            .read(knowledgeRepositoryProvider)
                            .upsertArticle({'active': !a.active}, id: a.id);
                        ref.invalidate(articlesProvider);
                      },
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline, color: AppColors.error),
                      onPressed: () async {
                        final confirmed = await confirmDestructiveAction(
                          context,
                          title: 'Delete article?',
                          message: 'This permanently removes "${a.title}". This cannot be undone.',
                        );
                        if (!confirmed) return;
                        await ref.read(knowledgeRepositoryProvider).deleteArticle(a.id);
                        ref.invalidate(articlesProvider);
                      },
                    ),
                  ],
                ),
                onTap: () => showArticleForm(context, ref, existing: a),
              ),
            );
          },
        ),
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.red),
        ),
        error: (e, _) => ErrorState(onRetry: () => ref.invalidate(articlesProvider)),
      ),
    );
  }
}
