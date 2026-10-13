class AdModel {
  final String id;
  final String title;
  final String? description;
  final String imageUrl;
  final String linkUrl;
  final DateTime startDate;
  final DateTime endDate;
  final String? adSizeId;
  final int? width;
  final int? height;

  AdModel({
    required this.id,
    required this.title,
    this.description,
    required this.imageUrl,
    required this.linkUrl,
    required this.startDate,
    required this.endDate,
    this.adSizeId,
    this.width,
    this.height,
  });

  factory AdModel.fromJson(Map<String, dynamic> json) {
    return AdModel(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String,
      linkUrl: json['link_url'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      adSizeId: json['ad_size_id'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
    );
  }

  bool get isActive {
    final now = DateTime.now();
    return now.isAfter(startDate) && now.isBefore(endDate);
  }
}
