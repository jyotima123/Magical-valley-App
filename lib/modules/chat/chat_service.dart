// lib/modules/chat/chat_service.dart
import 'dart:async';
import 'package:mvc_app/modules/channels/models/explore_feed_item.dart';
import 'package:mvc_app/modules/chat/models/chat_channel.dart';
import 'package:mvc_app/modules/chat/models/chat_message.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';
import 'package:mvc_app/modules/chat/models/post_reactions_model.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/api/api_service_factory.dart';
import 'package:mvc_app/services/read_status_service.dart';
import 'package:mvc_app/services/fcm_service.dart';
import 'package:mvc_app/utils/logging_utils.dart';
import 'package:mvc_app/services/amplitude_service.dart';

class ChatService {
  late final ApiRepository _apiRepository;

  // Caches to prevent duplicate requests
  static final Map<String, UserProfile> _userProfileCache = {};
  static final Map<String, Future<UserProfile?>> _pendingProfileRequests = {};
  static Future<List<ChatChannel>>? _pendingChannelsRequest;

  ChatService() {
    final apiService = ApiServiceFactory.createApiService(ApiProvider.supabase);
    _apiRepository = ApiRepository(apiService);
  }

  /// Calculate unread status for a list of channels
  Future<List<ChatChannel>> _calculateUnreadStatus(
    List<ChatChannel> channels,
  ) async {
    final readStatusService = ReadStatusService.instance;
    final List<ChatChannel> updatedChannels = [];

    for (final channel in channels) {
      final hasUnread = await readStatusService.hasUnreadMessages(
        channel.organizationId,
        channel.lastMessage?.createdAt,
      );

      updatedChannels.add(channel.copyWith(hasUnreadMessages: hasUnread));
    }

    return updatedChannels;
  }

  /// Mark a channel as read when user opens it
  /// Note: Badge update should be handled by the caller after channels are refreshed
  Future<void> markChannelAsRead(String organizationId) async {
    final readStatusService = ReadStatusService.instance;
    await readStatusService.markChannelAsRead(organizationId);
    print('🔍 ChatService: Marked channel $organizationId as read');
  }

  /// Update unread status for a specific channel after marking it as read
  Future<ChatChannel> updateChannelUnreadStatus(ChatChannel channel) async {
    final readStatusService = ReadStatusService.instance;
    final hasUnread = await readStatusService.hasUnreadMessages(
      channel.organizationId,
      channel.lastMessage?.createdAt,
    );

    return channel.copyWith(hasUnreadMessages: hasUnread);
  }

  /// Refresh unread status for all channels (useful when returning to chat list)
  Future<List<ChatChannel>> refreshAllChannelsUnreadStatus(
    List<ChatChannel> channels,
  ) async {
    return await _calculateUnreadStatus(channels);
  }

  /// Update notification badge based on unread channel count
  /// This should be called whenever channels are loaded or unread status changes
  Future<void> _updateNotificationBadge(List<ChatChannel> channels) async {
    try {
      // Count channels with unread messages
      final unreadCount = channels
          .where((channel) => channel.hasUnreadMessages)
          .length;

      final fcmService = FCMService.instance;
      await fcmService.updateNotificationBadge(count: unreadCount);
      print(
        '🔍 ChatService: Updated notification badge to $unreadCount (${channels.length} total channels)',
      );
    } catch (e) {
      print('🔍 ChatService: Failed to update notification badge: $e');
    }
  }

  Future<List<ChatChannel>> getFollowedChannelsWithLastMessage(
    String userId,
  ) async {
    try {
      // Get user's followed organization IDs
      final followedResult = await _apiRepository
          .getUserFollowedOrganizationIds(userId);

      if (!followedResult.isSuccess) {
        throw Exception(
          'Failed to get followed organizations: ${followedResult.message}',
        );
      }

      final followedOrgIds = followedResult.data!;

      // If user doesn't follow any organizations, return empty list
      if (followedOrgIds.isEmpty) {
        return [];
      }

      // Get all channels
      final allChannels = await getChannelsWithLastMessage(userId);

      // Filter channels to only include followed organizations
      final followedChannels = allChannels.where((channel) {
        return followedOrgIds.contains(channel.organizationId);
      }).toList();

      // Calculate unread status for followed channels
      final channelsWithUnreadStatus = await _calculateUnreadStatus(
        followedChannels,
      );

      return channelsWithUnreadStatus;
    } catch (e) {
      print('Error getting followed channels: $e');
      rethrow;
    }
  }

