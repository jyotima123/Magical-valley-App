// lib/modules/channels/explore_feed_bloc.dart

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/modules/channels/models/explore_feed_item.dart';
import 'package:mvc_app/modules/chat/chat_service.dart';
import 'package:mvc_app/modules/chat/models/chat_message.dart';
import 'package:mvc_app/modules/chat/models/post_reactions_model.dart';

// ============================================================================
// EVENTS
// ============================================================================

abstract class ExploreFeedEvent {}

/// Initial load of the explore feed
class LoadExploreFeed extends ExploreFeedEvent {
  final String userId;

  LoadExploreFeed({required this.userId});
}

/// Load more posts for pagination (infinite scroll)
class LoadMoreExploreFeed extends ExploreFeedEvent {
  final String userId;

  LoadMoreExploreFeed({required this.userId});
}

/// Pull-to-refresh the feed
class RefreshExploreFeed extends ExploreFeedEvent {
  final String userId;

  RefreshExploreFeed({required this.userId});
}

/// Update follow status for an organization in the feed
class UpdateOrganizationFollowStatus extends ExploreFeedEvent {
  final String organizationId;
  final bool isFollowing;

  UpdateOrganizationFollowStatus({
    required this.organizationId,
    required this.isFollowing,
  });
}

/// Add or update a reaction on a post
class AddExploreFeedReactionEvent extends ExploreFeedEvent {
  final String messageId;
  final List<String> emojis;
  final String userId;

  AddExploreFeedReactionEvent({
    required this.messageId,
    required this.emojis,
    required this.userId,
  });
}

/// Remove a reaction from a post
class RemoveExploreFeedReactionEvent extends ExploreFeedEvent {
  final String messageId;
  final String userId;

  RemoveExploreFeedReactionEvent({required this.messageId, required this.userId});
}

/// Load reactions for a specific post
class LoadExploreFeedPostReactionsEvent extends ExploreFeedEvent {
  final String messageId;

  LoadExploreFeedPostReactionsEvent({required this.messageId});
}

/// Update a post's content in the state (after a successful API edit)
class UpdateExploreFeedPostEvent extends ExploreFeedEvent {
  final String messageId;
  final String? title;
  final String? content;

  UpdateExploreFeedPostEvent({
    required this.messageId,
    this.title,
    this.content,
  });
}

/// Remove a post from the state (after a successful API delete)
class RemoveExploreFeedPostEvent extends ExploreFeedEvent {
  final String messageId;

  RemoveExploreFeedPostEvent({required this.messageId});
}

// ============================================================================
// STATES
// ============================================================================

abstract class ExploreFeedState {}

class ExploreFeedInitial extends ExploreFeedState {}

class ExploreFeedLoading extends ExploreFeedState {}

class ExploreFeedLoaded extends ExploreFeedState {
  final List<ExploreFeedItem> posts;
  final bool hasMorePosts;
  final DateTime? oldestTimestamp;
  final bool isLoadingMore;
  final Map<String, List<PostReaction>> messageReactions;

  ExploreFeedLoaded({
    required this.posts,
    this.hasMorePosts = true,
    this.oldestTimestamp,
    this.isLoadingMore = false,
    this.messageReactions = const {},
  });

  ExploreFeedLoaded copyWith({
    List<ExploreFeedItem>? posts,
    bool? hasMorePosts,
    DateTime? oldestTimestamp,
    bool? isLoadingMore,
    Map<String, List<PostReaction>>? messageReactions,
  }) {
    return ExploreFeedLoaded(
      posts: posts ?? this.posts,
      hasMorePosts: hasMorePosts ?? this.hasMorePosts,
      oldestTimestamp: oldestTimestamp ?? this.oldestTimestamp,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      messageReactions: messageReactions ?? this.messageReactions,
    );
  }
}

class ExploreFeedError extends ExploreFeedState {
  final String message;

  ExploreFeedError({required this.message});
}

// ============================================================================
// BLOC
// ============================================================================

class ExploreFeedBloc extends Bloc<ExploreFeedEvent, ExploreFeedState> {
  final ChatService _chatService = ChatService();
  static const int _pageSize = 20;

