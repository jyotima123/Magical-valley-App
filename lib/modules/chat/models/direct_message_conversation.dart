// lib/modules/chat/models/direct_message_conversation.dart
import 'package:mvc_app/modules/chat/models/chat_message.dart';

/// Represents a direct message conversation between a user and an organization
class DirectMessageConversation {
  final String id;
  final String userId;
  final String organizationId;
  final String organizationName;
  final String? organizationLogoUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ChatMessage? lastMessage;
  final int unreadCount;
  // User profile information (from view, for admins)
  final String? userUsername;
  final String? userFullName;
  final String? userProfilePictureUrl;

  DirectMessageConversation({
    required this.id,
    required this.userId,
    required this.organizationId,
    required this.organizationName,
    this.organizationLogoUrl,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessage,
    this.unreadCount = 0,
    this.userUsername,
    this.userFullName,
    this.userProfilePictureUrl,
  });

  factory DirectMessageConversation.fromJson(Map<String, dynamic> json) {
    return DirectMessageConversation(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      organizationId: json['organization_id'] as String,
      organizationName: json['organization_name'] as String,
      organizationLogoUrl: json['organization_logo_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
      lastMessage: json['last_message_id'] != null && json['last_message_content'] != null
          ? ChatMessage(
              id: json['last_message_id'] as String,
              organizationId: json['organization_id'] as String,
              createdBy: json['last_message_sender_id'] as String? ?? '',
              content: json['last_message_content'] as String?,
              postType: 'text',
              status: 'active',
              viewCount: 0,
              createdAt: json['last_message_created_at'] != null
                  ? DateTime.parse(json['last_message_created_at'] as String).toUtc()
                  : DateTime.now().toUtc(),
              updatedAt: json['last_message_created_at'] != null
                  ? DateTime.parse(json['last_message_created_at'] as String).toUtc()
                  : DateTime.now().toUtc(),
            )
          : null,
      unreadCount: (json['unread_count'] as int?) ?? 0,
      userUsername: json['user_username'] as String?,
      userFullName: json['user_full_name'] as String?,
      userProfilePictureUrl: json['user_profile_picture_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'organization_id': organizationId,
      'organization_name': organizationName,
      'organization_logo_url': organizationLogoUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'unread_count': unreadCount,
      // Note: ChatMessage doesn't have toJson, so we skip it
    };
  }

  bool get hasUnreadMessages => unreadCount > 0;
}