  /// Fetch all organizations (acting as chat channels)
  Future<List<ChatChannel>> getChannels() async {
    try {
      print('🔍 ChatService: Starting getChannels request...');

      final result = await _apiRepository.fetchAll<Map<String, dynamic>>(
        'organizations',
        orderBy: 'created_at',
        ascending: false,
      );

      print(
        '🔍 ChatService: getChannels result - Success: ${result.isSuccess}',
      );
      if (!result.isSuccess) {
        print('🔍 ChatService: getChannels error: ${result.error}');
      }

      if (result.isSuccess) {
        final channels = result.data!
            .map((org) => ChatChannel.fromOrganization(org))
            .toList();
        print(
          '🔍 ChatService: getChannels returned ${channels.length} channels',
        );
        return channels;
      } else {
        throw Exception(result.error);
      }
    } catch (e) {
      print('🔍 ChatService: getChannels exception: $e');
      throw Exception('Failed to fetch channels: $e');
    }
  }

  /// Fetch messages (posts) for a specific organization/channel
  /// [organizationId] - The organization/channel ID
  /// [limit] - Maximum number of messages to fetch (default: 50)
  /// [offset] - Number of messages to skip (for pagination)
  /// [beforeTimestamp] - If provided, only fetch messages created before this timestamp
  Future<List<ChatMessage>> getMessages(
    String organizationId, {
    int limit = 50,
    int offset = 0,
    DateTime? beforeTimestamp,
  }) async {
    try {
      // Build filters for regular messages
      final regularFilters = {
        'organization_id': organizationId,
        'status': 'active',
      };

      // If beforeTimestamp is provided, we need to filter messages created before it
      // Note: Supabase doesn't support direct timestamp comparison in filters,
      // so we'll fetch more and filter in memory, or use a different approach
      // For now, we'll use offset-based pagination when beforeTimestamp is null,
      // and fetch all then filter when beforeTimestamp is provided

      List<ChatMessage> regularMessages = [];

      if (beforeTimestamp != null) {
        // Fetch messages before the timestamp using cursor-based pagination
        // We'll fetch messages and filter by timestamp in memory
        // This is more efficient than fetching all messages
        final result = await _apiRepository.fetchAll<Map<String, dynamic>>(
          'posts',
          filters: regularFilters,
          orderBy: 'created_at',
          ascending: false,
          limit: limit * 2, // Fetch more to account for filtering
        );

        if (result.isSuccess) {
          regularMessages = result.data!
              .map((post) => ChatMessage.fromJson(post))
              .where((msg) => msg.createdAt.isBefore(beforeTimestamp))
              .take(limit)
              .toList();

          // If we got fewer than limit messages, there might be more
          // But for now, we'll assume we got all if we got less than requested
        }
      } else {
        // Normal pagination with offset
        final regularResult = await _apiRepository
            .fetchAll<Map<String, dynamic>>(
              'posts',
              filters: regularFilters,
              orderBy: 'created_at',
              ascending: false,
              limit: limit,
              offset: offset,
            );

        if (regularResult.isSuccess) {
          regularMessages = regularResult.data!
              .map((post) => ChatMessage.fromJson(post))
              .toList();
        }
      }

      // Fetch pinned messages (always fetch all pinned messages)
      final pinnedResult = await _apiRepository.fetchAll<Map<String, dynamic>>(
        'posts',
        filters: {'organization_id': organizationId, 'status': 'fixated'},
        orderBy: 'created_at',
        ascending: false,
      );

      if (pinnedResult.isSuccess) {
        final pinnedMessages = pinnedResult.data!
            .map((post) => ChatMessage.fromJson(post))
            .toList();

        print(
          '🔍 ChatService: Regular messages count: ${regularMessages.length}',
        );
        print(
          '🔍 ChatService: Pinned messages count: ${pinnedMessages.length}',
        );

        // Sort regular messages chronologically (oldest first) for proper display
        regularMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

        // Sort pinned messages chronologically (oldest first) for proper display
        pinnedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

        // Combine messages with pinned first, then regular (both in chronological order)
        final allMessages = [...pinnedMessages, ...regularMessages];

        print('🔍 ChatService: Total combined messages: ${allMessages.length}');

        // Populate authors
        await _populateAuthorsOptimized(allMessages);

        return allMessages;
      } else {
        throw Exception('Failed to fetch messages');
      }
    } catch (e) {
      throw Exception('Failed to fetch messages: $e');
    }
  }