  ExploreFeedBloc() : super(ExploreFeedInitial()) {
    on<LoadExploreFeed>(_onLoadExploreFeed);
    on<LoadMoreExploreFeed>(_onLoadMoreExploreFeed);
    on<RefreshExploreFeed>(_onRefreshExploreFeed);
    on<UpdateOrganizationFollowStatus>(_onUpdateOrganizationFollowStatus);
    on<AddExploreFeedReactionEvent>(_onAddReaction);
    on<RemoveExploreFeedReactionEvent>(_onRemoveReaction);
    on<LoadExploreFeedPostReactionsEvent>(_onLoadPostReactions);
    on<UpdateExploreFeedPostEvent>(_onUpdatePost);
    on<RemoveExploreFeedPostEvent>(_onRemovePost);
  }

  Future<void> _onLoadExploreFeed(
    LoadExploreFeed event,
    Emitter<ExploreFeedState> emit,
  ) async {
    print('ExploreFeedBloc: Loading explore feed for user: ${event.userId}');
    emit(ExploreFeedLoading());

    try {
      final posts = await _chatService.getExploreFeedPosts(
        userId: event.userId,
        limit: _pageSize,
      );

      final oldestTimestamp = posts.isNotEmpty ? posts.last.post.createdAt : null;

      emit(ExploreFeedLoaded(
        posts: posts,
        hasMorePosts: posts.length >= _pageSize,
        oldestTimestamp: oldestTimestamp,
      ));
      print('ExploreFeedBloc: Loaded ${posts.length} posts');
    } catch (e) {
      print('ExploreFeedBloc: Error loading feed: $e');
      emit(ExploreFeedError(message: 'Failed to load explore feed: $e'));
    }
  }

  Future<void> _onLoadMoreExploreFeed(
    LoadMoreExploreFeed event,
    Emitter<ExploreFeedState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ExploreFeedLoaded) return;
    if (currentState.isLoadingMore || !currentState.hasMorePosts) return;

    print('ExploreFeedBloc: Loading more posts...');
    emit(currentState.copyWith(isLoadingMore: true));

