/// A farm service (e.g. "Fish Recovery & Quarantine", "Pond Renovation
/// Boarding") — admin-managed, informational like [Variety]/knowledge
/// articles rather than a purchasable [Product]; customers contact the
/// shop directly to book.
class Service {
  final String id;
  final String name;
  final String? description;
  final List<String> imageUrls;
  final double? price;
  final bool showPrice;
  final String? category;
  final bool active;

  const Service({
    required this.id,
    required this.name,
    this.description,
    this.imageUrls = const [],
    this.price,
    this.showPrice = true,
    this.category,
    this.active = true,
  });

  factory Service.fromMap(Map<String, dynamic> map) {
    return Service(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      description: map['description'] as String?,
      imageUrls: (map['image_urls'] as List?)?.cast<String>() ?? const [],
      price: (map['price'] as num?)?.toDouble(),
      showPrice: map['show_price'] as bool? ?? true,
      category: map['category'] as String?,
      active: map['active'] as bool? ?? true,
    );
  }
}
