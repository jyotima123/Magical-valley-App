// lib/modules/chat/widgets/chat_view.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/models/ad_model.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/chat/chat_bloc.dart';
import 'package:mvc_app/modules/chat/models/chat_message.dart';
import 'package:mvc_app/services/ad_service.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/utils/timezone_utils.dart';

import 'ad_widget.dart';
import 'message_item.dart';
import 'message_input.dart';
import 'pinned_posts_section.dart';

// Helper class to represent list items
class _MessageListItem {
  final ChatMessage? message;
  final String? dateDivider;
  final bool isAd;

  _MessageListItem({this.message, this.dateDivider, this.isAd = false});

  bool get isMessage => message != null && !isAd;
  bool get isDateDivider => dateDivider != null;
  bool get isAdItem => isAd;
}

class ChatView extends StatefulWidget {
  final TextEditingController messageController;
  final ScrollController messagesScrollController;
  final AppThemeMode theme;

  const ChatView({
    super.key,
    required this.messageController,
    required this.messagesScrollController,
    required this.theme,
  });

  @override
  State<ChatView> createState() => _ChatViewState();

  // Static map to store viewed post IDs per channel (for access from outside)
  static final Map<String, Set<String>> _channelPostViews = {};

  /// Save post views for a specific channel (called when channel changes)
  /// This is a static method that can be called from outside the widget
  static Future<void> savePostViewsForChannel(
    String? channelId,
    BuildContext context,
  ) async {
    if (channelId == null || channelId.isEmpty) {
      return;
    }

    final viewedPostIds = _channelPostViews[channelId];
    if (viewedPostIds == null || viewedPostIds.isEmpty) {
      return;
    }

    try {
      final apiRepository = context.read<ApiRepository>();
      final postIds = viewedPostIds.toList();

      // Clear the set for this channel before inserting
      _channelPostViews.remove(channelId);

      // Run in background without blocking the UI
      unawaited(
        apiRepository
            .batchInsertPostViews(postIds)
            .then((result) {
              if (result.isSuccess) {
                print(
                  '✅ Successfully recorded ${postIds.length} post views for channel $channelId',
                );
              } else {
                print(
                  '⚠️ Failed to record post views for channel $channelId: ${result.error}',
                );
                // Re-add if failed (for potential retry)
                _channelPostViews[channelId] = postIds.toSet();
              }
            })
            .catchError((e) {
              print('❌ Error recording post views for channel $channelId: $e');
              // Re-add if failed (for potential retry)
              _channelPostViews[channelId] = viewedPostIds;
            }),
      );
    } catch (e) {
      print('❌ Error recording post views for channel $channelId: $e');
      // Re-add if failed (for potential retry)
      _channelPostViews[channelId] = viewedPostIds;
    }
  }
}

class _ChatViewState extends State<ChatView> {
  List<ChatMessage> _previousMessages = [];
  bool _shouldAutoScroll = true;

  // Track viewed post IDs to batch insert when leaving the chat
  final Set<String> _viewedPostIds = {};
  bool _isDisposed = false;

  // Current channel ID being viewed
  String? _currentChannelId;

  // Ad management
  List<AdModel> _availableAds = [];
  bool _isLoadingAds = false;

