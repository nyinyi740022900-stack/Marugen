import 'dart:typed_data';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/knowledge.dart';

class KnowledgeRepository {
  final _client = SupabaseService.client;

  /// Uploads to the same `product-images` bucket (admin-write/anyone-read
  /// policies already cover it) under a `varieties/` prefix so no new
  /// bucket/policy migration is needed.
  Future<String> uploadVarietyImage(
      String varietyId, Uint8List bytes, String ext) async {
    final path =
        'varieties/$varietyId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('product-images').uploadBinary(path, bytes);
    return _client.storage.from('product-images').getPublicUrl(path);
  }

  /// Same bucket, `articles/` prefix — for a guide's cover photo.
  Future<String> uploadArticleImage(
      String articleId, Uint8List bytes, String ext) async {
    final path =
        'articles/$articleId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('product-images').uploadBinary(path, bytes);
    return _client.storage.from('product-images').getPublicUrl(path);
  }

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

  /// Returns the variety's id (existing [id], or the newly generated one)
  /// so the caller can upload stage/cover images under it right after.
  Future<String> upsertVariety(Map<String, dynamic> payload, {String? id}) async {
    if (id != null) {
      await _client.from('varieties').update(payload).eq('id', id);
      return id;
    }
    final row = await _client.from('varieties').insert(payload).select().single();
    return row['id'] as String;
  }

  /// Returns the article's id (existing [id], or the newly generated one)
  /// so the caller can upload a cover image under it right after.
  Future<String> upsertArticle(Map<String, dynamic> payload, {String? id}) async {
    if (id != null) {
      await _client.from('knowledge_articles').update(payload).eq('id', id);
      return id;
    }
    final row = await _client.from('knowledge_articles').insert(payload).select().single();
    return row['id'] as String;
  }

  Future<void> deleteVariety(String id) async {
    await _client.from('varieties').delete().eq('id', id);
  }

  Future<void> deleteArticle(String id) async {
    await _client.from('knowledge_articles').delete().eq('id', id);
  }
}