    try {
      final morePosts = await _chatService.getExploreFeedPosts(
        userId: event.userId,
        limit: _pageSize,
        beforeTimestamp: currentState.oldestTimestamp,
      );

      if (morePosts.isEmpty) {
        emit(currentState.copyWith(
          hasMorePosts: false,
          isLoadingMore: false,
        ));
        return;
      }

      final allPosts = [...currentState.posts, ...morePosts];
      final oldestTimestamp = morePosts.last.post.createdAt;

      emit(ExploreFeedLoaded(
        posts: allPosts,
        hasMorePosts: morePosts.length >= _pageSize,
        oldestTimestamp: oldestTimestamp,
        isLoadingMore: false,
      ));
      print('ExploreFeedBloc: Loaded ${morePosts.length} more posts, total: ${allPosts.length}');
    } catch (e) {
      print('ExploreFeedBloc: Error loading more: $e');
      emit(currentState.copyWith(isLoadingMore: false));
    }
  }

  Future<void> _onRefreshExploreFeed(
    RefreshExploreFeed event,
    Emitter<ExploreFeedState> emit,
  ) async {
    print('ExploreFeedBloc: Refreshing explore feed');

    try {
      final posts = await _chatService.getExploreFeedPosts(
        userId: event.userId,
        limit: _pageSize,
      );

      final oldestTimestamp = posts.isNotEmpty ? posts.last.post.createdAt : null;

      emit(ExploreFeedLoaded(
        posts: posts,
        hasMorePosts: posts.length >= _pageSize,
        oldestTimestamp: oldestTimestamp,
      ));
      print('ExploreFeedBloc: Refreshed with ${posts.length} posts');
    } catch (e) {
      print('ExploreFeedBloc: Error refreshing: $e');
      // Keep old state on refresh error, just show a message
      if (state is ExploreFeedLoaded) {
        // Stay in loaded state but could show a snackbar
      } else {
        emit(ExploreFeedError(message: 'Failed to refresh explore feed: $e'));
      }
    }
  }

  Future<void> _onUpdateOrganizationFollowStatus(
    UpdateOrganizationFollowStatus event,
    Emitter<ExploreFeedState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ExploreFeedLoaded) return;

    // Update the follow status for all posts from this organization
    final updatedPosts = currentState.posts.map((item) {
      if (item.organization.id == event.organizationId) {
        return item.copyWith(
          isFollowedOrganization: event.isFollowing,
          organization: item.organization.copyWith(isFollowing: event.isFollowing),
        );
      }
      return item;
    }).toList();

    // Re-sort after follow status change:
    // up to 3 latest posts per followed org, then non-followed newest first.
    final followedItems =
        updatedPosts.where((item) => item.isFollowedOrganization).toList()
          ..sort((a, b) => b.post.createdAt.compareTo(a.post.createdAt));
    final nonFollowedItems =
        updatedPosts.where((item) => !item.isFollowedOrganization).toList()
          ..sort((a, b) => b.post.createdAt.compareTo(a.post.createdAt));

    final Map<String, int> orgPostCount = {};
    final List<ExploreFeedItem> cappedFollowed = [];
    for (final item in followedItems) {
      final orgId = item.organization.id;
      final count = orgPostCount[orgId] ?? 0;
      if (count < 3) {
        cappedFollowed.add(item);
        orgPostCount[orgId] = count + 1;
      }
    }
    cappedFollowed.sort((a, b) => b.post.createdAt.compareTo(a.post.createdAt));

    emit(currentState.copyWith(posts: [...cappedFollowed, ...nonFollowedItems]));
  }

  Future<void> _onAddReaction(
    AddExploreFeedReactionEvent event,
    Emitter<ExploreFeedState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ExploreFeedLoaded) return;

    try {
      final success = await _chatService.addReaction(
        event.messageId,
        event.emojis,
        event.userId,
      );
      if (success) {
        add(LoadExploreFeedPostReactionsEvent(messageId: event.messageId));
      }
    } catch (e) {
      print('ExploreFeedBloc: Error adding reaction: $e');
    }
  }

  Future<void> _onRemoveReaction(
    RemoveExploreFeedReactionEvent event,
    Emitter<ExploreFeedState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ExploreFeedLoaded) return;

    try {
      final success = await _chatService.removeReaction(
        event.messageId,
        event.userId,
      );
      if (success) {
        final updatedReactions = Map<String, List<PostReaction>>.from(
          currentState.messageReactions,
        );
        updatedReactions.remove(event.messageId);
        emit(currentState.copyWith(messageReactions: updatedReactions));
      }
    } catch (e) {
      print('ExploreFeedBloc: Error removing reaction: $e');
    }
  }

  Future<void> _onLoadPostReactions(
    LoadExploreFeedPostReactionsEvent event,
    Emitter<ExploreFeedState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ExploreFeedLoaded) return;

    try {
      final reactions = await _chatService.getMessageReactions(event.messageId);
      final updatedReactions = Map<String, List<PostReaction>>.from(
        currentState.messageReactions,
      );
      updatedReactions[event.messageId] = reactions;
      emit(currentState.copyWith(messageReactions: updatedReactions));
    } catch (e) {
      print('ExploreFeedBloc: Error loading reactions: $e');
    }
  }

  Future<void> _onUpdatePost(
    UpdateExploreFeedPostEvent event,
    Emitter<ExploreFeedState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ExploreFeedLoaded) return;

    final updatedPosts = currentState.posts.map((item) {
      if (item.post.id != event.messageId) return item;
      final p = item.post;
      final updatedPost = ChatMessage(
        id: p.id,
        organizationId: p.organizationId,
        createdBy: p.createdBy,
        title: event.title ?? p.title,
        content: event.content ?? p.content,
        postType: p.postType,
        fileUrl: p.fileUrl,
        status: p.status,
        viewCount: p.viewCount,
        createdAt: p.createdAt,
        updatedAt: DateTime.now().toUtc(),
        author: p.author,
      );
      return item.copyWith(post: updatedPost);
    }).toList();

    emit(currentState.copyWith(posts: updatedPosts));
  }

  Future<void> _onRemovePost(
    RemoveExploreFeedPostEvent event,
    Emitter<ExploreFeedState> emit,
  ) async {
    final currentState = state;
    if (currentState is! ExploreFeedLoaded) return;

    final updatedPosts = currentState.posts
        .where((item) => item.post.id != event.messageId)
        .toList();

    emit(currentState.copyWith(posts: updatedPosts));
  }
}
