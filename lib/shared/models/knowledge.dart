/// A koi/arowana variety catalog entry (e.g. "Kohaku", "Showa", "Super Red
/// Arowana") — educational content, separate from sellable [Product]s,
/// though the shop screen can link "available in store" products by variety.
class Variety {
  final String id;
  final String name;
  final String category; // 'koi' | 'arowana'
  final String? description;
  final String? imageUrl;
  final List<String> traits;

  const Variety({
    required this.id,
    required this.name,
    required this.category,
    this.description,
    this.imageUrl,
    this.traits = const [],
  });

  factory Variety.fromMap(Map<String, dynamic> map) {
    return Variety(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      category: map['category'] as String? ?? 'koi',
      description: map['description'] as String?,
      imageUrl: map['image_url'] as String?,
      traits: (map['traits'] as List?)?.cast<String>() ?? const [],
    );
  }
}

/// A care/guide article (water quality, feeding, disease prevention, etc.)
/// authored by admin in the Knowledge section.
class KnowledgeArticle {
  final String id;
  final String title;
  final String bodyMarkdown;
  final String? coverImageUrl;
  final DateTime? publishedAt;

  const KnowledgeArticle({
    required this.id,
    required this.title,
    required this.bodyMarkdown,
    this.coverImageUrl,
    this.publishedAt,
  });

  factory KnowledgeArticle.fromMap(Map<String, dynamic> map) {
    return KnowledgeArticle(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      bodyMarkdown: map['body_markdown'] as String? ?? '',
      coverImageUrl: map['cover_image_url'] as String?,
      publishedAt: map['published_at'] != null
          ? DateTime.tryParse(map['published_at'] as String)
          : null,
    );
  }
}