  /// Optimized populate author information for messages with batch fetching
  Future<void> _populateAuthorsOptimized(List<ChatMessage> messages) async {
    final authorIds = messages.map((m) => m.createdBy).toSet();
    print(
      '🔍 ChatService: Populating authors for ${authorIds.length} unique users: $authorIds',
    );

    // Batch fetch all user profiles
    await _batchFetchUserProfiles(authorIds.toList());

    // Apply cached profiles to messages
    for (var i = 0; i < messages.length; i++) {
      final authorId = messages[i].createdBy;
      final cachedProfile = _userProfileCache[authorId];

      if (cachedProfile != null) {
        messages[i] = ChatMessage(
          id: messages[i].id,
          organizationId: messages[i].organizationId,
          createdBy: messages[i].createdBy,
          title: messages[i].title,
          content: messages[i].content,
          postType: messages[i].postType,
          fileUrl: messages[i].fileUrl,
          status: messages[i].status,
          viewCount: messages[i].viewCount,
          createdAt: messages[i].createdAt,
          updatedAt: messages[i].updatedAt,
          author: cachedProfile,
        );
      }
    }

    print('🔍 ChatService: Finished populating all authors');
  }

  /// Cached user profile fetching with deduplication
  Future<UserProfile?> getUserProfile(String userId) async {
    // Check cache first
    if (_userProfileCache.containsKey(userId)) {
      print('🔍 ChatService: Using cached profile for $userId');
      return _userProfileCache[userId];
    }

    // Check if request is already in progress
    if (_pendingProfileRequests.containsKey(userId)) {
      print('🔍 ChatService: Waiting for pending profile request for $userId');
      return await _pendingProfileRequests[userId];
    }

    // Start new request
    print('🔍 ChatService: Fetching new profile for $userId');
    final future = _fetchUserProfile(userId);
    _pendingProfileRequests[userId] = future;

    try {
      final profile = await future;
      if (profile != null) {
        _userProfileCache[userId] = profile;
      }
      return profile;
    } finally {
      _pendingProfileRequests.remove(userId);
    }
  }

  /// Batch fetch multiple user profiles efficiently
  Future<void> _batchFetchUserProfiles(List<String> userIds) async {
    final uncachedIds = userIds
        .where(
          (id) =>
              !_userProfileCache.containsKey(id) &&
              !_pendingProfileRequests.containsKey(id),
        )
        .toList();

    if (uncachedIds.isEmpty) {
      print('🔍 ChatService: All ${userIds.length} profiles are cached');
      return;
    }

    print('🔍 ChatService: Batch fetching ${uncachedIds.length} user profiles');

    // Fetch all profiles concurrently
    final futures = uncachedIds.map((id) => getUserProfile(id)).toList();
    await Future.wait(futures);
  }

  /// Internal method to fetch user profile from API
  Future<UserProfile?> _fetchUserProfile(String userId) async {
    try {
      final result = await _apiRepository.getUserProfile(userId);

      if (result.isSuccess) {
        return result.data;
      } else {
        print(
          '🔍 ChatService: Error fetching profile for $userId: ${result.error}',
        );
        return null;
      }
    } catch (e) {
      print('🔍 ChatService: Exception fetching profile for $userId: $e');
      return null;
    }
  }

  /// Get last message for a specific channel (includes pinned/fixated messages)
  Future<List<ChatMessage>> _getLastMessageForChannel(
    String organizationId,
  ) async {
    try {
      debugLogCyan(
        'Fetching last message for organization: $organizationId',
        tag: 'CHAT_SERVICE',
      );

      // Fetch the latest active and latest fixated (pinned) messages separately,
      // then return whichever is more recent so that pinned posts are not skipped.
      final results = await Future.wait([
        _apiRepository.fetchAll<Map<String, dynamic>>(
          'posts',
          filters: {'organization_id': organizationId, 'status': 'active'},
          orderBy: 'created_at',
          ascending: false,
          limit: 1,
        ),
        _apiRepository.fetchAll<Map<String, dynamic>>(
          'posts',
          filters: {'organization_id': organizationId, 'status': 'fixated'},
          orderBy: 'created_at',
          ascending: false,
          limit: 1,
        ),
      ]);

      final activeResult = results[0];
      final fixatedResult = results[1];

      ChatMessage? activeMsg;
      ChatMessage? fixatedMsg;

      if (activeResult.isSuccess && activeResult.data!.isNotEmpty) {
        activeMsg = ChatMessage.fromJson(activeResult.data!.first);
      }
      if (fixatedResult.isSuccess && fixatedResult.data!.isNotEmpty) {
        fixatedMsg = ChatMessage.fromJson(fixatedResult.data!.first);
      }

      ChatMessage? lastMessage;
      if (activeMsg != null && fixatedMsg != null) {
        lastMessage = activeMsg.createdAt.isAfter(fixatedMsg.createdAt)
            ? activeMsg
            : fixatedMsg;
      } else {
        lastMessage = activeMsg ?? fixatedMsg;
      }

      if (lastMessage == null) {
        debugLogYellow(
          'No messages found for organization: $organizationId',
          tag: 'CHAT_SERVICE',
        );
        return [];
      }

      debugLogGreen(
        'Found last message for organization: $organizationId - Message ID: ${lastMessage.id}, Status: ${lastMessage.status}, Created: ${lastMessage.createdAt}',
        tag: 'CHAT_SERVICE',
      );

      return [lastMessage];
    } catch (e) {
      errorLog(
        'Exception fetching last message for organization $organizationId: $e',
        tag: 'CHAT_SERVICE',
        error: e,
      );
      return [];
    }
  }