  @override
  void initState() {
    super.initState();

    // Add scroll listener to detect manual scrolling
    widget.messagesScrollController.addListener(_onScroll);

    // Load ads for the chat
    _loadAds();

    // Scroll to bottom when the widget is first built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  /// Load ads from the ad service
  Future<void> _loadAds() async {
    if (_isLoadingAds || _isDisposed) return;

    setState(() {
      _isLoadingAds = true;
    });

    try {
      print('🚀 ChatView: Starting to load ads...');
      final ads = await AdService.instance.getRandomMediumRectangleAds(count: 10);
      if (!_isDisposed && mounted) {
        setState(() {
          _availableAds = ads;
          _isLoadingAds = false;
        });
        print('💾 ChatView: Loaded ${ads.length} ads into state');
      }
    } catch (e) {
      print('❌ ChatView: Error loading ads: $e');
      if (!_isDisposed && mounted) {
        setState(() {
          _isLoadingAds = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    widget.messagesScrollController.removeListener(_onScroll);

    // Batch insert all viewed post IDs when leaving the chat
    _batchInsertPostViews();

    super.dispose();
  }

  /// Track a post as viewed when it becomes visible
  void _trackPostView(String postId) {
    if (!_isDisposed && postId.isNotEmpty) {
      _viewedPostIds.add(postId);
      // Also store in static map for access when channel changes
      if (_currentChannelId != null) {
        ChatView._channelPostViews
            .putIfAbsent(_currentChannelId!, () => <String>{})
            .add(postId);
        print(
          '📊 Tracked post view: postId=$postId, channelId=$_currentChannelId',
        );
      } else {
        print('⚠️ Cannot track post view: postId=$postId, channelId is null');
      }
    }
  }

  /// Batch insert all viewed post IDs to the database
  /// This is called when the widget is disposed or when navigating away
  /// Can also be called manually when channel changes
  Future<void> _batchInsertPostViews() async {
    if (_viewedPostIds.isEmpty || _isDisposed) {
      return;
    }

    try {
      final apiRepository = context.read<ApiRepository>();
      final postIds = _viewedPostIds.toList();

      // Clear the set before inserting to avoid duplicates if called multiple times
      _viewedPostIds.clear();

      // Run in background without blocking the UI
      unawaited(
        apiRepository
            .batchInsertPostViews(postIds)
            .then((result) {
              if (result.isSuccess) {
                print('✅ Successfully recorded ${postIds.length} post views');
              } else {
                print('⚠️ Failed to record post views: ${result.error}');
              }
            })
            .catchError((e) {
              print('❌ Error recording post views: $e');
            }),
      );
    } catch (e) {
      print('❌ Error recording post views: $e');
    }
  }

  /// Update current channel ID and initialize tracking for it
  void _updateCurrentChannel(String? channelId) {
    if (_currentChannelId != null && _currentChannelId != channelId) {
      // Channel changed - save post views for previous channel
      print(
        '🔄 Channel changed: ${_currentChannelId} -> $channelId, saving post views for previous channel',
      );
      ChatView.savePostViewsForChannel(_currentChannelId, context);
    }
    _currentChannelId = channelId;
    // Initialize tracking for new channel
    if (channelId != null) {
      ChatView._channelPostViews.putIfAbsent(channelId, () => <String>{});
      print('📊 Initialized post view tracking for channel: $channelId');
    } else {
      print('📊 Cleared post view tracking (no channel selected)');
    }
  }

  void _onScroll() {
    // Check if user has scrolled up from the bottom
    if (widget.messagesScrollController.hasClients) {
      final position = widget.messagesScrollController.position;
      final maxScroll = position.maxScrollExtent;
      final currentScroll = position.pixels;

      // If user is near the bottom (within 100 pixels), enable auto-scroll
      // If user has scrolled up significantly, disable auto-scroll
      _shouldAutoScroll = (maxScroll - currentScroll) < 100;
    }
  }

  @override
  void didUpdateWidget(ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if we should auto-scroll (when new messages are added)
    if (_shouldAutoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  void _scrollToBottom() {
    if (widget.messagesScrollController.hasClients) {
      widget.messagesScrollController.animateTo(
        widget.messagesScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  bool _hasNewMessages(List<ChatMessage> currentMessages) {
    if (currentMessages.length != _previousMessages.length) {
      _previousMessages = List.from(currentMessages);
      return true;
    }

    // Check if the last message is different (new message added)
    if (currentMessages.isNotEmpty && _previousMessages.isNotEmpty) {
      final lastCurrent = currentMessages.last;
      final lastPrevious = _previousMessages.last;
      if (lastCurrent.id != lastPrevious.id) {
        _previousMessages = List.from(currentMessages);
        // If it's a new message, always enable auto-scroll to show it
        _shouldAutoScroll = true;
        return true;
      }
    }

    return false;
  }

  // Helper method to separate pinned and regular messages
  Map<String, List<ChatMessage>> _separateMessages(List<ChatMessage> messages) {
    final pinnedMessages = <ChatMessage>[];
    final regularMessages = <ChatMessage>[];

    for (final message in messages) {
      if (message.status == 'fixated') {
        pinnedMessages.add(message);
      } else {
        regularMessages.add(message);
      }
    }

    // Sort regular messages chronologically (oldest first) for proper display
    regularMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Sort pinned messages chronologically (oldest first) for proper display
    pinnedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    print(
      'ChatView: Pinned ${pinnedMessages.length}, Regular ${regularMessages.length}',
    );
    return {'pinned': pinnedMessages, 'regular': regularMessages};
  }

  // Helper method to format date for dividers
  String _formatDateDivider(DateTime date) {
    return TimezoneUtils.formatDateDivider(date);
  }

  // Build optimized list items with date dividers and ads
  List<_MessageListItem> _buildMessageListItems(List<ChatMessage> messages) {
    if (messages.isEmpty) return [];

    List<_MessageListItem> items = [];
    DateTime? lastDate;
    int messagesSinceLastAd = 0;
    int adIndex = 0;

    print('🎬 Building message list with ${messages.length} messages and ${_availableAds.length} available ads');

    for (final message in messages) {
      // Convert to local time for date comparison
      final localDateTime = TimezoneUtils.toLocalTime(message.createdAt);
      final messageDate = DateTime(
        localDateTime.year,
        localDateTime.month,
        localDateTime.day,
      );

      // Add date divider if this is a new day
      if (lastDate == null || messageDate != lastDate) {
        items.add(
          _MessageListItem(dateDivider: _formatDateDivider(message.createdAt)),
        );
        lastDate = messageDate;
      }

      // Add the message
      items.add(_MessageListItem(message: message));
      messagesSinceLastAd++;

      // Insert an ad after every 3 messages
      if (messagesSinceLastAd >= 3 && _availableAds.isNotEmpty) {
        print('📺 Inserting ad at position ${items.length}');
        items.add(_MessageListItem(isAd: true));
        messagesSinceLastAd = 0;
        adIndex = (adIndex + 1) % _availableAds.length;
      }
    }

    print('📋 Built ${items.length} list items (${messages.length} messages, ${items.where((i) => i.isAdItem).length} ads)');
    return items;
  }

  // Optimized ListView.builder for messages
  Widget _buildOptimizedMessageList(
    List<ChatMessage> messages,
    String currentUserId,
    UserRole currentUserRole,
    String currentOrganizationId,
    List<String> currentUserManagedOrganizations,
    BuildContext context,
    ChatLoadedState chatState,
  ) {
    final listItems = _buildMessageListItems(messages);

    return ListView.builder(
      controller: widget.messagesScrollController,
      reverse: false,
      itemCount:
          listItems.length +
          (chatState.hasMoreMessages && !chatState.isLoadingMoreMessages
              ? 1
              : 0) +
          (chatState.isLoadingMoreMessages ? 1 : 0),
      // Optimize cache extent - reduce to prevent loading too many images off-screen
      // Reduced further to prevent dimension loading for off-screen images
      cacheExtent:
          200, // Reduced from 300 to minimize off-screen image processing
      // Add physics optimization for smoother scrolling
      physics: const ClampingScrollPhysics(),
      itemBuilder: (context, index) {
        // Load More button at the top
        if (index == 0 &&
            chatState.hasMoreMessages &&
            !chatState.isLoadingMoreMessages) {
          return _buildLoadMoreButton(context, chatState, currentUserId);
        }

        // Loading indicator
        if (index == 0 && chatState.isLoadingMoreMessages) {
          return _buildLoadingMoreIndicator(context);
        }

        // Adjust index for header items
        final adjustedIndex =
            index -
            (chatState.hasMoreMessages && !chatState.isLoadingMoreMessages
                ? 1
                : 0) -
            (chatState.isLoadingMoreMessages ? 1 : 0);

        if (adjustedIndex < 0 || adjustedIndex >= listItems.length) {
          return const SizedBox.shrink();
        }

        final item = listItems[adjustedIndex];

        // Build date divider
        if (item.isDateDivider) {
          return _buildDateDivider(item.dateDivider!, context);
        }

        // Build ad item
        if (item.isAdItem && _availableAds.isNotEmpty) {
          // Calculate which ad to show based on the index
          final adIndex = (adjustedIndex ~/ 4) % _availableAds.length;
          final ad = _availableAds[adIndex];

          print('📺 Rendering ad at index $adjustedIndex (ad ${adIndex + 1}/${_availableAds.length})');

          return RepaintBoundary(
            key: ValueKey('ad_$adjustedIndex'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(44,2,2,2),
              child: AdWidget(
                ad: ad,
                theme: widget.theme,
              ),
            ),
          );
        }

        // Build message item with RepaintBoundary for performance
        if (item.isMessage) {
          final messageId = item.message!.id;

          // Track post view when message becomes visible (only once per session)
          // ListView.builder only builds visible items, so this is accurate
          // Track immediately since ListView.builder only builds visible items
          if (mounted && !_isDisposed) {
            _trackPostView(messageId);
          }

          return RepaintBoundary(
            child: MessageItem(
              key: ValueKey(
                item.message!.id,
              ), // Use message ID as key for better recycling
              message: item.message!,
              currentUserId: currentUserId,
              theme: widget.theme,
              isPinned: item.message!.status == 'fixated',
              currentUserRole: currentUserRole,
              messageAuthorRole: item.message!.author?.role ?? UserRole.regular,
              currentOrganizationId: currentOrganizationId,
              currentUserManagedOrganizations: currentUserManagedOrganizations,
              reactions: chatState.messageReactions[item.message!.id] ?? [],
              onPinToggle: (messageId, shouldPin) {
                final chatBloc = BlocProvider.of<ChatBloc>(context);
                if (shouldPin) {
                  chatBloc.add(
                    PinMessageEvent(
                      messageId: messageId,
                      userId: currentUserId,
                      userRole: currentUserRole,
                    ),
                  );
                } else {
                  chatBloc.add(
                    UnpinMessageEvent(
                      messageId: messageId,
                      userId: currentUserId,
                      userRole: currentUserRole,
                    ),
                  );
                }
              },
              onEditMessage: (messageId, newContent) {
                final chatBloc = BlocProvider.of<ChatBloc>(context);
                chatBloc.add(
                  EditMessageEvent(
                    messageId: messageId,
                    newContent: newContent,
                  ),
                );
              },
              onDeleteMessage: (messageId) {
                final chatBloc = BlocProvider.of<ChatBloc>(context);
                chatBloc.add(DeleteMessageEvent(messageId: messageId));
                Navigator.pop(context);
              },
              onReactionUpdate: (messageId, emojis) {
                final chatBloc = BlocProvider.of<ChatBloc>(context);
                if (emojis.isEmpty) {
                  chatBloc.add(
                    RemoveReactionEvent(
                      messageId: messageId,
                      userId: currentUserId,
                    ),
                  );
                } else {
                  chatBloc.add(
                    AddReactionEvent(
                      messageId: messageId,
                      emojis: emojis,
                      userId: currentUserId,
                    ),
                  );
                }
              },
              apiRepository: context.read<ApiRepository>(),
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  // Widget for date dividers
  Widget _buildDateDivider(String dateText, BuildContext context) {
    final isDark = widget.theme == AppThemeMode.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: isDark
                  ? AppTheme.darkTextTertiary
                  : AppTheme.dividerBackground,
              thickness: 1,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.darkSurface
                  : AppTheme.cardGreyBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              dateText,
              style: isDark
                  ? AppTheme.darkChatDateDivider
                  : AppTheme.chatDateDivider,
            ),
          ),
          Expanded(
            child: Divider(
              color: isDark
                  ? AppTheme.darkTextTertiary
                  : AppTheme.dividerBackground,
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isDark = widget.theme == AppThemeMode.dark;

    return Center(
      child: Text(
        'This channel hasn\'t posted anything yet\n New posts will appear here',
        textAlign: TextAlign.center,
        style: isDark
            ? AppTheme.darkChatEmptyMessage
            : AppTheme.chatEmptyMessage,
      ),
    );
  }

  Widget _buildLoadingIndicator(BuildContext context) {
    final isDark = widget.theme == AppThemeMode.dark;

    return Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(
          isDark ? AppTheme.accentPrimary : AppTheme.accentPrimary,
        ),
      ),
    );
  }

  Widget _buildLoadMoreButton(
    BuildContext context,
    ChatLoadedState chatState,
    String currentUserId,
  ) {
    final isDark = widget.theme == AppThemeMode.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Center(
        child: TextButton(
          onPressed: () {
            if (chatState.oldestMessageTimestamp != null) {
              final chatBloc = BlocProvider.of<ChatBloc>(context);
              chatBloc.add(
                LoadMoreMessagesEvent(
                  chatState.selectedChannel!.id,
                  currentUserId,
                  chatState.oldestMessageTimestamp!,
                ),
              );
            }
          },
          style: TextButton.styleFrom(
            backgroundColor: isDark
                ? AppTheme.darkSurface
                : AppTheme.cardGreyBackground,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(
            'Load More Posts',
            style: isDark
                ? AppTheme.darkFieldText.copyWith(
                    color: AppTheme.accentSecondary,
                    fontWeight: FontWeight.w600,
                  )
                : AppTheme.bodyText.copyWith(
                    color: AppTheme.accentSecondary,
                    fontWeight: FontWeight.w600,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingMoreIndicator(BuildContext context) {
    final isDark = widget.theme == AppThemeMode.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              isDark ? AppTheme.accentPrimary : AppTheme.accentPrimary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.theme == AppThemeMode.dark;

    return Container(
      color: isDark ? context.darkBackground : AppTheme.white,
      child: BlocBuilder<ChatBloc, ChatState>(
        builder: (context, chatState) {
          if (chatState is! ChatLoadedState) {
            return _buildLoadingIndicator(context);
          }

          // Update current channel tracking when channel changes (synchronously)
          final currentChannelId = chatState.selectedChannel?.id;
          if (_currentChannelId != currentChannelId) {
            _updateCurrentChannel(currentChannelId);
          }

          return BlocBuilder<AuthBloc, AuthState>(
            builder: (context, authState) {
              // Get current user ID and role for message comparison
              String currentUserId = '';
              UserRole currentUserRole = UserRole.regular;
              List<String> currentUserManagedOrganizations = [];
              if (authState is AuthAuthenticatedState) {
                currentUserId = authState.userId;
                currentUserRole =
                    authState.userProfile?.role ?? UserRole.regular;
                currentUserManagedOrganizations = authState.managedOrganizations
                    .map((org) => org.id)
                    .toList();
              }

              // Separate pinned and regular messages
              final separatedMessages = _separateMessages(chatState.messages);
              final pinnedMessages = separatedMessages['pinned']!;
              final regularMessages = separatedMessages['regular']!;

              // Check if we have new messages and should auto-scroll
              if (_hasNewMessages(chatState.messages)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_shouldAutoScroll) {
                    _scrollToBottom();
                  }
                });
              }

              // Also scroll to bottom when messages are first loaded (not loading anymore)
              if (!chatState.isLoadingMessages &&
                  chatState.messages.isNotEmpty &&
                  _previousMessages.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });
              }

              return Column(
                children: [
                  // Sticky pinned posts section at the top
                  if (pinnedMessages.isNotEmpty)
                    Container(
                      color: isDark ? AppTheme.darkBackground : AppTheme.white,
                      child: PinnedPostsSection(
                        pinnedMessages: pinnedMessages,
                        currentUserId: currentUserId,
                        theme: widget.theme,
                        currentUserRole: currentUserRole,
                        currentOrganizationId:
                            chatState.selectedChannel?.organizationId ?? '',
                        currentUserManagedOrganizations:
                            currentUserManagedOrganizations,
                        messageReactions: chatState.messageReactions,
                        onPinToggle: (messageId, shouldPin) {
                          final chatBloc = BlocProvider.of<ChatBloc>(context);
                          if (shouldPin) {
                            print("emmitting pin message");
                            chatBloc.add(
                              PinMessageEvent(
                                messageId: messageId,
                                userId: currentUserId,
                                userRole: currentUserRole,
                              ),
                            );
                          } else {
                            print("emmitting unpin message");
                            chatBloc.add(
                              UnpinMessageEvent(
                                messageId: messageId,
                                userId: currentUserId,
                                userRole: currentUserRole,
                              ),
                            );
                          }
                        },
                        onReactionUpdate: (messageId, emojis) {
                          // Handle reaction updates for pinned messages
                          final chatBloc = BlocProvider.of<ChatBloc>(context);
                          if (emojis.isEmpty) {
                            chatBloc.add(
                              RemoveReactionEvent(
                                messageId: messageId,
                                userId: currentUserId,
                              ),
                            );
                          } else {
                            chatBloc.add(
                              AddReactionEvent(
                                messageId: messageId,
                                emojis: emojis,
                                userId: currentUserId,
                              ),
                            );
                          }
                        },
                      ),
                    ),

                  // Messages area (scrollable)
                  Expanded(
                    child: chatState.isLoadingMessages
                        ? _buildLoadingIndicator(context)
                        : (regularMessages.isEmpty && pinnedMessages.isEmpty)
                        ? _buildEmptyState(context)
                        : Container(
                            color: isDark
                                ? AppTheme.darkBackground
                                : AppTheme.white,
                            child: _buildOptimizedMessageList(
                              [...pinnedMessages, ...regularMessages],
                              currentUserId,
                              currentUserRole,
                              chatState.selectedChannel?.organizationId ?? '',
                              currentUserManagedOrganizations,
                              context,
                              chatState,
                            ),
                          ),
                  ),

                  // Show loading indicator for pin/unpin operations
                  if (chatState.isPinningMessage)
                    Container(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isDark
                                    ? AppTheme.accentPrimary
                                    : AppTheme.accentPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Updating pin status...',
                            style: isDark
                                ? AppTheme.darkFieldText
                                : AppTheme.darkFieldText,
                          ),
                        ],
                      ),
                    ),

                  // Message input
                  MessageInput(
                    controller: widget.messageController,
                    chatState: chatState,
                    authState: authState,
                    theme: widget.theme,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
