import 'package:mvc_app/services/api_repository.dart';

class PostReaction {
  final String id;
  final String postId;
  final String userId;
  final List<String> emojiReactions;
  final DateTime createdAt;
  final DateTime updatedAt;
  final UserProfile? userProfile; // Optional nested user data

  const PostReaction({
    required this.id,
    required this.postId,
    required this.userId,
    required this.emojiReactions,
    required this.createdAt,
    required this.updatedAt,
    this.userProfile,
  });

  factory PostReaction.fromJson(Map<String, dynamic> json) {
    print("THIS IS JSON $json");
    try {
      return PostReaction(
        id: (json['id'] ?? '') as String,
        postId: (json['post_id'] ?? '') as String,
        userId: (json['user_id'] ?? '') as String,
        emojiReactions: (json['emoji_reactions'] as List<dynamic>?)?.cast< String>() ?? <String>[],
        createdAt: DateTime.tryParse((json['created_at'] ?? '') as String) ?.toUtc() ?? DateTime.now().toUtc(),
        updatedAt: DateTime.tryParse((json['updated_at'] ?? '') as String) ?.toUtc() ?? DateTime.now().toUtc(),
      userProfile: json['user_profiles'] != null ? UserProfile.fromJson(json['user_profiles'] as Map<String, dynamic>) : null,
    );
    } catch (e, stackTrace) {
      print("Error parsing PostReaction: $e");
      print("Stack trace: $stackTrace");
      print("Problematic JSON: $json");
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'post_id': postId,
      'user_id': userId,
      'emoji_reactions': emojiReactions,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (userProfile != null) 'user_profiles': userProfile!.toJson(),
    };
  }
}

class PostReactionSummary {
  final String postId;
  final String? title;
  final String? organizationId;
  final int totalUsersReacted;
  final int totalEmojiReactions;
  final List<String> uniqueEmojisUsed;

  const PostReactionSummary({
    required this.postId,
    this.title,
    this.organizationId,
    required this.totalUsersReacted,
    required this.totalEmojiReactions,
    required this.uniqueEmojisUsed,
  });

  factory PostReactionSummary.fromJson(Map<String, dynamic> json) {
    return PostReactionSummary(
      postId: json['post_id'] as String,
      title: json['title'] as String?,
      organizationId: json['organization_id'] as String?,
      totalUsersReacted: json['total_users_reacted'] as int,
      totalEmojiReactions: json['total_emoji_reactions'] as int,
      uniqueEmojisUsed: List<String>.from(json['unique_emojis_used'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'post_id': postId,
      'title': title,
      'organization_id': organizationId,
      'total_users_reacted': totalUsersReacted,
      'total_emoji_reactions': totalEmojiReactions,
      'unique_emojis_used': uniqueEmojisUsed,
    };
  }
}

class EmojiCount {
  final String postId;
  final String emoji;
  final int count;

  const EmojiCount({
    required this.postId,
    required this.emoji,
    required this.count,
  });

  factory EmojiCount.fromJson(Map<String, dynamic> json) {
    return EmojiCount(
      postId: json['post_id'] as String,
      emoji: json['emoji'] as String,
      count: json['count'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {'post_id': postId, 'emoji': emoji, 'count': count};
  }
}

class CategoryCount {
  final String categoryId;
  final String categoryName;
  final String? categoryDescription;
  final int organizationCount;

  const CategoryCount({
    required this.categoryId,
    required this.categoryName,
    this.categoryDescription,
    required this.organizationCount,
  });

  factory CategoryCount.fromJson(Map<String, dynamic> json) {
    return CategoryCount(
      categoryId: json['category_id'] as String,
      categoryName: json['category_name'] as String,
      categoryDescription: json['category_description'] as String?,
      organizationCount: json['organization_count'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category_id': categoryId,
      'category_name': categoryName,
      'category_description': categoryDescription,
      'organization_count': organizationCount,
    };
  }
}
