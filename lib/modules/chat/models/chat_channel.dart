// lib/modules/chat/models/chat_channel.dart
import 'package:mvc_app/modules/chat/models/chat_message.dart';

class ChatChannel {
  final String id;
  final String name;
  final String? description;
  final String? logoUrl;
  final String organizationId;
  final DateTime createdAt;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final bool isFollowed;
  final bool hasUnreadMessages;

  ChatChannel({
    required this.id,
    required this.name,
    this.description,
    this.logoUrl,
    required this.organizationId,
    required this.createdAt,
    this.lastMessage,
    this.unreadCount = 0,
    this.isFollowed = false, // Default to false
    this.hasUnreadMessages = false, // Default to false
  });

  factory ChatChannel.fromOrganization(Map<String, dynamic> json) {
    return ChatChannel(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      logoUrl: json['logo_url'],
      organizationId: json['id'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String).toUtc()
          : DateTime.now().toUtc(),
      // TODO find a way to mark isFollowed
      // This might come from a separate field or a join with a user_follows table
      isFollowed: json['is_followed'] ?? false,
    );
  }

  // Copy method to help with updates
  ChatChannel copyWith({
    String? id,
    String? name,
    String? description,
    String? logoUrl,
    String? organizationId,
    DateTime? createdAt,
    ChatMessage? lastMessage,
    int? unreadCount,
    bool? isFollowed,
    bool? hasUnreadMessages,
  }) {
    return ChatChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      logoUrl: logoUrl ?? this.logoUrl,
      organizationId: organizationId ?? this.organizationId,
      createdAt: createdAt ?? this.createdAt,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      isFollowed: isFollowed ?? this.isFollowed,
      hasUnreadMessages: hasUnreadMessages ?? this.hasUnreadMessages,
    );
  }
}
