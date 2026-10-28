// lib/modules/chat/chat_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/chat/models/chat_channel.dart';
import 'package:mvc_app/modules/chat/models/chat_message.dart';
import 'package:mvc_app/modules/chat/models/post_reactions_model.dart';
import 'package:mvc_app/modules/chat/chat_service.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/utils/logging_utils.dart';
import 'package:mvc_app/flavour_config.dart';

/// MVC official channel organization IDs - always shown in chat list
const String _mvcOrganizationIdQa = '938562d2-0a56-41bb-9c55-520390f30aa4';
const String _mvcOrganizationIdProduction = '2a2ceec6-aa41-4f0b-8954-b973fed287ac';

String get _mvcOrganizationId =>
    FlavorConfig.isProduction ? _mvcOrganizationIdProduction : _mvcOrganizationIdQa;

// Events
abstract class ChatEvent {}

class LoadChannelsEvent extends ChatEvent {}

class SelectChannelEvent extends ChatEvent {
  final ChatChannel channel;
  SelectChannelEvent(this.channel);
}

class SelectChannelByOrganizationIdEvent extends ChatEvent {
  final String organizationId;
  SelectChannelByOrganizationIdEvent(this.organizationId);
}

class FollowAndSelectOrganizationEvent extends ChatEvent {
  final String organizationId;
  FollowAndSelectOrganizationEvent(this.organizationId);
}

class LoadMessagesEvent extends ChatEvent {
  final String channelId;
  final String userId;
  LoadMessagesEvent(this.channelId, this.userId);
}

class LoadMoreMessagesEvent extends ChatEvent {
  final String channelId;
  final String userId;
  final DateTime beforeTimestamp;
  LoadMoreMessagesEvent(this.channelId, this.userId, this.beforeTimestamp);
}

class SendMessageEvent extends ChatEvent {
  final String organizationId;
  final String userId;
  final String content;
  final String? title;
  final String postType;
  final String? fileUrl;

  SendMessageEvent({
    required this.organizationId,
    required this.userId,
    required this.content,
    this.title,
    this.postType = 'text',
    this.fileUrl,
  });
}

class RefreshChannelsEvent extends ChatEvent {}

class RefreshChannelsOnlyEvent extends ChatEvent {}

class RefreshCurrentChannelMessagesEvent extends ChatEvent {}

// Search filtering event
class SetSearchFilterEvent extends ChatEvent {
  final String searchTerm;
  SetSearchFilterEvent(this.searchTerm);
}

class ClearSelectedChannelEvent extends ChatEvent {}

// New events for pin/unpin functionality
class PinMessageEvent extends ChatEvent {
  final String messageId;
  final String userId;
  final UserRole userRole;

  PinMessageEvent({
    required this.messageId,
    required this.userId,
    required this.userRole,
  });
}

class UnpinMessageEvent extends ChatEvent {
  final String messageId;
  final String userId;
  final UserRole userRole;

  UnpinMessageEvent({
    required this.messageId,
    required this.userId,
    required this.userRole,
  });
}

// States
abstract class ChatState {}

class ChatInitialState extends ChatState {}

class ChatLoadingState extends ChatState {}

class ChatLoadedState extends ChatState {
  final List<ChatChannel> allChannels; // All channels from API
  final List<ChatChannel> filteredChannels; // Filtered channels for display
  final ChatChannel? selectedChannel;
  final List<ChatMessage> messages;
  final bool isLoadingMessages;
  final bool isSendingMessage;
  final bool isPinningMessage;
  final bool isLoadingReactions;
  final Map<String, List<PostReaction>>
  messageReactions; // messageId -> reactions
  final String searchTerm; // Search state
  final String? error;
  // Pagination fields
  final bool hasMoreMessages;
  final bool isLoadingMoreMessages;
  final DateTime? oldestMessageTimestamp;

  ChatLoadedState({
    required this.allChannels,
    List<ChatChannel>? filteredChannels,
    this.selectedChannel,
    this.messages = const [],
    this.isLoadingMessages = false,
    this.isSendingMessage = false,
    this.isPinningMessage = false,
    this.isLoadingReactions = false,
    this.messageReactions = const {},
    this.searchTerm = '',
    this.error,
    this.hasMoreMessages = false,
    this.isLoadingMoreMessages = false,
    this.oldestMessageTimestamp,
  }) : filteredChannels =
           filteredChannels ?? _applyFilters(allChannels, searchTerm);

