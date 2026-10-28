// lib/modules/chat/models/chat_message.dart

import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/utils/timezone_utils.dart';

class ChatMessage {
  final String id;
  final String organizationId;
  final String createdBy;
  final String? title;
  final String? content;
  final String postType;
  final String? fileUrl;
  final String status;
  final int viewCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final UserProfile? author;

  ChatMessage({
    required this.id,
    required this.organizationId,
    required this.createdBy,
    this.title,
    this.content,
    required this.postType,
    this.fileUrl,
    required this.status,
    required this.viewCount,
    required this.createdAt,
    required this.updatedAt,
    this.author,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final String id = json['id'];

    final String organizationId = json['organization_id'];

    final String createdBy = json['created_by'];

    final String title = json['title'] ?? "";

    final String content = json['content'] ?? "";

    final String postType = json['post_type'] ?? "text";

    final String? fileUrl = json['file_url'];

    final String status = json['status'] ?? "active";

    final int viewCount = json['view_count'] ?? 0;

    final DateTime createdAt = json['created_at'] != null
        ? DateTime.parse(json['created_at']).toUtc()
        : DateTime.now().toUtc();

    final DateTime updatedAt = json['updated_at'] != null
        ? DateTime.parse(json['updated_at']).toUtc()
        : DateTime.now().toUtc();

    final UserProfile? author = json['author'] != null
        ? UserProfile.fromJson(json['author'])
        : null;

    return ChatMessage(
      id: id,
      organizationId: organizationId,
      createdBy: createdBy,
      title: title,
      content: content,
      postType: postType,
      fileUrl: fileUrl,
      status: status,
      viewCount: viewCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
      author: author,
    );
  }

  String get displayContent {
    if (content != null && content!.isNotEmpty) {
      return content!;
    } else if (title != null && title!.isNotEmpty) {
      return title!;
    } else if (postType == 'image') {
      return '📷 Image';
    } else if (postType == 'pdf') {
      return '📄 PDF Document';
    }
    return 'Message';
  }

  String get timeDisplay {
    return TimezoneUtils.formatRelativeTime(createdAt);
  }

  @override
  String toString() {
    final authorName = author != null
        ? (author!.fullName ?? author!.email)
        : (createdBy.isNotEmpty
              ? 'Unknown (${createdBy.length > 8 ? createdBy.substring(0, 8) : createdBy}...)'
              : 'Unknown');

    final contentPreview = content != null && content!.isNotEmpty
        ? (content!.length > 50 ? '${content!.substring(0, 50)}...' : content!)
        : (title != null && title!.isNotEmpty
              ? (title!.length > 50 ? '${title!.substring(0, 50)}...' : title!)
              : '[No content]');

    final fileInfo = fileUrl != null
        ? ' | File: ${fileUrl!.split('/').last}'
        : '';

    return 'ChatMessage(id: $id, org: $organizationId, author: $authorName, '
        'type: $postType, status: $status, content: "$contentPreview"$fileInfo, '
        'created: ${createdAt.toIso8601String()})';
  }
}
