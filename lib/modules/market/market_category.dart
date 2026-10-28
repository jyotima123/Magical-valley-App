import 'package:flutter/material.dart';

/// The one category not stored in `market_items`: it opens the Cars screen,
/// backed by `vehicle_listings`. The slug is reserved by migration 080 and kept
/// through the rename to "Cars" in 083, because SQL and shipped builds both
/// depend on this literal.
const String kCarsCategory = 'cars_trucks';

/// A row of `market_categories`. Which categories exist, what they are called
/// and their order is data, so a category can be renamed, reordered or hidden
/// without a release; only its icon is chosen here.
class MarketCategory {
  final String slug;
  final String name;
  final int sortOrder;

  const MarketCategory({
    required this.slug,
    required this.name,
    this.sortOrder = 0,
  });

  factory MarketCategory.fromJson(Map<String, dynamic> json) {
    return MarketCategory(
      slug: json['slug'] as String,
      name: json['name'] as String,
      sortOrder: (json['sort_order'] as int?) ?? 0,
    );
  }

  bool get isCars => slug == kCarsCategory;

  IconData get icon => iconFor(slug);

  String get photo => photoFor(slug);

  /// The stock photo behind the category's tile on the Market screen. Bundled
  /// rather than fetched, so the grid paints complete on the first frame and
  /// offline. A category the app does not know yet gets the general one.
  static String photoFor(String? slug) {
    const known = {
      kCarsCategory: 'cars',
      'recreational_vehicles': 'recreational_vehicles',
      'home_garden': 'home_garden',
      'industrial': 'industrial',
      'ag_livestock': 'ag_livestock',
      'sports_fitness': 'sports_fitness',
      'clothing': 'clothing',
      'electronics': 'electronics',
      'furniture': 'furniture',
      'pets': 'pets',
      'musical_instruments': 'musical_instruments',
      'auto_parts': 'auto_parts',
      'outdoors': 'outdoors',
    };
    return 'assets/market_categories/${known[slug] ?? 'general'}.jpg';
  }

  /// A category added later through SQL still renders, with a generic icon,
  /// until the app learns a better one.
  ///
  /// Migration 083 renamed most of these slugs along with their names; the old
  /// spellings are gone from the database, so only the current ones are listed.
  static IconData iconFor(String? slug) => switch (slug) {
    kCarsCategory => Icons.directions_car,
    'recreational_vehicles' => Icons.two_wheeler,
    'home_garden' => Icons.yard_outlined,
    'industrial' => Icons.handyman_outlined,
    'ag_livestock' => Icons.agriculture,
    'sports_fitness' => Icons.sports_basketball_outlined,
    'clothing' => Icons.checkroom,
    'electronics' => Icons.devices_other,
    'furniture' => Icons.chair_outlined,
    'pets' => Icons.pets,
    'musical_instruments' => Icons.music_note_outlined,
    'auto_parts' => Icons.build_outlined,
    'outdoors' => Icons.forest_outlined,
    'general' => Icons.category_outlined,
    _ => Icons.storefront_outlined,
  };
}