  // Getter for the channels to display (backwards compatibility)
  List<ChatChannel> get channels => filteredChannels;

  // Static helper method to apply filters
  static List<ChatChannel> _applyFilters(
    List<ChatChannel> allChannels,
    String searchTerm,
  ) {
    // Include followed channels AND the MVC official channel (always visible)
    List<ChatChannel> filtered = allChannels
        .where((channel) =>
            channel.isFollowed ||
            channel.organizationId == _mvcOrganizationId)
        .toList();

    // Apply search filter
    if (searchTerm.isNotEmpty) {
      final searchLower = searchTerm.toLowerCase();
      filtered = filtered.where((channel) {
        return channel.name.toLowerCase().contains(searchLower) ||
            (channel.description?.toLowerCase().contains(searchLower) ?? false);
      }).toList();
    }

    // Sort channels by last message timestamp (most recent first, like WhatsApp)
    filtered.sort((a, b) {
      // If both channels have last messages, sort by message timestamp
      if (a.lastMessage != null && b.lastMessage != null) {
        return b.lastMessage!.createdAt.compareTo(a.lastMessage!.createdAt);
      }

      // If only one has a last message, prioritize the one with a message
      if (a.lastMessage != null && b.lastMessage == null) {
        return -1; // a comes first
      }
      if (a.lastMessage == null && b.lastMessage != null) {
        return 1; // b comes first
      }

      // If neither has a last message, sort by channel creation date (most recent first)
      return b.createdAt.compareTo(a.createdAt);
    });

    return filtered;
  }

  ChatLoadedState copyWith({
    List<ChatChannel>? allChannels,
    List<ChatChannel>? filteredChannels,
    ChatChannel? selectedChannel,
    bool updateSelectedChannel = false,
    List<ChatMessage>? messages,
    bool? isLoadingMessages,
    bool? isSendingMessage,
    bool? isPinningMessage,
    bool? isLoadingReactions,
    Map<String, List<PostReaction>>? messageReactions,
    String? searchTerm,
    String? error,
    bool clearError = false,
    bool? hasMoreMessages,
    bool? isLoadingMoreMessages,
    DateTime? oldestMessageTimestamp,
  }) {
    final newAllChannels = allChannels ?? this.allChannels;
    final newSearchTerm = searchTerm ?? this.searchTerm;
    final newFilteredChannels =
        filteredChannels ?? _applyFilters(newAllChannels, newSearchTerm);
    final newSelectedChannel = updateSelectedChannel
        ? selectedChannel
        : this.selectedChannel;

    return ChatLoadedState(
      allChannels: newAllChannels,
      filteredChannels: newFilteredChannels,
      selectedChannel: newSelectedChannel,
      messages: messages ?? this.messages,
      isLoadingMessages: isLoadingMessages ?? this.isLoadingMessages,
      isSendingMessage: isSendingMessage ?? this.isSendingMessage,
      isPinningMessage: isPinningMessage ?? this.isPinningMessage,
      isLoadingReactions: isLoadingReactions ?? this.isLoadingReactions,
      messageReactions: messageReactions ?? this.messageReactions,
      searchTerm: newSearchTerm,
      error: clearError ? null : (error ?? this.error),
      hasMoreMessages: hasMoreMessages ?? this.hasMoreMessages,
      isLoadingMoreMessages:
          isLoadingMoreMessages ?? this.isLoadingMoreMessages,
      oldestMessageTimestamp:
          oldestMessageTimestamp ?? this.oldestMessageTimestamp,
    );
  }

  // Factory method to create state with updated filters
  ChatLoadedState withUpdatedFilters({String? searchTerm}) {
    final newSearchTerm = searchTerm ?? this.searchTerm;
    final filteredChannels = _applyFilters(allChannels, newSearchTerm);

    return copyWith(
      searchTerm: newSearchTerm,
      filteredChannels: filteredChannels,
    );
  }
}

class ChatErrorState extends ChatState {
  final String error;
  ChatErrorState(this.error);
}