  /// Send a new message (create a post)
  Future<ChatMessage> sendMessage({
    required String organizationId,
    required String userId,
    String? title,
    String? content,
    String postType = 'text',
    String? fileUrl,
  }) async {
    try {
      print('🔍 ChatService: Sending message to org: $organizationId');

      final postData = {
        'organization_id': organizationId,
        'created_by': userId,
        'title': title?.trim().isEmpty == true ? null : title?.trim(),
        'content': content?.trim().isEmpty == true ? null : content?.trim(),
        'post_type': postType,
        'file_url': fileUrl?.trim().isEmpty == true ? null : fileUrl?.trim(),
        'status': 'active',
      };

      final result = await _apiRepository.create<Map<String, dynamic>>(
        'posts',
        postData,
      );

      print(
        '🔍 ChatService: sendMessage result - Success: ${result.isSuccess}',
      );

      if (result.isSuccess) {
        final message = ChatMessage.fromJson(result.data!);

        // Fetch author details using cached method
        final author = await getUserProfile(userId);
        if (author != null) {
          return ChatMessage(
            id: message.id,
            organizationId: message.organizationId,
            createdBy: message.createdBy,
            title: message.title,
            content: message.content,
            postType: message.postType,
            fileUrl: message.fileUrl,
            status: message.status,
            viewCount: message.viewCount,
            createdAt: message.createdAt,
            updatedAt: message.updatedAt,
            author: author,
          );
        }

        return message;
      } else {
        print('🔍 ChatService: sendMessage error: ${result.error}');
        throw Exception(result.error);
      }
    } catch (e) {
      print('🔍 ChatService: sendMessage exception: $e');
      throw Exception('Failed to send message: $e');
    }
  }

  /// Follow an organization
  Future<bool> followOrganization(String organizationId, String userId) async {
    try {
      print(
        '🔍 ChatService: Following organization $organizationId for user $userId',
      );

      // Create follow relationship
      final followData = {'user_id': userId, 'organization_id': organizationId};

      final result = await _apiRepository.create('user_follows', followData);

      if (result.isSuccess) {
        print(
          '🔍 ChatService: Successfully followed organization $organizationId',
        );
        return true;
      } else {
        print('🔍 ChatService: Failed to follow organization: ${result.error}');
        return false;
      }
    } catch (e) {
      print('🔍 ChatService: Exception following organization: $e');
      return false;
    }
  }

