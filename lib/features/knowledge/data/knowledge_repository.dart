import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/knowledge.dart';

class KnowledgeRepository {
  final _client = SupabaseService.client;

  Future<List<Variety>> fetchVarieties({String? category}) async {
    var query = _client.from('varieties').select();
    if (category != null) query = query.eq('category', category);
    final data = await query.order('name');
    return (data as List).map((e) => Variety.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<List<KnowledgeArticle>> fetchArticles() async {
    final data = await _client
        .from('knowledge_articles')
        .select()
        .order('published_at', ascending: false);
    return (data as List)
        .map((e) => KnowledgeArticle.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> upsertVariety(Map<String, dynamic> payload, {String? id}) async {
    if (id != null) {
      await _client.from('varieties').update(payload).eq('id', id);
    } else {
      await _client.from('varieties').insert(payload);
    }
  }

  Future<void> upsertArticle(Map<String, dynamic> payload, {String? id}) async {
    if (id != null) {
      await _client.from('knowledge_articles').update(payload).eq('id', id);
    } else {
      await _client.from('knowledge_articles').insert(payload);
    }
  }

  Future<void> deleteVariety(String id) async {
    await _client.from('varieties').delete().eq('id', id);
  }

  Future<void> deleteArticle(String id) async {
    await _client.from('knowledge_articles').delete().eq('id', id);
  }
}
