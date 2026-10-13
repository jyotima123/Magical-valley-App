import 'package:mvc_app/modules/chat/models/chat_message.dart';

/// A buyer-to-seller conversation about one Market listing: either a vehicle
/// ([vehicleId]) or a generic Market item ([marketItemId]), never both.
///
/// Named for its first use; since migration 081 the same conversation tables,
/// chat screen and notifications serve every Market category. Render with the
/// `listing*` getters, which work for either kind — the `vehicle*` fields are
/// null for item conversations.
class VehicleInquiryConversation {
  final String id;
  final String? vehicleId;
  final String? marketItemId;
  final String buyerId;
  final String? sellerId;
  final String? organizationId;
  final DateTime createdAt;
  final DateTime updatedAt;

  final int? vehicleYear;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehicleTrim;
  final double? vehiclePrice;
  final String? vehicleImageUrl;

  /// `market_categories.slug` of the listing; `cars_trucks` for vehicles.
  final String? listingCategory;
  final String? _listingTitle;
  final double? _listingPrice;
  final String? _listingImageUrl;
  final bool listingIsSold;

  final String? buyerUsername;
  final String? buyerFullName;
  final String? buyerProfilePictureUrl;

  final String? sellerUsername;
  final String? sellerFullName;
  final String? sellerProfilePictureUrl;

  final ChatMessage? lastMessage;
  final int unreadCount;

  const VehicleInquiryConversation({
    required this.id,
    this.vehicleId,
    this.marketItemId,
    required this.buyerId,
    this.sellerId,
    this.organizationId,
    required this.createdAt,
    required this.updatedAt,
    this.vehicleYear,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleTrim,
    this.vehiclePrice,
    this.vehicleImageUrl,
    this.listingCategory,
    String? listingTitle,
    double? listingPrice,
    String? listingImageUrl,
    this.listingIsSold = false,
    this.buyerUsername,
    this.buyerFullName,
    this.buyerProfilePictureUrl,
    this.sellerUsername,
    this.sellerFullName,
    this.sellerProfilePictureUrl,
    this.lastMessage,
    this.unreadCount = 0,
  })  : _listingTitle = listingTitle,
        _listingPrice = listingPrice,
        _listingImageUrl = listingImageUrl;

  factory VehicleInquiryConversation.fromJson(Map<String, dynamic> json) {
    return VehicleInquiryConversation(
      id: json['id'] as String,
      vehicleId: json['vehicle_id'] as String?,
      marketItemId: json['market_item_id'] as String?,
      buyerId: json['buyer_id'] as String,
      sellerId: json['seller_id'] as String?,
      organizationId: json['organization_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
      vehicleYear: json['vehicle_year'] as int?,
      vehicleMake: json['vehicle_make'] as String?,
      vehicleModel: json['vehicle_model'] as String?,
      vehicleTrim: json['vehicle_trim'] as String?,
      vehiclePrice: json['vehicle_price'] != null
          ? (json['vehicle_price'] as num).toDouble()
          : null,
      vehicleImageUrl: json['vehicle_image_url'] as String?,
      listingCategory: json['listing_category'] as String?,
      listingTitle: json['listing_title'] as String?,
      listingPrice: json['listing_price'] != null
          ? (json['listing_price'] as num).toDouble()
          : null,
      listingImageUrl: json['listing_image_url'] as String?,
      listingIsSold: (json['listing_is_sold'] as bool?) ?? false,
      buyerUsername: json['buyer_username'] as String?,
      buyerFullName: json['buyer_full_name'] as String?,
      buyerProfilePictureUrl: json['buyer_profile_picture_url'] as String?,
      sellerUsername: json['seller_username'] as String?,
      sellerFullName: json['seller_full_name'] as String?,
      sellerProfilePictureUrl: json['seller_profile_picture_url'] as String?,
      lastMessage: json['last_message_id'] != null &&
              json['last_message_content'] != null
          ? ChatMessage(
              id: json['last_message_id'] as String,
              organizationId: '',
              createdBy: '',
              content: json['last_message_content'] as String?,
              postType: 'text',
              status: 'active',
              viewCount: 0,
              createdAt: json['last_message_created_at'] != null
                  ? DateTime.parse(json['last_message_created_at'] as String)
                      .toUtc()
                  : DateTime.now().toUtc(),
              updatedAt: json['last_message_created_at'] != null
                  ? DateTime.parse(json['last_message_created_at'] as String)
                      .toUtc()
                  : DateTime.now().toUtc(),
            )
          : null,
      unreadCount: (json['unread_count'] as int?) ?? 0,
    );
  }

  String get vehicleTitle {
    final parts = <String>[];
    if (vehicleYear != null) parts.add('$vehicleYear');
    if (vehicleMake != null) parts.add(vehicleMake!);
    if (vehicleModel != null) parts.add(vehicleModel!);
    if (vehicleTrim != null && vehicleTrim!.isNotEmpty) {
      parts.add(vehicleTrim!);
    }
    return parts.join(' ');
  }

  /// About a generic Market item rather than a vehicle.
  bool get isMarketItem => marketItemId != null;

  /// What the conversation is about, for either kind of listing. The view
  /// computes it; [vehicleTitle] covers rows from before migration 081.
  String get listingTitle {
    final title = _listingTitle;
    if (title != null && title.isNotEmpty) return title;
    return vehicleTitle;
  }

  double? get listingPrice => _listingPrice ?? vehiclePrice;

  String? get listingImageUrl => _listingImageUrl ?? vehicleImageUrl;

  /// True when this inquiry is answered by a dealership rather than by an
  /// individual. Dealer conversations carry no [sellerId] — every current
  /// admin of [organizationId] shares the inbox.
  bool get isDealerConversation => organizationId != null;

  /// Which side of the conversation [userId] sits on. RLS only ever exposes a
  /// conversation to its buyer, its seller, or an admin of its organization,
  /// so "not the buyer" is enough to mean "answering for the seller" — and it
  /// stays correct for dealer conversations, where [sellerId] is null.
  bool isSellerSide(String? userId) => userId != null && buyerId != userId;

  /// The other party as seen by [userId]. The view already falls back to the
  /// organization for the seller_* columns, so there is no dealer branch here.
  String counterpartyName(String? userId) => isSellerSide(userId)
      ? (buyerFullName ?? buyerUsername ?? 'Buyer')
      : (sellerFullName ?? sellerUsername ?? 'Seller');

  bool get hasUnreadMessages => unreadCount > 0;
}
