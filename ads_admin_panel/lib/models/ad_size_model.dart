import 'package:equatable/equatable.dart';

class AdSizeModel extends Equatable {
  final String id;
  final String name;
  final int width;
  final int height;
  final bool isActive;
  final int displayOrder;
  final double currentPrice; // Price in cents
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AdSizeModel({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    this.isActive = true,
    this.displayOrder = 0,
    this.currentPrice = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory AdSizeModel.fromJson(Map<String, dynamic> json) {
    return AdSizeModel(
      id: json['id'] as String,
      name: json['name'] as String,
      width: json['width'] as int,
      height: json['height'] as int,
      isActive: json['is_active'] as bool? ?? true,
      displayOrder: json['display_order'] as int? ?? 0,
      currentPrice: json['current_price'] as double? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'width': width,
      'height': height,
      'is_active': isActive,
      'display_order': displayOrder,
      'current_price': currentPrice,
    };
  }

  String get displaySize => '$width x $height';

  String get displayNameWithSize => '$name ($displaySize)';

  double get aspectRatio => width / height;

  String get priceDisplay => '\$${(currentPrice / 100).toStringAsFixed(2)}/month';

  @override
  List<Object?> get props => [
        id,
        name,
        width,
        height,
        isActive,
        displayOrder,
        currentPrice,
        createdAt,
        updatedAt,
      ];
}