  /// Optimized method with caching and deduplication
  Future<List<ChatChannel>> getChannelsWithLastMessage(String userId) async {
    try {
      logSection('Loading Channels with Last Messages');

      // Validate userId before proceeding
      if (userId.isEmpty) {
        errorLog('Cannot load channels: userId is empty', tag: 'CHAT_SERVICE');
        throw Exception('User ID is required to load channels');
      }

      debugLogCyan(
        'Starting getChannelsWithLastMessage for user: $userId',
        tag: 'CHAT_SERVICE',
      );

      // Fetch all channels
      debugLogBlue('Fetching all channels...', tag: 'CHAT_SERVICE');
      final allChannels = await getChannels();
      infoLog(
        'Loaded ${allChannels.length} total channels',
        tag: 'CHAT_SERVICE',
      );

      // Log channel names
      for (final channel in allChannels) {
        debugLog(
          'Channel: "${channel.name}" (ID: ${channel.id}, OrgID: ${channel.organizationId})',
          tag: 'CHAT_SERVICE',
        );
      }

      // Fetch user's followed organization IDs
      debugLogBlue(
        'Fetching followed organization IDs for user: $userId',
        tag: 'CHAT_SERVICE',
      );
      final followedResult = await _apiRepository
          .getUserFollowedOrganizationIds(userId);

      if (!followedResult.isSuccess) {
        errorLog(
          'Failed to get followed organizations: ${followedResult.error}',
          tag: 'CHAT_SERVICE',
        );
        throw Exception(
          'Failed to get followed organizations: ${followedResult.error}',
        );
      }

      final followedOrgIds = followedResult.data!;
      infoLog(
        'User follows ${followedOrgIds.length} organizations',
        tag: 'CHAT_SERVICE',
      );

      // Set isFollowed based on whether the channel's organization ID is in the followed list
      final channelsWithFollowedStatus = allChannels.map((channel) {
        final isFollowed = followedOrgIds.contains(channel.organizationId);
        if (isFollowed) {
          debugLogGreen(
            'Channel "${channel.name}" is followed',
            tag: 'CHAT_SERVICE',
          );
        }
        return channel.copyWith(isFollowed: isFollowed);
      }).toList();

      // Fetch last messages for all channels
      debugLogBlue(
        'Fetching last messages for all ${channelsWithFollowedStatus.length} channels...',
        tag: 'CHAT_SERVICE',
      );
      final futures = channelsWithFollowedStatus
          .map((channel) => _getLastMessageForChannel(channel.organizationId))
          .toList();

      final lastMessages = await Future.wait(futures);

      // Collect all unique user IDs that need profiles
      final Set<String> userIdsToFetch = {};
      for (final messages in lastMessages) {
        if (messages.isNotEmpty) {
          userIdsToFetch.addAll(messages.map((msg) => msg.createdBy));
        }
      }

      debugLogCyan(
        'Found ${userIdsToFetch.length} unique authors to fetch profiles for',
        tag: 'CHAT_SERVICE',
      );

      // Batch fetch all user profiles (with caching)
      await _batchFetchUserProfiles(userIdsToFetch.toList());

      // Combine results
      debugLogBlue(
        'Combining channels with last messages...',
        tag: 'CHAT_SERVICE',
      );
      final channelsWithMessages = <ChatChannel>[];
      int channelsWithMessagesCount = 0;
      int channelsWithoutMessagesCount = 0;

      for (int i = 0; i < channelsWithFollowedStatus.length; i++) {
        final channel = channelsWithFollowedStatus[i];
        ChatMessage? lastMessage;

        if (lastMessages[i].isNotEmpty) {
          final message = lastMessages[i].first;
          final profile = _userProfileCache[message.createdBy];

          if (profile != null) {
            lastMessage = ChatMessage(
              id: message.id,
              organizationId: message.organizationId,
              createdBy: message.createdBy,
              title: message.title,
              content: message.content,
              postType: message.postType,
              fileUrl: message.fileUrl,
              status: message.status,
              viewCount: message.viewCount,
              createdAt: message.createdAt,
              updatedAt: message.updatedAt,
              author: profile,
            );
            channelsWithMessagesCount++;
            debugLogGreen(
              'Channel "${channel.name}": Attached last message (ID: ${message.id}, Author: ${profile.fullName ?? profile.email})',
              tag: 'CHAT_SERVICE',
            );
          } else {
            // Message exists but author profile is missing
            warningLog(
              'Channel "${channel.name}": Message exists (ID: ${message.id}) but author profile not found for userId: ${message.createdBy}. Message attached without author.',
              tag: 'CHAT_SERVICE',
            );
            lastMessage = message;
            channelsWithMessagesCount++;
          }
        } else {
          // No messages found for this channel
          channelsWithoutMessagesCount++;
          debugLogOrange(
            'Channel "${channel.name}" (OrgID: ${channel.organizationId}): No last message found. Reason: API returned empty list (no active posts with status="active")',
            tag: 'CHAT_SERVICE',
          );
        }

        channelsWithMessages.add(
          channel.copyWith(
            lastMessage: lastMessage,
            unreadCount: 0, // TODO: Implement unread count logic
          ),
        );
      }

      infoLog(
        'Channels processed: ${channelsWithMessages.length} total, $channelsWithMessagesCount with messages, $channelsWithoutMessagesCount without messages',
        tag: 'CHAT_SERVICE',
      );

      // Calculate unread status for all channels
      debugLogBlue(
        'Calculating unread status for all channels...',
        tag: 'CHAT_SERVICE',
      );
      final channelsWithUnreadStatus = await _calculateUnreadStatus(
        channelsWithMessages,
      );

      // Update notification badge based on unread count
      await _updateNotificationBadge(channelsWithUnreadStatus);

      successLog(
        'Completed getChannelsWithLastMessage: ${channelsWithUnreadStatus.length} channels returned',
        tag: 'CHAT_SERVICE',
      );
      logSeparator();

      return channelsWithUnreadStatus;
    } catch (e) {
      errorLog(
        'Exception in getChannelsWithLastMessage: $e',
        tag: 'CHAT_SERVICE',
        error: e,
      );
      throw Exception('Failed to fetch channels with last message: $e');
    }
  }