// BLoC
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatService _chatService;
  final AuthBloc _authBloc;

  ChatBloc({ChatService? chatService, required AuthBloc authBloc})
    : _chatService = chatService ?? ChatService(),
      _authBloc = authBloc,
      super(ChatInitialState()) {
    on<LoadChannelsEvent>(_onLoadChannels);
    on<SelectChannelEvent>(_onSelectChannel);
    on<SelectChannelByOrganizationIdEvent>(_onSelectChannelByOrganizationId);
    on<FollowAndSelectOrganizationEvent>(_onFollowAndSelectOrganization);
    on<LoadMessagesEvent>(_onLoadMessages);
    on<LoadMoreMessagesEvent>(_onLoadMoreMessages);
    on<SendMessageEvent>(_onSendMessage);
    on<RefreshChannelsEvent>(_onRefreshChannels);
    on<RefreshChannelsOnlyEvent>(_onRefreshChannelsOnly);
    on<RefreshCurrentChannelMessagesEvent>(_onRefreshCurrentChannelMessages);
    on<SetSearchFilterEvent>(_onSetSearchFilter);
    on<ClearSelectedChannelEvent>(_onClearSelectedChannel);
    on<PinMessageEvent>(_onPinMessage);
    on<UnpinMessageEvent>(_onUnpinMessage);
    on<EditMessageEvent>(_onEditMessage);
    on<DeleteMessageEvent>(_onDeleteMessage);
    on<AddReactionEvent>(_onAddReaction);
    on<RemoveReactionEvent>(_onRemoveReaction);
    on<LoadMessageReactionsEvent>(_onLoadMessageReactions);
  }

  String _getCurrentUserId() {
    final authState = _authBloc.state;
    if (authState is AuthAuthenticatedState) {
      // Prefer userProfile.id if available, otherwise fall back to userId
      if (authState.userProfile != null) {
        return authState.userProfile!.id;
      }
      // Fall back to userId directly from auth state
      if (authState.userId.isNotEmpty) {
        return authState.userId;
      }
    }
    return '';
  }

  // Helper method to check if user can pin/unpin messages
  bool _canPinMessage(UserRole userRole) {
    // Superadmins and admins can pin/unpin messages
    return userRole.isAdmin || userRole.isSuperAdmin;
  }

  Future<void> _onLoadChannels(
    LoadChannelsEvent event,
    Emitter<ChatState> emit,
  ) async {
    try {
      print("_onLoadChannels");

      final userId = _getCurrentUserId();

      // Validate userId before attempting to load channels
      if (userId.isEmpty) {
        errorLog(
          'Cannot load channels: user is not authenticated',
          tag: 'CHAT_BLOC',
        );
        emit(ChatErrorState('Please log in to view channels'));
        return;
      }

      final channels = await _chatService.getChannelsWithLastMessage(userId);

      if (state is ChatLoadedState) {
        // If we already have a loaded state, update channels but clear selection
        // This prevents auto-selecting the last channel on reload
        final currentState = state as ChatLoadedState;
        final updatedState = currentState.copyWith(
          allChannels: channels,
          selectedChannel: null, // Clear selection on reload
          updateSelectedChannel: true,
          messages: [], // Clear messages when clearing selection
        );
        final filteredState = updatedState.withUpdatedFilters();

        // Update notification badge based on unread count
        await ChatService.updateNotificationBadgeFromChannels(channels);

        emit(filteredState);
      } else {
        // If this is the initial load, emit loading state first
        emit(ChatLoadingState());
        final initialState = ChatLoadedState(allChannels: channels);
        final filteredState = initialState.withUpdatedFilters();

        // Update notification badge based on unread count
        await ChatService.updateNotificationBadgeFromChannels(channels);

        emit(filteredState);
      }
    } catch (e) {
      emit(ChatErrorState('Failed to load channels: $e'));
    }
  }

  Future<void> _onSetSearchFilter(
    SetSearchFilterEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is ChatLoadedState) {
      final currentState = state as ChatLoadedState;
      final updatedState = currentState.withUpdatedFilters(
        searchTerm: event.searchTerm,
      );
      emit(updatedState);
    }
  }

  Future<void> _onClearSelectedChannel(
    ClearSelectedChannelEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is ChatLoadedState) {
      final currentState = state as ChatLoadedState;
      emit(
        currentState.copyWith(
          selectedChannel: null,
          updateSelectedChannel: true,
          messages: [],
          messageReactions: {},
          isLoadingMessages: false,
        ),
      );
    }
  }

  Future<void> _onSelectChannel(
    SelectChannelEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is ChatLoadedState) {
      final currentState = state as ChatLoadedState;

      // Mark channel as read when selected
      await _chatService.markChannelAsRead(event.channel.organizationId);

      // Update the channel's unread status in the list
      final updatedChannel = await _chatService.updateChannelUnreadStatus(
        event.channel,
      );

      // Update the channels list with the new unread status
      final updatedChannels = currentState.allChannels.map((channel) {
        if (channel.id == updatedChannel.id) {
          return updatedChannel;
        }
        return channel;
      }).toList();

      // Update notification badge based on unread count
      await ChatService.updateNotificationBadgeFromChannels(updatedChannels);

      // Update selected channel and start loading messages
      emit(
        currentState.copyWith(
          allChannels: updatedChannels,
          selectedChannel: updatedChannel,
          updateSelectedChannel: true,
          messages: [], // Clear previous messages
          isLoadingMessages: true,
          clearError: true,
        ),
      );

      // Load messages for the selected channel
      add(LoadMessagesEvent(event.channel.id, _getCurrentUserId()));
    }
  }

  Future<void> _onSelectChannelByOrganizationId(
    SelectChannelByOrganizationIdEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is ChatLoadedState) {
      final currentState = state as ChatLoadedState;

      // Find the channel that matches the organization ID
      final matchingChannel = currentState.allChannels
          .where((channel) => channel.organizationId == event.organizationId)
          .firstOrNull;

      if (matchingChannel != null) {
        // Mark channel as read when selected
        await _chatService.markChannelAsRead(matchingChannel.organizationId);

        // Update the channel's unread status in the list
        final updatedChannel = await _chatService.updateChannelUnreadStatus(
          matchingChannel,
        );

        // Update the channels list with the new unread status
        final updatedChannels = currentState.allChannels.map((channel) {
          if (channel.id == updatedChannel.id) {
            return updatedChannel;
          }
          return channel;
        }).toList();

        // Update notification badge based on unread count
        await ChatService.updateNotificationBadgeFromChannels(updatedChannels);

        // Update selected channel and start loading messages
        emit(
          currentState.copyWith(
            allChannels: updatedChannels,
            selectedChannel: updatedChannel,
            updateSelectedChannel: true,
            messages: [], // Clear previous messages
            isLoadingMessages: true,
            clearError: true,
          ),
        );

        // Load messages for the selected channel
        add(LoadMessagesEvent(matchingChannel.id, _getCurrentUserId()));
      } else {
        // Organization not found in channels - try to follow and select it
        add(FollowAndSelectOrganizationEvent(event.organizationId));
      }
    }
  }

  Future<void> _onFollowAndSelectOrganization(
    FollowAndSelectOrganizationEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is ChatLoadedState) {
      final currentState = state as ChatLoadedState;

      try {
        emit(currentState.copyWith(isLoadingMessages: true, clearError: true));

        // First, try to follow the organization
        final userId = _getCurrentUserId();
        final followResult = await _chatService.followOrganization(
          event.organizationId,
          userId,
        );

        if (followResult) {
          // Reload channels to get the newly followed organization
          final channels = await _chatService.getChannelsWithLastMessage(
            userId,
          );

          // Update notification badge after following
          await ChatService.updateNotificationBadgeFromChannels(channels);

          // Find the channel for this organization
          final matchingChannel = channels
              .where(
                (channel) => channel.organizationId == event.organizationId,
              )
              .firstOrNull;

          if (matchingChannel != null) {
            // Update state with new channels and select the organization's channel
            final updatedState = currentState.copyWith(
              allChannels: channels,
              selectedChannel: matchingChannel,
              updateSelectedChannel: true,
              messages: [], // Clear previous messages
              isLoadingMessages: true,
              clearError: true,
            );
            final filteredState = updatedState.withUpdatedFilters();
            emit(filteredState);

            // Load messages for the selected channel
            add(LoadMessagesEvent(matchingChannel.id, userId));
          } else {
            emit(
              currentState.copyWith(
                isLoadingMessages: false,
                error: 'Organization channel not found after following',
              ),
            );
          }
        } else {
          emit(
            currentState.copyWith(
              isLoadingMessages: false,
              error: 'Failed to follow organization',
            ),
          );
        }
      } catch (e) {
        emit(
          currentState.copyWith(
            isLoadingMessages: false,
            error: 'Failed to follow and select organization: $e',
          ),
        );
      }
    }
  }

  Future<void> _onLoadMessages(
    LoadMessagesEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is ChatLoadedState) {
      final currentState = state as ChatLoadedState;

      try {
        emit(currentState.copyWith(isLoadingMessages: true, clearError: true));

        // Load only the latest 10 messages initially
        final messages = await _chatService.getMessages(
          event.channelId,
          limit: 10,
        );

        // Messages come from API ordered by created_at DESC (newest first)
        // Sort chronologically (oldest first) for display
        final orderedMessages = messages.toList();
        orderedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

        // Determine if there are more messages to load
        final hasMore = messages.length >= 10;
        final oldestTimestamp = orderedMessages.isNotEmpty
            ? orderedMessages.first.createdAt
            : null;

        emit(
          currentState.copyWith(
            messages: orderedMessages,
            isLoadingMessages: false,
            hasMoreMessages: hasMore,
            oldestMessageTimestamp: oldestTimestamp,
          ),
        );

        // Load reactions for all messages
        for (final message in orderedMessages) {
          add(LoadMessageReactionsEvent(messageId: message.id));
        }
      } catch (e) {
        emit(
          currentState.copyWith(
            isLoadingMessages: false,
            error: 'Failed to load messages: $e',
          ),
        );
      }
    }
  }

  Future<void> _onLoadMoreMessages(
    LoadMoreMessagesEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is ChatLoadedState) {
      final currentState = state as ChatLoadedState;

      try {
        emit(
          currentState.copyWith(isLoadingMoreMessages: true, clearError: true),
        );

        // Load 10 more messages before the oldest timestamp
        final olderMessages = await _chatService.getMessages(
          event.channelId,
          limit: 10,
          beforeTimestamp: event.beforeTimestamp,
        );

        if (olderMessages.isEmpty) {
          // No more messages to load
          emit(
            currentState.copyWith(
              isLoadingMoreMessages: false,
              hasMoreMessages: false,
            ),
          );
          return;
        }

        // Sort chronologically (oldest first)
        olderMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

        // Prepend older messages to the existing list
        final updatedMessages = [...olderMessages, ...currentState.messages];

        // Check if there are more messages (if we got 10, there might be more)
        final hasMore = olderMessages.length >= 10;
        final oldestTimestamp = olderMessages.first.createdAt;

        emit(
          currentState.copyWith(
            messages: updatedMessages,
            isLoadingMoreMessages: false,
            hasMoreMessages: hasMore,
            oldestMessageTimestamp: oldestTimestamp,
          ),
        );

        // Load reactions for the newly loaded messages
        for (final message in olderMessages) {
          add(LoadMessageReactionsEvent(messageId: message.id));
        }
      } catch (e) {
        emit(
          currentState.copyWith(
            isLoadingMoreMessages: false,
            error: 'Failed to load more messages: $e',
          ),
        );
      }
    }
  }

  Future<void> _onSendMessage(
    SendMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is ChatLoadedState) {
      final currentState = state as ChatLoadedState;

      // Allow sending if any of title, content, or fileUrl is provided
      final bool hasContent = event.content.trim().isNotEmpty;
      final bool hasTitle = (event.title?.trim().isNotEmpty ?? false);
      final bool hasFile = (event.fileUrl?.trim().isNotEmpty ?? false);
      if (!hasContent && !hasTitle && !hasFile) return;

      try {
        emit(currentState.copyWith(isSendingMessage: true, clearError: true));

        final newMessage = await _chatService.sendMessage(
          organizationId: event.organizationId,
          userId: event.userId,
          content: event.content,
          title: event.title,
          postType: event.postType,
          fileUrl: event.fileUrl,
        );

        // Add the new message to the end of the list (newest at bottom)
        final updatedMessages = [...currentState.messages, newMessage];

        emit(
          currentState.copyWith(
            messages: updatedMessages,
            isSendingMessage: false,
          ),
        );

        // Refresh channels to update last message
        add(RefreshChannelsEvent());
      } catch (e) {
        emit(
          currentState.copyWith(
            isSendingMessage: false,
            error: 'Failed to send message: $e',
          ),
        );
      }
    }
  }

  Future<void> _onRefreshChannels(
    RefreshChannelsEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is ChatLoadedState) {
      final currentState = state as ChatLoadedState;

      try {
        final channels = await _chatService.getChannelsWithLastMessage(
          _getCurrentUserId(),
        );

        ChatChannel? refreshedSelectedChannel = currentState.selectedChannel;
        bool shouldUpdateSelection = false;

        if (currentState.selectedChannel != null) {
          refreshedSelectedChannel = channels
              .where(
                (channel) => channel.id == currentState.selectedChannel!.id,
              )
              .firstOrNull;
          shouldUpdateSelection = true;
        }

        // Maintain current filter settings when refreshing
        final updatedState = currentState.copyWith(
          allChannels: channels,
          selectedChannel: refreshedSelectedChannel,
          updateSelectedChannel: shouldUpdateSelection,
          messages: refreshedSelectedChannel == null
              ? []
              : currentState.messages,
        );
        final filteredState = updatedState.withUpdatedFilters();

        // Update notification badge based on unread count
        await ChatService.updateNotificationBadgeFromChannels(channels);

        emit(filteredState);
      } catch (e) {
        // Don't emit error for refresh, just log it
        print('Failed to refresh channels: $e');
      }
    }
  }

  Future<void> _onRefreshChannelsOnly(
    RefreshChannelsOnlyEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is ChatLoadedState) {
      final currentState = state as ChatLoadedState;

      try {
        print('🔄 Refreshing channels only (preserving current chat state)');
        final channels = await _chatService.getChannelsWithLastMessage(
          _getCurrentUserId(),
        );

        ChatChannel? refreshedSelectedChannel = currentState.selectedChannel;
        bool shouldUpdateSelection = false;

        if (currentState.selectedChannel != null) {
          refreshedSelectedChannel = channels
              .where(
                (channel) => channel.id == currentState.selectedChannel!.id,
              )
              .firstOrNull;
          shouldUpdateSelection = true;
        }

        // Preserve ALL current state, only update channels
        final updatedState = currentState.copyWith(
          allChannels: channels,
          selectedChannel: refreshedSelectedChannel,
          updateSelectedChannel: shouldUpdateSelection,
          messages: refreshedSelectedChannel == null
              ? []
              : currentState.messages,
        );
        final filteredState = updatedState.withUpdatedFilters();

        // Update notification badge based on unread count
        await ChatService.updateNotificationBadgeFromChannels(channels);

        emit(filteredState);
      } catch (e) {
        // Don't emit error for refresh, just log it
        print('Failed to refresh channels only: $e');
      }
    }
  }

  Future<void> _onRefreshCurrentChannelMessages(
    RefreshCurrentChannelMessagesEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is ChatLoadedState) {
      final currentState = state as ChatLoadedState;

      if (currentState.selectedChannel != null) {
        try {
          print(
            '🔄 Refreshing messages for current channel: ${currentState.selectedChannel!.id}',
          );

          emit(
            currentState.copyWith(isLoadingMessages: true, clearError: true),
          );

          final messages = await _chatService.getMessages(
            currentState.selectedChannel!.id,
            limit: 10,
          );
          final orderedMessages = messages.toList();
          orderedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

          // Update pagination state
          final hasMore = messages.length >= 10;
          final oldestTimestamp = orderedMessages.isNotEmpty
              ? orderedMessages.first.createdAt
              : null;

          emit(
            currentState.copyWith(
              messages: orderedMessages,
              isLoadingMessages: false,
              hasMoreMessages: hasMore,
              oldestMessageTimestamp: oldestTimestamp,
            ),
          );

          // Load reactions for all messages
          for (final message in orderedMessages) {
            add(LoadMessageReactionsEvent(messageId: message.id));
          }
        } catch (e) {
          emit(
            currentState.copyWith(
              isLoadingMessages: false,
              error: 'Failed to refresh messages: $e',
            ),
          );
        }
      }
    }
  }

  Future<void> _onPinMessage(
    PinMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    print("onPinMessage start");
    if (state is ChatLoadedState) {
      print("chat is loaded");
      final currentState = state as ChatLoadedState;

      // Check if user has permission to pin messages
      if (!_canPinMessage(event.userRole)) {
        emit(
          currentState.copyWith(
            error: 'You do not have permission to pin messages',
          ),
        );
        return;
      }

      try {
        emit(currentState.copyWith(isPinningMessage: true, clearError: true));

        final success = await _chatService.pinMessage(
          event.messageId,
          event.userId,
        );

        if (success) {
          // Update the message status in the local state
          final updatedMessages = currentState.messages.map((message) {
            if (message.id == event.messageId) {
              return ChatMessage(
                id: message.id,
                organizationId: message.organizationId,
                createdBy: message.createdBy,
                title: message.title,
                content: message.content,
                postType: message.postType,
                fileUrl: message.fileUrl,
                status: 'fixated',
                viewCount: message.viewCount,
                createdAt: message.createdAt,
                updatedAt: DateTime.now(),
                author: message.author,
              );
            }
            return message;
          }).toList();

          // Re-sort messages to ensure pinned messages are at the top
          final pinnedMessages = <ChatMessage>[];
          final regularMessages = <ChatMessage>[];

          for (final message in updatedMessages) {
            if (message.status == 'fixated') {
              pinnedMessages.add(message);
            } else {
              regularMessages.add(message);
            }
          }

          // Sort both lists chronologically (oldest first)
          pinnedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          regularMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

          // Combine with pinned first
          final finalMessages = [...pinnedMessages, ...regularMessages];

          emit(
            currentState.copyWith(
              messages: finalMessages,
              isPinningMessage: false,
            ),
          );
        } else {
          emit(
            currentState.copyWith(
              isPinningMessage: false,
              error: 'Failed to pin message',
            ),
          );
        }
      } catch (e) {
        emit(
          currentState.copyWith(
            isPinningMessage: false,
            error: 'Failed to pin message: $e',
          ),
        );
      }
    }
  }

  Future<void> _onUnpinMessage(
    UnpinMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    print("Un onPinMessage start");
    if (state is ChatLoadedState) {
      final currentState = state as ChatLoadedState;
      print("Unpining msg");

      // Check if user has permission to unpin messages
      if (!_canPinMessage(event.userRole)) {
        emit(
          currentState.copyWith(
            error: 'You do not have permission to unpin messages',
          ),
        );
        return;
      }

      try {
        emit(currentState.copyWith(isPinningMessage: true, clearError: true));

        final success = await _chatService.unpinMessage(
          event.messageId,
          event.userId,
        );

        if (success) {
          // Update the message status in the local state
          final updatedMessages = currentState.messages.map((message) {
            if (message.id == event.messageId) {
              return ChatMessage(
                id: message.id,
                organizationId: message.organizationId,
                createdBy: message.createdBy,
                title: message.title,
                content: message.content,
                postType: message.postType,
                fileUrl: message.fileUrl,
                status: 'active',
                viewCount: message.viewCount,
                createdAt: message.createdAt,
                updatedAt: DateTime.now(),
                author: message.author,
              );
            }
            return message;
          }).toList();

          // Re-sort messages to ensure pinned messages are at the top
          final pinnedMessages = <ChatMessage>[];
          final regularMessages = <ChatMessage>[];

          for (final message in updatedMessages) {
            if (message.status == 'fixated') {
              pinnedMessages.add(message);
            } else {
              regularMessages.add(message);
            }
          }

          // Sort both lists chronologically (oldest first)
          pinnedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          regularMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

          // Combine with pinned first
          final finalMessages = [...pinnedMessages, ...regularMessages];

          emit(
            currentState.copyWith(
              messages: finalMessages,
              isPinningMessage: false,
            ),
          );
        } else {
          emit(
            currentState.copyWith(
              isPinningMessage: false,
              error: 'Failed to unpin message',
            ),
          );
        }
      } catch (e) {
        emit(
          currentState.copyWith(
            isPinningMessage: false,
            error: 'Failed to unpin message: $e',
          ),
        );
      }
    }
  }

  Future<void> _onEditMessage(
    EditMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is ChatLoadedState) {
      final currentState = state as ChatLoadedState;

      // Parse the combined content (title\n\ncontent format)
      // The format is: [title, content].join('\n\n')
      final parts = event.newContent.split('\n\n');
      String? newTitle;
      String? newContent;

      if (parts.length >= 2) {
        // First part is title, rest is content
        newTitle = parts[0].isEmpty ? null : parts[0];
        newContent = parts.sublist(1).join('\n\n');
        if (newContent.isEmpty) newContent = null;
      } else if (parts.length == 1) {
        // Only content, no title
        newContent = parts[0].isEmpty ? null : parts[0];
        newTitle = null;
      }

      // Use newTitle from event if provided (more reliable)
      final finalTitle = event.newTitle ?? newTitle;

      // Update the message in the current list
      final updatedMessages = currentState.messages.map((msg) {
        if (msg.id == event.messageId) {
          return ChatMessage(
            id: msg.id,
            organizationId: msg.organizationId,
            createdBy: msg.createdBy,
            title: finalTitle,
            content: newContent,
            postType: msg.postType,
            fileUrl: msg.fileUrl,
            status: msg.status,
            viewCount: msg.viewCount,
            createdAt: msg.createdAt,
            updatedAt: DateTime.now(),
            author: msg.author,
          );
        }
        return msg;
      }).toList();

      emit(currentState.copyWith(messages: updatedMessages, clearError: true));
    }
  }

  Future<void> _onDeleteMessage(
    DeleteMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    print("ONDELETE");
    // TODO: Implement delete message functionality
  }

  // Reaction event handlers
  Future<void> _onAddReaction(
    AddReactionEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is ChatLoadedState) {
      final currentState = state as ChatLoadedState;

      try {
        emit(currentState.copyWith(isLoadingReactions: true, clearError: true));

        final success = await _chatService.addReaction(
          event.messageId,
          event.emojis,
          event.userId,
        );

        if (success) {
          // Reload reactions for this message
          add(LoadMessageReactionsEvent(messageId: event.messageId));
        } else {
          emit(
            currentState.copyWith(
              isLoadingReactions: false,
              error: 'Failed to add reaction',
            ),
          );
        }
      } catch (e) {
        emit(
          currentState.copyWith(
            isLoadingReactions: false,
            error: 'Failed to add reaction: $e',
          ),
        );
      }
    }
  }

  Future<void> _onRemoveReaction(
    RemoveReactionEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is ChatLoadedState) {
      final currentState = state as ChatLoadedState;

      try {
        emit(currentState.copyWith(isLoadingReactions: true, clearError: true));

        final success = await _chatService.removeReaction(
          event.messageId,
          event.userId,
        );

        if (success) {
          // Remove reactions from local state
          final updatedReactions = Map<String, List<PostReaction>>.from(
            currentState.messageReactions,
          );
          updatedReactions.remove(event.messageId);

          emit(
            currentState.copyWith(
              messageReactions: updatedReactions,
              isLoadingReactions: false,
            ),
          );
        } else {
          emit(
            currentState.copyWith(
              isLoadingReactions: false,
              error: 'Failed to remove reaction',
            ),
          );
        }
      } catch (e) {
        emit(
          currentState.copyWith(
            isLoadingReactions: false,
            error: 'Failed to remove reaction: $e',
          ),
        );
      }
    }
  }

  Future<void> _onLoadMessageReactions(
    LoadMessageReactionsEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is ChatLoadedState) {
      final currentState = state as ChatLoadedState;

      try {
        final reactions = await _chatService.getMessageReactions(
          event.messageId,
        );
        for (var reaction in reactions) {
          print("Reactions: ${reaction.toJson()}");
        }

        final updatedReactions = Map<String, List<PostReaction>>.from(
          currentState.messageReactions,
        );
        updatedReactions[event.messageId] = reactions;

        emit(
          currentState.copyWith(
            messageReactions: updatedReactions,
            isLoadingReactions: false,
          ),
        );
      } catch (e) {
        emit(
          currentState.copyWith(
            isLoadingReactions: false,
            error: 'Failed to load reactions: $e',
          ),
        );
      }
    }
  }
}

class EditMessageEvent extends ChatEvent {
  final String messageId;
  final String newContent;
  final String? newTitle;

  EditMessageEvent({
    required this.messageId,
    required this.newContent,
    this.newTitle,
  });
}

class DeleteMessageEvent extends ChatEvent {
  final String messageId;

  DeleteMessageEvent({required this.messageId});
}

// Reaction events
class AddReactionEvent extends ChatEvent {
  final String messageId;
  final List<String> emojis;
  final String userId;

  AddReactionEvent({
    required this.messageId,
    required this.emojis,
    required this.userId,
  });
}

class RemoveReactionEvent extends ChatEvent {
  final String messageId;
  final String userId;

  RemoveReactionEvent({required this.messageId, required this.userId});
}

class LoadMessageReactionsEvent extends ChatEvent {
  final String messageId;

  LoadMessageReactionsEvent({required this.messageId});
}
