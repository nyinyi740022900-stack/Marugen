import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/knowledge.dart';
import '../../knowledge/presentation/knowledge_providers.dart';

class AdminKnowledgeScreen extends ConsumerWidget {
  const AdminKnowledgeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Knowledge'),
          bottom: const TabBar(
            indicatorColor: AppColors.red,
            tabs: [Tab(text: 'Varieties'), Tab(text: 'Guides')],
          ),
        ),
        body: const TabBarView(children: [_AdminVarieties(), _AdminArticles()]),
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
        onPressed: () => _showVarietyForm(context, ref),
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
                title: Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(v.category.toUpperCase()),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () async {
                    await ref.read(knowledgeRepositoryProvider).deleteVariety(v.id);
                    ref.invalidate(varietiesProvider);
                  },
                ),
                onTap: () => _showVarietyForm(context, ref, existing: v),
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showVarietyForm(BuildContext context, WidgetRef ref, {Variety? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name);
    final descCtrl = TextEditingController(text: existing?.description);
    final traitsCtrl = TextEditingController(text: existing?.traits.join(', '));
    String category = existing?.category ?? 'koi';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.xl,
          right: AppSpacing.xl,
          top: AppSpacing.xl,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xl,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(existing == null ? 'Add Variety' : 'Edit Variety',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.lg),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: category,
                items: const [
                  DropdownMenuItem(value: 'koi', child: Text('Koi')),
                  DropdownMenuItem(value: 'arowana', child: Text('Arowana')),
                ],
                onChanged: (v) => category = v ?? 'koi',
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: traitsCtrl,
                decoration: const InputDecoration(
                    labelText: 'Traits (comma-separated)',
                    hintText: 'e.g. Red & white, Metallic scales'),
              ),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: () async {
                  await ref.read(knowledgeRepositoryProvider).upsertVariety({
                    'name': nameCtrl.text.trim(),
                    'category': category,
                    'description': descCtrl.text.trim(),
                    'traits': traitsCtrl.text
                        .split(',')
                        .map((t) => t.trim())
                        .where((t) => t.isNotEmpty)
                        .toList(),
                  }, id: existing?.id);
                  ref.invalidate(varietiesProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
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
        onPressed: () => _showArticleForm(context, ref),
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
                title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(a.bodyMarkdown, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () async {
                    await ref.read(knowledgeRepositoryProvider).deleteArticle(a.id);
                    ref.invalidate(articlesProvider);
                  },
                ),
                onTap: () => _showArticleForm(context, ref, existingId: a.id, title: a.title, body: a.bodyMarkdown),
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showArticleForm(BuildContext context, WidgetRef ref,
      {String? existingId, String? title, String? body}) {
    final titleCtrl = TextEditingController(text: title);
    final bodyCtrl = TextEditingController(text: body);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.xl,
          right: AppSpacing.xl,
          top: AppSpacing.xl,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xl,
        ),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(existingId == null ? 'Add Guide' : 'Edit Guide',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.lg),
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: bodyCtrl,
              decoration: const InputDecoration(labelText: 'Content'),
              maxLines: 8,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: () async {
                await ref.read(knowledgeRepositoryProvider).upsertArticle({
                  'title': titleCtrl.text.trim(),
                  'body_markdown': bodyCtrl.text.trim(),
                  'published_at': DateTime.now().toIso8601String(),
                }, id: existingId);
                ref.invalidate(articlesProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Publish'),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
