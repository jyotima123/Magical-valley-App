/// A listing in any Market category except Cars & Trucks — a row of
/// `market_items` (migration 080). Carries only the fields every category
/// shares; vehicles keep their own model, [VehicleListing].
class MarketItem {
  final String id;
  final String category;

  /// Optional second category the item is also listed under.
  final String? secondaryCategory;
  final String title;
  final String? description;

  /// One of [MarketItemCondition.values], or null when it does not apply.
  final String? condition;
  final double price;
  final double? promotion;
  final String? location;
  final List<String> images;
  final List<String> videos;
  final String? contactPhone;
  final bool isSold;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MarketItem({
    required this.id,
    required this.category,
    this.secondaryCategory,
    required this.title,
    this.description,
    this.condition,
    required this.price,
    this.promotion,
    this.location,
    this.images = const [],
    this.videos = const [],
    this.contactPhone,
    this.isSold = false,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MarketItem.fromJson(Map<String, dynamic> json) {
    return MarketItem(
      id: json['id'] as String,
      category: json['category'] as String,
      secondaryCategory: json['secondary_category'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      condition: json['condition'] as String?,
      price: (json['price'] as num).toDouble(),
      promotion: json['promotion'] != null
          ? (json['promotion'] as num).toDouble()
          : null,
      location: json['location'] as String?,
      images: _splitComma(json['images'] as String?),
      videos: _splitComma(json['videos'] as String?),
      contactPhone: json['contact_phone'] as String?,
      isSold: (json['is_sold'] as bool?) ?? false,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Stored comma-separated, as in `vehicle_listings`.
  static List<String> _splitComma(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  bool isInCategory(String slug) =>
      category == slug || secondaryCategory == slug;

  bool isOwnedBy(String? userId) => userId != null && userId == createdBy;

  /// Unlike a dealer car, where a missing price means "ask", an item listed at
  /// zero is a giveaway — common in Pets & Animals.
  bool get isFree => price == 0;

  bool get hasPromo => promotion != null && promotion! > 0;

  String get displayPrice => isFree ? 'Free' : formatPrice(price);

  String get displayPromoPrice => hasPromo ? formatPrice(promotion!) : '';

  String? get conditionLabel =>
      condition != null ? MarketItemCondition.label(condition!) : null;

  String? get firstImageUrl => images.isNotEmpty ? images.first : null;

  /// Whole dollars without cents, anything else to the cent: `$1,200`, `$4.99`.
  static String formatPrice(double value) {
    final cents = (value * 100).round();
    final dollars = _groupThousands(cents ~/ 100);
    final remainder = cents % 100;
    return remainder == 0
        ? '\$$dollars'
        : '\$$dollars.${remainder.toString().padLeft(2, '0')}';
  }

  static String _groupThousands(int n) => n.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
}

/// The values `market_items_condition_check` accepts, in the order they are
/// offered to a seller.
class MarketItemCondition {
  MarketItemCondition._();

  static const List<String> values = [
    'new',
    'like_new',
    'good',
    'fair',
    'for_parts',
  ];

  static String label(String value) => switch (value) {
    'new' => 'New',
    'like_new' => 'Used – Like New',
    'good' => 'Used – Good',
    'fair' => 'Used – Fair',
    'for_parts' => 'For Parts',
    _ => value,
  };
}
