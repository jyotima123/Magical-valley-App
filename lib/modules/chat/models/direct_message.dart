// lib/modules/chat/models/direct_message.dart
import 'package:mvc_app/modules/chat/models/chat_message.dart';

/// Represents a direct message conversation with a channel/company
class DirectMessage {
  final String id;
  final String channelId; // The channel/company ID
  final String channelName;
  final String? channelLogoUrl;
  final DateTime createdAt;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final bool hasUnreadMessages;

  DirectMessage({
    required this.id,
    required this.channelId,
    required this.channelName,
    this.channelLogoUrl,
    required this.createdAt,
    this.lastMessage,
    this.unreadCount = 0,
    this.hasUnreadMessages = false,
  });

  // Copy method to help with updates
  DirectMessage copyWith({
    String? id,
    String? channelId,
    String? channelName,
    String? channelLogoUrl,
    DateTime? createdAt,
    ChatMessage? lastMessage,
    int? unreadCount,
    bool? hasUnreadMessages,
  }) {
    return DirectMessage(
      id: id ?? this.id,
      channelId: channelId ?? this.channelId,
      channelName: channelName ?? this.channelName,
      channelLogoUrl: channelLogoUrl ?? this.channelLogoUrl,
      createdAt: createdAt ?? this.createdAt,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      hasUnreadMessages: hasUnreadMessages ?? this.hasUnreadMessages,
    );
  }
}