  /// Clear caches when needed (e.g., on logout or data refresh)
  static void clearCaches() {
    _userProfileCache.clear();
    _pendingProfileRequests.clear();
    _pendingChannelsRequest = null;
    print('🔍 ChatService: Caches cleared');
  }

  /// Clear read status when user logs out
  /// DEPRECATED: This method should NOT be called - read status is now device-based
  /// and should persist across logins. Kept for backward compatibility only.
  @Deprecated('Read status is now device-based and should not be cleared on logout')
  static Future<void> clearReadStatusOnLogout() async {
    final readStatusService = ReadStatusService.instance;
    await readStatusService.clearAllReadStatuses();
    print('🔍 ChatService: Read statuses cleared on logout');
  }

  /// Update notification badge based on unread channel count
  /// This is a static method that can be called from outside the service
  /// NOTE: Uses device-based read status (hasUnreadMessages) not server-side unreadCount
  static Future<void> updateNotificationBadgeFromChannels(
    List<ChatChannel> channels,
  ) async {
    try {
      // Count channels with unread messages based on device-local read status
      // This ensures unread counts persist across logins on the same device
      final unreadCount = channels
          .where((channel) => channel.hasUnreadMessages)
          .length;

      final fcmService = FCMService.instance;
      await fcmService.updateNotificationBadge(count: unreadCount);
      AmplitudeService.instance.logEvent('badge_updated', eventProperties: {
        'count': unreadCount,
        'total_channels': channels.length,
      });
      print(
        '🔍 ChatService: Updated notification badge to $unreadCount (${channels.length} total channels)',
      );
    } catch (e) {
      print('🔍 ChatService: Failed to update notification badge: $e');
    }
  }

  /// Refresh channels and update notification badge
  /// This is a static method that can be called from outside the service
  /// Useful for updating badge after follow/unfollow operations
  static Future<void> refreshChannelsAndUpdateBadge(String userId) async {
    try {
      final chatService = ChatService();
      final channels = await chatService.getChannelsWithLastMessage(userId);
      // Badge is already updated by getChannelsWithLastMessage, but we ensure it here
      await updateNotificationBadgeFromChannels(channels);
      print(
        '🔍 ChatService: Refreshed channels and updated badge for user: $userId',
      );
    } catch (e) {
      print('🔍 ChatService: Failed to refresh channels and update badge: $e');
    }
  }

  /// Invalidate specific user profile cache
  static void invalidateUserProfile(String userId) {
    _userProfileCache.remove(userId);
    _pendingProfileRequests.remove(userId);
    print('🔍 ChatService: Invalidated cache for user $userId');
  }

  /// Get cache statistics for debugging
  static Map<String, dynamic> getCacheStats() {
    return {
      'userProfileCacheSize': _userProfileCache.length,
      'pendingProfileRequests': _pendingProfileRequests.length,
      'hasPendingChannelsRequest': _pendingChannelsRequest != null,
    };
  }

  /// Pin a message (set status to 'fixated')
  Future<bool> pinMessage(String messageId, String userId) async {
    try {
      print('🔍 ChatService: Pinning message: $messageId by user: $userId');

      final result = await _apiRepository.update<Map<String, dynamic>>(
        'posts',
        messageId,
        {'status': 'fixated', 'updated_at': DateTime.now().toIso8601String()},
      );

      print(
        '🔍 ChatService: Pin message result - Success: ${result.isSuccess}',
      );

      if (result.isSuccess) {
        print('🔍 ChatService: Successfully pinned message $messageId');
        return true;
      } else {
        print('🔍 ChatService: Failed to pin message: ${result.error}');
        return false;
      }
    } catch (e) {
      print('🔍 ChatService: Exception pinning message $messageId: $e');
      return false;
    }
  }

  /// Unpin a message (set status to 'active')
  Future<bool> unpinMessage(String messageId, String userId) async {
    try {
      print('🔍 BEFORE API CALL - Unpinning message: $messageId');

      final result = await _apiRepository.update<Map<String, dynamic>>(
        'posts',
        messageId,
        {'status': 'active', 'updated_at': DateTime.now().toIso8601String()},
      );

      print(
        '🔍 API RESPONSE - Success: ${result.isSuccess}, Data: ${result.data}',
      );

      return result.isSuccess;
    } catch (e) {
      print('🔍 API EXCEPTION: $e');
      return false;
    }
  }

