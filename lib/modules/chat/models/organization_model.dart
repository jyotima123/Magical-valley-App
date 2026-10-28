// lib/models/organization.dart

class OrgPhoneNumber {
  final String id;
  final String? label;
  final String phoneNumber;

  OrgPhoneNumber({required this.id, this.label, required this.phoneNumber});

  factory OrgPhoneNumber.fromJson(Map<String, dynamic> json) {
    return OrgPhoneNumber(
      id: json['id'] as String,
      label: json['label'] as String?,
      phoneNumber: json['phone_number'] as String,
    );
  }
}

class OrgAddress {
  final String id;
  final String? label;
  final String? street;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;
  final double? latitude;
  final double? longitude;
  final String? mapsUrl;

  OrgAddress({
    required this.id,
    this.label,
    this.street,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    this.latitude,
    this.longitude,
    this.mapsUrl,
  });

  factory OrgAddress.fromJson(Map<String, dynamic> json) {
    return OrgAddress(
      id: json['id'] as String,
      label: json['label'] as String?,
      street: json['street'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      country: json['country'] as String?,
      postalCode: json['postal_code'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      mapsUrl: json['maps_url'] as String?,
    );
  }

  bool get hasGps => latitude != null && longitude != null;

  String get formattedAddress {
    final parts = <String>[
      if (street != null && street!.isNotEmpty) street!,
      if (city != null && city!.isNotEmpty) city!,
      if (state != null && state!.isNotEmpty) state!,
      if (country != null && country!.isNotEmpty) country!,
      if (postalCode != null && postalCode!.isNotEmpty) postalCode!,
    ];
    return parts.join(', ');
  }

  /// Best URL to open this address in the device maps app.
  String get mapsLaunchUrl {
    if (hasGps) return 'https://maps.google.com/?q=$latitude,$longitude';
    if (mapsUrl != null && mapsUrl!.isNotEmpty) return mapsUrl!;
    return 'https://maps.google.com/?q=${Uri.encodeComponent(formattedAddress)}';
  }
}

class OrgPhoto {
  final String id;
  final String photoUrl;
  final String? caption;

  OrgPhoto({required this.id, required this.photoUrl, this.caption});

  factory OrgPhoto.fromJson(Map<String, dynamic> json) {
    return OrgPhoto(
      id: json['id'] as String,
      photoUrl: json['photo_url'] as String,
      caption: json['caption'] as String?,
    );
  }
}

class Organization {
  final String id;
  final String name;
  final String? logoUrl;
  final String? bio;
  final String? websiteUrl;
  final String? mapsUrl;
  final int followerCount;
  final List<String> categoryIds;
  final List<OrgPhoneNumber> phoneNumbers;
  final List<OrgAddress> addresses;
  final List<OrgPhoto> photos;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFollowing;

  Organization({
    required this.id,
    required this.name,
    this.logoUrl,
    this.bio,
    this.websiteUrl,
    this.mapsUrl,
    required this.followerCount,
    required this.categoryIds,
    this.phoneNumbers = const [],
    this.addresses = const [],
    this.photos = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isFollowing = false,
  });

  factory Organization.fromJson(Map<String, dynamic> json) {
    return Organization(
      id: json['id'] as String,
      name: json['name'] as String,
      logoUrl: json['logo_url'] as String?,
      bio: json['bio'] as String?,
      websiteUrl: json['website_url'] as String?,
      mapsUrl: json['maps_url'] as String?,
      followerCount: json['follower_count'] as int? ?? 0,
      categoryIds: List<String>.from(json['category_ids'] ?? []),
      phoneNumbers: (json['phone_numbers'] as List<dynamic>? ?? [])
          .map((e) => OrgPhoneNumber.fromJson(e as Map<String, dynamic>))
          .toList(),
      addresses: (json['addresses'] as List<dynamic>? ?? [])
          .map((e) => OrgAddress.fromJson(e as Map<String, dynamic>))
          .toList(),
      photos: (json['photos'] as List<dynamic>? ?? [])
          .map((e) => OrgPhoto.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
      isFollowing: json['is_following'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'logo_url': logoUrl};
  }

  Map<String, dynamic> toDatabaseJson() {
    return {
      'name': name,
      'logo_url': logoUrl,
      'bio': bio,
      'website_url': websiteUrl,
      'maps_url': mapsUrl,
    };
  }

  Map<String, dynamic> toCreateJson() {
    return {
      'name': name,
      'logo_url': logoUrl,
      'bio': bio,
      'website_url': websiteUrl,
      'maps_url': mapsUrl,
    };
  }

  Organization copyWith({
    String? id,
    String? name,
    String? logoUrl,
    String? bio,
    String? websiteUrl,
    String? mapsUrl,
    int? followerCount,
    List<String>? categoryIds,
    List<OrgPhoneNumber>? phoneNumbers,
    List<OrgAddress>? addresses,
    List<OrgPhoto>? photos,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isFollowing,
  }) {
    return Organization(
      id: id ?? this.id,
      name: name ?? this.name,
      logoUrl: logoUrl ?? this.logoUrl,
      bio: bio ?? this.bio,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      mapsUrl: mapsUrl ?? this.mapsUrl,
      followerCount: followerCount ?? this.followerCount,
      categoryIds: categoryIds ?? this.categoryIds,
      phoneNumbers: phoneNumbers ?? this.phoneNumbers,
      addresses: addresses ?? this.addresses,
      photos: photos ?? this.photos,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }
}
