/// The one source key that is not a dealership: listings a user posted in-app.
/// Everything else is a row in `dealer_sources`, and the set of them is data,
/// not code — see migration 078.
const String kCommunitySource = 'community';

class VehicleListing {
  final String id;
  final String stock;
  final String? vin;
  final int year;
  final String make;
  final String model;
  final String? trim;
  final String? body;
  final String status;
  final int mileage;
  final String? color;
  final String? interior;
  final String? transmission;
  final String? speed;
  final String? engineType;
  final String? fuel;
  final String? doors;
  final double price;
  final double? promotion;
  final String? description;
  final String? location;
  final List<String> images;
  final List<String> videos;
  final String? engineOptions;
  final String? packageOptions;
  final String? transmissionOptions;
  final String? addonsDescription;
  final String? contactPhone;
  final bool isSold;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Registry key from `dealer_sources.source`: `community`, or a provider's
  /// per-dealership key such as `liftkit` or `vauto:48213`.
  final String source;

  /// The provider's own identifier for this vehicle, namespaced by source
  /// (`vauto:48213:PG205293`). Distinct from [id], which for a stored row is our
  /// uuid — messaging keys on this, so conflating the two would mirror a second
  /// copy of a vehicle we already have.
  final String? externalId;

  /// Vehicle detail page on the dealer's own site (LiftKit listings only).
  final String? vdpUrl;
  final String? drivetrain;
  final List<String> features;

  const VehicleListing({
    required this.id,
    required this.stock,
    this.vin,
    required this.year,
    required this.make,
    required this.model,
    this.trim,
    this.body,
    required this.status,
    required this.mileage,
    this.color,
    this.interior,
    this.transmission,
    this.speed,
    this.engineType,
    this.fuel,
    this.doors,
    required this.price,
    this.promotion,
    this.description,
    this.location,
    required this.images,
    required this.videos,
    this.engineOptions,
    this.packageOptions,
    this.transmissionOptions,
    this.addonsDescription,
    this.contactPhone,
    this.isSold = false,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.source = kCommunitySource,
    this.externalId,
    this.vdpUrl,
    this.drivetrain,
    this.features = const [],
  });

  /// Listed in-app by a user: editable by its creator, and answered by that
  /// person rather than by a dealership.
  bool get isCommunity => source == kCommunitySource;

  /// Dealer inventory, whether pulled live or ingested from a delivered file.
  /// Read-only to us, owned by the dealership, and messaged about through
  /// `create_or_get_dealer_vehicle_inquiry` rather than the personal path.
  bool get isFromDealerFeed => !isCommunity;

  /// Value stored in `vehicle_listings.source` / `dealer_sources.source`, used
  /// to resolve which organization answers messages about this vehicle.
  String get dealerSourceKey => source;

  factory VehicleListing.fromJson(Map<String, dynamic> json) {
    return VehicleListing(
      id: json['id'] as String,
      stock: json['stock'] as String,
      vin: json['vin'] as String?,
      year: json['year'] as int,
      make: json['make'] as String,
      model: json['model'] as String,
      trim: json['trim'] as String?,
      body: json['body'] as String?,
      status: json['status'] as String? ?? 'New',
      mileage: json['mileage'] as int? ?? 0,
      color: json['color'] as String?,
      interior: json['interior'] as String?,
      transmission: json['transmission'] as String?,
      speed: json['speed'] as String?,
      engineType: json['engine_type'] as String?,
      fuel: json['fuel'] as String?,
      doors: json['doors'] as String?,
      price: (json['price'] as num).toDouble(),
      promotion: json['promotion'] != null
          ? (json['promotion'] as num).toDouble()
          : null,
      description: json['description'] as String?,
      location: json['location'] as String?,
      images: _splitComma(json['images'] as String?),
      videos: _splitComma(json['videos'] as String?),
      engineOptions: json['engine_options'] as String?,
      packageOptions: json['package_options'] as String?,
      transmissionOptions: json['transmission_options'] as String?,
      addonsDescription: json['addons_description'] as String?,
      contactPhone: json['contact_phone'] as String?,
      isSold: (json['is_sold'] as bool?) ?? false,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      source: json['source'] as String? ?? kCommunitySource,
      externalId: json['external_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'stock': stock,
        'vin': vin,
        'year': year,
        'make': make,
        'model': model,
        'trim': trim,
        'body': body,
        'status': status,
        'mileage': mileage,
        'color': color,
        'interior': interior,
        'transmission': transmission,
        'speed': speed,
        'engine_type': engineType,
        'fuel': fuel,
        'doors': doors,
        'price': price,
        'promotion': promotion,
        'description': description,
        'location': location,
        'images': images.isEmpty ? null : images.join(','),
        'videos': videos.isEmpty ? null : videos.join(','),
        'engine_options': engineOptions,
        'package_options': packageOptions,
        'transmission_options': transmissionOptions,
        'addons_description': addonsDescription,
        'contact_phone': contactPhone,
        'is_sold': isSold,
      };

  static List<String> _splitComma(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  String get displayTitle =>
      '$year $make $model${trim != null && trim!.isNotEmpty ? ' $trim' : ''}';

  /// Dealer feeds routinely omit the price on fresh trade-ins, so a zero price
  /// means "ask", not "free".
  bool get hasPrice => price > 0;

  String get displayPrice =>
      hasPrice ? '\$${_formatNumber(price.round())}' : 'Call for price';

  String get displayPromoPrice =>
      promotion != null ? '\$${_formatNumber(promotion!.round())}' : '';

  String get displayMileage => '${_formatNumber(mileage)} mi';

  String? get firstImageUrl => images.isNotEmpty ? images.first : null;

  static String _formatNumber(int n) => n
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}