  /// Get only pinned messages for a channel
  Future<List<ChatMessage>> getPinnedMessages(String organizationId) async {
    try {
      print('🔍 ChatService: Getting pinned messages for org: $organizationId');

      final result = await _apiRepository.fetchAll<Map<String, dynamic>>(
        'posts',
        filters: {'organization_id': organizationId, 'status': 'fixated'},
        orderBy: 'created_at',
        ascending: false,
      );

      if (result.isSuccess) {
        print(
          '🔍 ChatService: Found ${result.data?.length ?? 0} pinned messages',
        );

        final messages = result.data!
            .map((post) => ChatMessage.fromJson(post))
            .toList();

        // Populate authors for pinned messages
        await _populateAuthorsOptimized(messages);

        return messages;
      } else {
        print('🔍 ChatService: Error getting pinned messages: ${result.error}');
        throw Exception(result.error);
      }
    } catch (e) {
      print('🔍 ChatService: Exception getting pinned messages: $e');
      throw Exception('Failed to fetch pinned messages: $e');
    }
  }

  /// Check if user has permission to pin/unpin messages
  /// You might want to implement proper permission checking based on your business logic
  Future<bool> canUserPinMessages(String userId, String organizationId) async {
    try {
      // For now, let's assume all users can pin messages
      // You can implement proper role-based permissions here
      // For example, checking if user is admin/moderator of the organization

      return true; // TODO: Implement proper permission checking
    } catch (e) {
      print('🔍 ChatService: Exception checking pin permissions: $e');
      return false;
    }
  }

  // ============================================================================
  // REACTION METHODS
  // ============================================================================

  /// Add or update a user's reaction to a message
  Future<bool> addReaction(
    String messageId,
    List<String> emojis,
    String userId,
  ) async {
    try {
      print('🔍 ChatService: Adding reaction to message: $messageId');

      final result = await _apiRepository.upsertPostReaction(messageId, emojis);

      if (result.isSuccess) {
        print('🔍 ChatService: Successfully added reaction');
        return true;
      } else {
        print('🔍 ChatService: Error adding reaction: ${result.error}');
        return false;
      }
    } catch (e) {
      print('🔍 ChatService: Exception adding reaction: $e');
      return false;
    }
  }

  /// Remove a user's reaction from a message
  Future<bool> removeReaction(String messageId, String userId) async {
    try {
      print('🔍 ChatService: Removing reaction from message: $messageId');

      final result = await _apiRepository.removePostReaction(messageId);

      if (result.isSuccess) {
        print('🔍 ChatService: Successfully removed reaction');
        return true;
      } else {
        print('🔍 ChatService: Error removing reaction: ${result.error}');
        return false;
      }
    } catch (e) {
      print('🔍 ChatService: Exception removing reaction: $e');
      return false;
    }
  }

  /// Get all reactions for a message
  Future<List<PostReaction>> getMessageReactions(String messageId) async {
    try {
      print('🔍 ChatService: Getting reactions for message: $messageId');

      final result = await _apiRepository.getPostReactions(messageId);

      if (result.isSuccess) {
        print('🔍 ChatService: Found ${result.data?.length ?? 0} reactions');
        return result.data ?? [];
      } else {
        print('🔍 ChatService: Error getting reactions: ${result.error}');
        return [];
      }
    } catch (e) {
      print('🔍 ChatService: Exception getting reactions: $e');
      return [];
    }
  }

  /// Get the current user's reaction for a message
  Future<PostReaction?> getUserReactionForMessage(String messageId) async {
    try {
      print('🔍 ChatService: Getting user reaction for message: $messageId');

      final result = await _apiRepository.getUserReactionForPost(messageId);

      if (result.isSuccess) {
        print('🔍 ChatService: Found user reaction: ${result.data != null}');
        return result.data;
      } else {
        print('🔍 ChatService: Error getting user reaction: ${result.error}');
        return null;
      }
    } catch (e) {
      print('🔍 ChatService: Exception getting user reaction: $e');
      return null;
    }
  }

  /// Check if current user has reacted to a message
  Future<bool> hasUserReactedToMessage(String messageId) async {
    try {
      final result = await _apiRepository.hasUserReactedToPost(messageId);

      if (result.isSuccess) {
        return result.data ?? false;
      } else {
        print('🔍 ChatService: Error checking user reaction: ${result.error}');
        return false;
      }
    } catch (e) {
      print('🔍 ChatService: Exception checking user reaction: $e');
      return false;
    }
  }

