import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/knowledge_repository.dart';

final knowledgeRepositoryProvider = Provider<KnowledgeRepository>((ref) => KnowledgeRepository());

final varietiesProvider = FutureProvider.family((ref, String? category) {
  return ref.watch(knowledgeRepositoryProvider).fetchVarieties(category: category);
});

final articlesProvider = FutureProvider((ref) {
  return ref.watch(knowledgeRepositoryProvider).fetchArticles();
});
