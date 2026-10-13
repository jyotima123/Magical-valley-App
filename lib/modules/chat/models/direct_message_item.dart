// lib/modules/chat/models/direct_message_item.dart
import 'package:mvc_app/services/api_repository.dart';

/// Represents an individual direct message within a conversation
class DirectMessageItem {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String messageType;
  final String? fileUrl;
  final bool isRead;
  final DateTime createdAt;
  final DateTime updatedAt;
  final UserProfile? sender;

  DirectMessageItem({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.messageType = 'text',
    this.fileUrl,
    this.isRead = false,
    required this.createdAt,
    required this.updatedAt,
    this.sender,
  });

  factory DirectMessageItem.fromJson(Map<String, dynamic> json) {
    return DirectMessageItem(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String,
      messageType: (json['message_type'] as String?) ?? 'text',
      fileUrl: json['file_url'] as String?,
      isRead: (json['is_read'] as bool?) ?? false,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
      sender: json['user_profiles'] != null
          ? UserProfile.fromJson(json['user_profiles'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': content,
      'message_type': messageType,
      'file_url': fileUrl,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (sender != null) 'user_profiles': sender!.toJson(),
    };
  }
}

