// lib/modules/channels/models/explore_feed_item.dart

import 'package:mvc_app/modules/chat/models/chat_message.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';

/// Represents a single item in the Explore feed.
/// Contains a post along with its organization context and follow status.
class ExploreFeedItem {
  final ChatMessage post;
  final Organization organization;
  final bool isFollowedOrganization;

  ExploreFeedItem({
    required this.post,
    required this.organization,
    required this.isFollowedOrganization,
  });

  ExploreFeedItem copyWith({
    ChatMessage? post,
    Organization? organization,
    bool? isFollowedOrganization,
  }) {
    return ExploreFeedItem(
      post: post ?? this.post,
      organization: organization ?? this.organization,
      isFollowedOrganization: isFollowedOrganization ?? this.isFollowedOrganization,
    );
  }

  @override
  String toString() {
    return 'ExploreFeedItem(postId: ${post.id}, orgId: ${organization.id}, orgName: ${organization.name}, isFollowed: $isFollowedOrganization)';
  }
}
