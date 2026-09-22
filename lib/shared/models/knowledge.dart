/// One growth/size stage of a variety (e.g. "Tosai — under 1yr", "Nisai —
/// 2yr") with its own photo, shown as a gallery so customers can see how
/// the pattern/colour develops as the fish matures.
class VarietyStage {
  final String label;
  final String? imageUrl;
  final String? description;

  const VarietyStage({required this.label, this.imageUrl, this.description});

  factory VarietyStage.fromMap(Map<String, dynamic> map) {
    return VarietyStage(
      label: map['label'] as String? ?? '',
      imageUrl: map['image_url'] as String?,
      description: map['description'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'label': label,
        'image_url': imageUrl,
        'description': description,
      };
}

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

  /// Growth-stage photo gallery (e.g. Tosai → Nisai → Sansai), ordered
  /// young to mature.
  final List<VarietyStage> stages;

  /// Off hides this entry from customers (RLS-enforced — see migration
  /// 0044) without deleting it; admins still see it regardless.
  final bool active;

  const Variety({
    required this.id,
    required this.name,
    required this.category,
    this.description,
    this.imageUrl,
    this.traits = const [],
    this.stages = const [],
    this.active = true,
  });

  factory Variety.fromMap(Map<String, dynamic> map) {
    return Variety(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      category: map['category'] as String? ?? 'koi',
      description: map['description'] as String?,
      imageUrl: map['image_url'] as String?,
      traits: (map['traits'] as List?)?.cast<String>() ?? const [],
      stages: (map['stages'] as List?)
              ?.map((e) => VarietyStage.fromMap(e as Map<String, dynamic>))
              .toList() ??
          const [],
      active: map['active'] as bool? ?? true,
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

  /// Off hides this guide from customers (RLS-enforced — see migration
  /// 0044) without deleting it; admins still see it regardless.
  final bool active;

  const KnowledgeArticle({
    required this.id,
    required this.title,
    required this.bodyMarkdown,
    this.coverImageUrl,
    this.publishedAt,
    this.active = true,
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
      active: map['active'] as bool? ?? true,
    );
  }
}