  // ============================================================================
  // EXPLORE FEED METHODS
  // ============================================================================

  /// Get posts for the Explore feed from all organizations.
  /// Posts from followed organizations appear first, then non-followed.
  /// Both groups are sorted by createdAt descending (newest first).
  Future<List<ExploreFeedItem>> getExploreFeedPosts({
    required String userId,
    int limit = 20,
    DateTime? beforeTimestamp,
  }) async {
    try {
      print('🔍 ChatService: Getting explore feed posts for user: $userId');

      // 1. Get user's followed organization IDs
      final followedResult = await _apiRepository.getUserFollowedOrganizationIds(userId);
      final Set<String> followedOrgIds = {};

      if (followedResult.isSuccess && followedResult.data != null) {
        followedOrgIds.addAll(followedResult.data!.cast<String>());
      }
      print('🔍 ChatService: User follows ${followedOrgIds.length} organizations');

      // 2. Fetch posts from ALL organizations (status='active')
      final filters = <String, dynamic>{'status': 'active'};

      // Fetch more posts than needed to account for sorting and filtering
      final fetchLimit = limit * 3;

      final postsResult = await _apiRepository.fetchAll<Map<String, dynamic>>(
        'posts',
        filters: filters,
        orderBy: 'created_at',
        ascending: false,
        limit: fetchLimit,
      );

      if (!postsResult.isSuccess || postsResult.data == null) {
        print('🔍 ChatService: Failed to fetch posts: ${postsResult.error}');
        return [];
      }

      List<ChatMessage> posts = postsResult.data!
          .map((post) => ChatMessage.fromJson(post))
          .toList();

      // 3. Filter by beforeTimestamp if provided (for pagination)
      if (beforeTimestamp != null) {
        posts = posts.where((post) => post.createdAt.isBefore(beforeTimestamp)).toList();
      }

      // Filter out posts older than 90 days
      final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 90));
      posts = posts.where((post) => post.createdAt.isAfter(cutoff)).toList();

      if (posts.isEmpty) {
        print('🔍 ChatService: No posts found');
        return [];
      }

      // 4. Get unique organization IDs and batch fetch organization details
      final Set<String> orgIdsToFetch = posts.map((p) => p.organizationId).toSet();
      print('🔍 ChatService: Fetching ${orgIdsToFetch.length} unique organizations');

      final Map<String, Organization> orgMap = {};

      for (final orgId in orgIdsToFetch) {
        final orgResult = await _apiRepository.fetchById<Map<String, dynamic>>('organizations', orgId);
        if (orgResult.isSuccess && orgResult.data != null) {
          final orgData = Map<String, dynamic>.from(orgResult.data!);
          orgData['is_following'] = followedOrgIds.contains(orgId);
          orgMap[orgId] = Organization.fromJson(orgData);
        }
      }

      // 5. Populate authors for posts
      await _populateAuthorsOptimized(posts);

      // 6. Create ExploreFeedItems with organization context
      final List<ExploreFeedItem> feedItems = [];

      for (final post in posts) {
        final organization = orgMap[post.organizationId];
        if (organization != null) {
          feedItems.add(ExploreFeedItem(
            post: post,
            organization: organization,
            isFollowedOrganization: followedOrgIds.contains(post.organizationId),
          ));
        }
      }

      // 7. Sort: up to 3 latest posts per followed org (newest first),
      //    then all non-followed posts (newest first).
      //    feedItems is already in DB order (newest first overall).
      final followedItems =
          feedItems.where((item) => item.isFollowedOrganization).toList();
      final nonFollowedItems =
          feedItems.where((item) => !item.isFollowedOrganization).toList();

      // Cap at 3 posts per followed org, preserving newest-first order.
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

      // Re-sort capped followed posts by date (different orgs are now mixed).
      cappedFollowed.sort(
        (a, b) => b.post.createdAt.compareTo(a.post.createdAt),
      );

      // Non-followed: newest first.
      nonFollowedItems.sort(
        (a, b) => b.post.createdAt.compareTo(a.post.createdAt),
      );

      final sortedFeedItems = [...cappedFollowed, ...nonFollowedItems];

      // 8. Return limited results
      final result = sortedFeedItems.take(limit).toList();
      print('🔍 ChatService: Returning ${result.length} explore feed items');

      return result;
    } catch (e) {
      print('🔍 ChatService: Exception getting explore feed posts: $e');
      return [];
    }
  }
}
