// lib/modules/chat/direct_messages_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/chat/models/direct_message.dart';
import 'package:mvc_app/modules/chat/models/direct_message_conversation.dart';
import 'package:mvc_app/modules/chat/models/direct_message_item.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';
import 'package:mvc_app/modules/chat/select_organization_screen.dart';
import 'package:mvc_app/modules/admin/user_selector.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:cached_network_image/cached_network_image.dart';

class DirectMessagesScreen extends StatefulWidget {
  const DirectMessagesScreen({super.key});

  @override
  State<DirectMessagesScreen> createState() => _DirectMessagesScreenState();
}

class _DirectMessagesScreenState extends State<DirectMessagesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  DirectMessageConversation? _selectedConversation;
  bool _isNavigatingToChat = false;
  bool _isLoading = true;
  String? _errorMessage;

  List<DirectMessageConversation> _conversations = [];
  List<DirectMessageItem> _messages = [];
  StreamSubscription<List<DirectMessageConversation>>?
  _conversationsSubscription;
  StreamSubscription<List<DirectMessageItem>>? _messagesSubscription;
  String? _currentUserId;
  String?
  _currentConversationId; // Track which conversation's messages are loaded
  UserRole? _currentUserRole;
  Set<String> _managedOrganizationIds = {}; // Organizations the user can manage
  Map<String, UserProfile> _userProfilesCache =
      {}; // Cache user profiles for admin view
  Set<String> _animatedMessageIds =
      {}; // Track which messages have been animated
  final ScrollController _messagesScrollController = ScrollController();

  // Rate limiting for markDirectMessagesAsRead
  DateTime? _lastMarkAsReadTime;
  static const Duration _markAsReadCooldown = Duration(seconds: 2);
  bool _isMarkingAsRead = false; // Prevent concurrent calls

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterConversations);
    _loadUserRoleAndOrganizations();
    _loadConversations();
  }

  Future<void> _loadUserRoleAndOrganizations() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticatedState ||
        authState.userProfile?.id == null) {
      return;
    }

    final userId = authState.userProfile!.id;
    _currentUserId = userId;

    try {
      final apiRepository = context.read<ApiRepository>();

      // Get user role
      final roleResult = await apiRepository.getUserRole(userId);
      if (roleResult.isSuccess) {
        setState(() {
          _currentUserRole = roleResult.data;
        });
      }

      // Get managed organizations (for admins and superadmins)
      if (_currentUserRole?.isAdminOrSuperAdmin == true) {
        final orgsResult = await apiRepository.getUserManagedOrganizations(
          userId,
        );
        if (orgsResult.isSuccess && orgsResult.data != null) {
          setState(() {
            _managedOrganizationIds = orgsResult.data!
                .map((org) => org.id)
                .toSet();
          });
        }
      }
    } catch (e) {
      print('Error loading user role and organizations: $e');
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterConversations);
    _searchController.dispose();
    _messageController.dispose();
    _conversationsSubscription?.cancel();
    _messagesSubscription?.cancel();
    super.dispose();
  }

  void _filterConversations() {
    setState(() {});
  }

  /// Get the display name for a message sender
  String _getMessageSenderName(
    DirectMessageItem message,
    DirectMessageConversation conversation,
  ) {
    final isAdmin = _currentUserRole?.isAdminOrSuperAdmin == true;

    if (isAdmin) {
      // For admins: messages from the user show user's name, messages from admins show organization name
      if (message.senderId == conversation.userId) {
        // Message from the user
        return message.sender?.fullName ?? message.sender?.username ?? 'User';
      } else {
        // Message from an admin (sent as the organization)
        return conversation.organizationName;
      }
    } else {
      // For regular users: messages from themselves show their name, messages from admins show organization name
      if (message.senderId == conversation.userId) {
        return message.sender?.fullName ?? message.sender?.username ?? 'User';
      }
      // If sender is not the user, they must be an admin responding as the organization
      return conversation.organizationName;
    }
  }

  Future<void> _loadConversations() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticatedState ||
        authState.userProfile?.id == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Let\'s start messaging';
      });
      return;
    }

    _currentUserId = authState.userProfile!.id;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiRepository = context.read<ApiRepository>();

      // Check if user is admin and has managed organizations
      final isAdmin = _currentUserRole?.isAdminOrSuperAdmin == true;
      final hasManagedOrgs = _managedOrganizationIds.isNotEmpty;

      if (isAdmin && hasManagedOrgs) {
        // Load conversations for organizations the admin manages
        final result = await apiRepository
            .getDirectMessageConversationsByOrganizations(
              _managedOrganizationIds.toList(),
            );

        if (result.isSuccess) {
          final conversations = result.data ?? [];

          // Load user profiles for all conversations (for displaying user names)
          await _loadUserProfilesForConversations(conversations);

          setState(() {
            _conversations = conversations;
            _isLoading = false;
          });

          // Set up real-time subscription for admin
          _conversationsSubscription?.cancel();
          _conversationsSubscription = apiRepository
              .streamDirectMessageConversationsByOrganizations(
                _managedOrganizationIds.toList(),
              )
              .listen(
                (conversations) async {
                  if (mounted) {
                    // Load user profiles for new conversations
                    await _loadUserProfilesForConversations(conversations);
                    setState(() {
                      _conversations = conversations;
                    });
                  }
                },
                onError: (error) {
                  print('Error in admin conversations stream: $error');
                  // Optionally reconnect after a delay
                  if (mounted) {
                    Future.delayed(const Duration(seconds: 2), () {
                      if (mounted) {
                        _loadConversations();
                      }
                    });
                  }
                },
              );
        } else {
          setState(() {
            _errorMessage = result.error ?? 'Failed to load conversations';
            _isLoading = false;
          });
        }
      } else {
        // Regular user: load conversations normally
        final result = await apiRepository.getDirectMessageConversations(
          _currentUserId!,
        );

        if (result.isSuccess) {
          setState(() {
            _conversations = result.data ?? [];
            _isLoading = false;
          });

          // Set up real-time subscription
          _conversationsSubscription?.cancel();
          _conversationsSubscription = apiRepository
              .streamDirectMessageConversations(_currentUserId!)
              .listen(
                (conversations) {
                  if (mounted) {
                    setState(() {
                      _conversations = conversations;
                    });
                  }
                },
                onError: (error) {
                  print('Error in conversations stream: $error');
                  // Optionally reconnect after a delay
                  if (mounted) {
                    Future.delayed(const Duration(seconds: 2), () {
                      if (mounted) {
                        _loadConversations();
                      }
                    });
                  }
                },
              );
        } else {
          setState(() {
            _errorMessage = result.error ?? 'Failed to load conversations';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading conversations: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUserProfilesForConversations(
    List<DirectMessageConversation> conversations,
  ) async {
    final apiRepository = context.read<ApiRepository>();
    final userIdsToLoad = conversations
        .map((conv) => conv.userId)
        .where((userId) => !_userProfilesCache.containsKey(userId))
        .toSet();

    if (userIdsToLoad.isEmpty) return;

    // Load user profiles concurrently
    final futures = userIdsToLoad.map((userId) async {
      final result = await apiRepository.getUserProfile(userId);
      if (result.isSuccess && result.data != null) {
        return MapEntry(userId, result.data!);
      }
      return null;
    }).toList();

    final results = await Future.wait(futures);

    if (mounted) {
      setState(() {
        for (final entry in results) {
          if (entry != null) {
            _userProfilesCache[entry.key] = entry.value;
          }
        }
      });
    }
  }

  Future<void> _loadMessages(String conversationId) async {
    if (_currentUserId == null) return;

    // If we're already loading messages for this conversation and have a subscription, don't reload
    if (_currentConversationId == conversationId &&
        _messages.isNotEmpty &&
        _messagesSubscription != null) {
      return;
    }

    try {
      final apiRepository = context.read<ApiRepository>();

      // Cancel existing subscription if switching conversations
      if (_currentConversationId != null &&
          _currentConversationId != conversationId) {
        _messagesSubscription?.cancel();
        _messagesSubscription = null;
      }

      // Clear messages when switching to a different conversation
      if (_currentConversationId != conversationId) {
        setState(() {
          _messages = [];
          _currentConversationId = conversationId;
          _animatedMessageIds
              .clear(); // Clear animated IDs when switching conversations
        });
      }

      // Load initial messages
      final result = await apiRepository.getDirectMessages(
        conversationId,
        limit: 50,
      );

      if (result.isSuccess) {
        final initialMessages = (result.data ?? []).reversed.toList();
        setState(() {
          _messages = initialMessages; // Reverse to show oldest first
          _currentConversationId = conversationId;
          // Mark initial messages as already animated (no animation on first load)
          _animatedMessageIds.addAll(initialMessages.map((m) => m.id));
        });

        // Scroll to bottom after initial load
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _messagesScrollController.hasClients) {
            _messagesScrollController.animateTo(
              _messagesScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });

        // Mark messages as read (with rate limiting)
        _markMessagesAsReadDebounced(conversationId, _currentUserId!);

        // Set up real-time subscription for messages (always set up for the current conversation)
        _messagesSubscription?.cancel();
        _messagesSubscription = apiRepository
            .streamDirectMessages(conversationId)
            .listen(
              (messages) async {
                if (mounted && _currentConversationId == conversationId) {
                  final previousMessageIds = _messages.map((m) => m.id).toSet();
                  final previousMessageCount = _messages.length;
                  final newMessages = messages.reversed.toList();

                  // Track which messages are new for animation
                  final newMessageIds = newMessages
                      .where((msg) => !previousMessageIds.contains(msg.id))
                      .map((msg) => msg.id)
                      .toSet();

                  setState(() {
                    _messages = newMessages;
                    // Add new message IDs to animated set (they'll animate on next frame)
                    _animatedMessageIds.addAll(newMessageIds);
                  });

                  // Scroll to bottom when new messages arrive
                  if (newMessageIds.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _messagesScrollController.hasClients) {
                        _messagesScrollController.animateTo(
                          _messagesScrollController.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    });
                  }

                  // Mark new messages as read when they arrive in real-time
                  // Only mark messages from others (not the current user)
                  if (newMessages.length > previousMessageCount &&
                      _currentUserId != null) {
                    // Check if there are unread messages from others
                    final hasUnreadFromOthers = newMessages.any(
                      (msg) => !msg.isRead && msg.senderId != _currentUserId,
                    );

                    if (hasUnreadFromOthers) {
                      // Mark as read in the background with rate limiting
                      _markMessagesAsReadDebounced(
                        conversationId,
                        _currentUserId!,
                      );
                    }
                  }
                }
              },
              onError: (error) {
                print('Error in message stream: $error');
                // Optionally reconnect after a delay
                if (mounted && _currentConversationId == conversationId) {
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted && _currentConversationId == conversationId) {
                      _loadMessages(conversationId);
                    }
                  });
                }
              },
            );
      }
    } catch (e) {
      print('Error loading messages: $e');
    }
  }

  Future<void> _startNewConversation() async {
    final organization = await Navigator.push<Organization>(
      context,
      MaterialPageRoute(builder: (context) => const SelectOrganizationScreen()),
    );

    if (organization != null && _currentUserId != null) {
      try {
        final apiRepository = context.read<ApiRepository>();
        final result = await apiRepository.createOrGetDirectMessageConversation(
          _currentUserId!,
          organization.id,
        );

        if (result.isSuccess) {
          // Select the new conversation
          setState(() {
            _selectedConversation = result.data;
          });
          await _loadMessages(result.data!.id);
          // Refresh conversations list
          await _loadConversations();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result.error ?? 'Failed to start conversation'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _startNewConversationAsAdmin() async {
    // First, select an organization the admin manages
    if (_managedOrganizationIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You need to manage at least one organization to start a conversation',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final organization = await Navigator.push<Organization>(
      context,
      MaterialPageRoute(
        builder: (context) => SelectOrganizationScreen(
          allowedOrganizationIds: _managedOrganizationIds.toList(),
        ),
      ),
    );

    if (organization == null) {
      return; // User cancelled organization selection
    }

    // Then, select a user to start the conversation with
    final selectedUsers = await context.showUserSelector(
      title: 'Select User',
      allowMultipleSelection: false,
      excludeUserIds: _currentUserId != null
          ? [_currentUserId!]
          : null, // Exclude current user (admin)
    );

    if (selectedUsers == null || selectedUsers.isEmpty) {
      return; // User cancelled user selection
    }

    final selectedUser = selectedUsers.first;

    try {
      final apiRepository = context.read<ApiRepository>();
      final result = await apiRepository.createOrGetDirectMessageConversation(
        selectedUser.id,
        organization.id,
      );

      if (result.isSuccess) {
        // Select the new conversation
        setState(() {
          _selectedConversation = result.data;
        });
        await _loadMessages(result.data!.id);
        // Refresh conversations list
        await _loadConversations();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'Failed to start conversation'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sendMessage([String? conversationId]) async {
    final targetConversationId = conversationId ?? _selectedConversation?.id;
    if (targetConversationId == null || _currentUserId == null) {
      print(
        'Cannot send message: conversationId=$targetConversationId, userId=$_currentUserId',
      );
      return;
    }
    if (_messageController.text.trim().isEmpty) return;

    final content = _messageController.text.trim();
    _messageController.clear();

    try {
      final apiRepository = context.read<ApiRepository>();
      final result = await apiRepository.sendDirectMessage(
        targetConversationId,
        content,
      );

      if (!result.isSuccess) {
        // Restore message on error
        _messageController.text = content;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'Failed to send message'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      _messageController.text = content;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<DirectMessageConversation> get _filteredConversations {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      return _conversations;
    }

    final isAdmin = _currentUserRole?.isAdminOrSuperAdmin == true;

    if (isAdmin) {
      // For admins, search by user name
      return _conversations.where((conv) {
        final userProfile = _userProfilesCache[conv.userId];
        final userName = userProfile?.fullName ?? userProfile?.username ?? '';
        return userName.toLowerCase().contains(query);
      }).toList();
    } else {
      // For regular users, search by organization name
      return _conversations
          .where((conv) => conv.organizationName.toLowerCase().contains(query))
          .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isWideScreen = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: AppTheme.cardGreyBackground,
      appBar: AppBar(
        title: const Text('Direct Messages'),
        backgroundColor: AppTheme.headerBackground,
        foregroundColor: AppTheme.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            color: AppTheme.accentPrimary,
            iconSize: 28,
            onPressed: _currentUserRole?.isAdminOrSuperAdmin == true
                ? _startNewConversationAsAdmin
                : _startNewConversation,
            tooltip: 'Start new conversation',
          ),
        ],
      ),
      body: isWideScreen
          ? _buildWideScreenLayout()
          : _buildNarrowScreenLayout(),
    );
  }

  Widget _buildWideScreenLayout() {
    return Row(
      children: [
        SizedBox(
          width: MediaQuery.of(context).size.width * 0.35,
          child: _buildConversationsList(),
        ),
        const VerticalDivider(
          width: 1,
          thickness: 1,
          color: AppTheme.dividerBackground,
        ),
        Expanded(
          child: _selectedConversation != null
              ? _buildChatView(_selectedConversation!)
              : const Center(
                  child: Text('Select a conversation to start chatting'),
                ),
        ),
      ],
    );
  }

  Widget _buildNarrowScreenLayout() {
    if (_selectedConversation != null) {
      return _buildChatView(_selectedConversation!);
    }
    return _buildConversationsList();
  }

  void _navigateToChatView(DirectMessageConversation conversation) {
    if (_isNavigatingToChat) return; // Prevent double navigation
    _isNavigatingToChat = true;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ChatScreen(
          conversation: conversation,
          currentUserId: _currentUserId,
          currentUserRole: _currentUserRole,
          userProfilesCache: _userProfilesCache,
          onBack: () {
            Navigator.pop(context);
          },
        ),
      ),
    ).then((_) {
      _isNavigatingToChat = false;
      // Clean up messages when returning from chat
      setState(() {
        _messages = [];
        _currentConversationId = null;
        _animatedMessageIds.clear();
        _messagesSubscription?.cancel();
        _messagesSubscription = null;
      });
    });
  }

  Widget _buildConversationsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadConversations,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentPrimary,
              ),
              child: const Text(
                'Continue',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    final conversations = _filteredConversations;

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            style: AppTheme.searchInput,
            decoration: InputDecoration(
              hintText: 'Search conversations...',
              hintStyle: AppTheme.searchInput.copyWith(
                color: AppTheme.secondaryHeadingColor,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: AppTheme.secondaryHeadingColor,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear,
                        color: AppTheme.secondaryHeadingColor,
                      ),
                      onPressed: () {
                        _searchController.clear();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: AppTheme.searchBarBackground,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),
        Expanded(
          child: conversations.isEmpty
              ? RefreshIndicator(
                  onRefresh: _loadConversations,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: _buildEmptyState(),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadConversations,
                  child: ListView.separated(
                    itemCount: conversations.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      thickness: 0.5,
                      color: AppTheme.dividerBackground.withOpacity(0.5),
                    ),
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];
                      final isSelected =
                          _selectedConversation?.id == conversation.id;
                      final isAdmin =
                          _currentUserRole?.isAdminOrSuperAdmin == true;

                      // For admins, get user profile to display user name
                      final userProfile = isAdmin
                          ? _userProfilesCache[conversation.userId]
                          : null;
                      final displayName = isAdmin
                          ? (userProfile?.fullName ??
                                userProfile?.username ??
                                'User')
                          : conversation.organizationName;
                      final displayLogoUrl = isAdmin
                          ? userProfile?.profilePictureUrl
                          : conversation.organizationLogoUrl;

                      // Convert to DirectMessage for compatibility with existing UI code
                      final directMessage = DirectMessage(
                        id: conversation.id,
                        channelId: conversation.organizationId,
                        channelName: displayName,
                        channelLogoUrl: displayLogoUrl,
                        createdAt: conversation.createdAt,
                        lastMessage: conversation.lastMessage,
                        unreadCount: conversation.unreadCount,
                        hasUnreadMessages: conversation.hasUnreadMessages,
                      );

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            final bool isWideScreen =
                                MediaQuery.of(context).size.width >= 600;

                            if (isWideScreen) {
                              setState(() {
                                _selectedConversation = conversation;
                              });
                              _loadMessages(conversation.id);
                            } else {
                              if (!_isNavigatingToChat) {
                                _navigateToChatView(conversation);
                              }
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.cardGreyBackground
                                  : Colors.transparent,
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                _buildChannelAvatar(directMessage),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              displayName,
                                              style: AppTheme.chatTitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (conversation.lastMessage !=
                                              null) ...[
                                            const SizedBox(width: 8),
                                            Text(
                                              conversation
                                                  .lastMessage!
                                                  .timeDisplay,
                                              style: AppTheme.chatTimestamp,
                                            ),
                                          ],
                                          if (conversation
                                              .hasUnreadMessages) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: AppTheme.accentPrimary,
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: AppTheme
                                                        .accentPrimary
                                                        .withOpacity(0.3),
                                                    blurRadius: 4,
                                                    spreadRadius: 1,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      conversation.lastMessage != null
                                          ? Text(
                                              conversation
                                                  .lastMessage!
                                                  .displayContent,
                                              style: AppTheme.chatMessage
                                                  .copyWith(
                                                    color: AppTheme
                                                        .secondaryHeadingColor,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            )
                                          : Text(
                                              'No messages yet',
                                              style: AppTheme.chatMessage
                                                  .copyWith(
                                                    fontStyle: FontStyle.italic,
                                                    color: AppTheme
                                                        .secondaryHeadingColor,
                                                  ),
                                            ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final isAdmin = _currentUserRole?.isAdminOrSuperAdmin == true;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: AppTheme.secondaryHeadingColor.withOpacity(0.5),
          ),
          const SizedBox(height: 24),
          Text(
            _searchController.text.isEmpty
                ? (isAdmin
                      ? "No messages from users yet"
                      : "No direct messages yet")
                : "No conversations found",
            style: AppTheme.chatTitle.copyWith(
              color: AppTheme.secondaryHeadingColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_searchController.text.isEmpty && !isAdmin) ...[
            const SizedBox(height: 8),
            Text(
              'Tap the + button to start a conversation',
              style: AppTheme.chatMessage.copyWith(
                color: AppTheme.secondaryHeadingColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChannelAvatar(DirectMessage message) {
    String fallbackText = message.channelName.substring(0, 1).toUpperCase();

    if (message.channelLogoUrl != null &&
        message.channelLogoUrl!.isNotEmpty &&
        Uri.tryParse(message.channelLogoUrl!) != null) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: CachedNetworkImageProvider(message.channelLogoUrl!),
        onBackgroundImageError: (_, __) {},
      );
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: AppTheme.accentPrimary.withOpacity(0.15),
      child: Text(
        fallbackText,
        style: TextStyle(
          color: AppTheme.accentPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildChatView(DirectMessageConversation conversation) {
    return Column(
      children: [Expanded(child: _buildChatViewContent(conversation))],
    );
  }

  Widget _buildChatViewContent(DirectMessageConversation conversation) {
    // Ensure conversation is selected and messages are loaded
    if (_selectedConversation?.id != conversation.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedConversation?.id != conversation.id) {
          setState(() {
            _selectedConversation = conversation;
          });
          _loadMessages(conversation.id);
        }
      });
    } else if (_currentConversationId != conversation.id || _messages.isEmpty) {
      // Load messages if not already loaded for this conversation
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            (_currentConversationId != conversation.id || _messages.isEmpty)) {
          _loadMessages(conversation.id);
        }
      });
    }

    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: AppTheme.secondaryHeadingColor.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _currentUserRole?.isAdminOrSuperAdmin == true
                            ? 'Start chatting with ${_userProfilesCache[conversation.userId]?.fullName ?? _userProfilesCache[conversation.userId]?.username ?? "User"}'
                            : 'Start chatting with ${conversation.organizationName}',
                        style: AppTheme.chatTitle.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _messagesScrollController,
                  padding: const EdgeInsets.all(16),
                  reverse: false,
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    final isOwnMessage = message.senderId == _currentUserId;
                    final senderName = _getMessageSenderName(
                      message,
                      conversation,
                    );

                    final shouldAnimate = _animatedMessageIds.contains(
                      message.id,
                    );

                    return AnimatedMessageWidget(
                      key: ValueKey(message.id),
                      message: message,
                      isOwnMessage: isOwnMessage,
                      senderName: senderName,
                      formatTime: _formatMessageTime,
                      shouldAnimate: shouldAnimate,
                      onAnimationComplete: () {
                        // Remove from animated set after animation completes
                        setState(() {
                          _animatedMessageIds.remove(message.id);
                        });
                      },
                    );
                  },
                ),
        ),
        // Message input area
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.searchBarBackground,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  style: AppTheme.searchInput,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: AppTheme.searchInput.copyWith(
                      color: AppTheme.secondaryHeadingColor,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: AppTheme.headerBackground,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(conversation.id),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: AppTheme.accentPrimary,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: () => _sendMessage(conversation.id),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Rate-limited version of markDirectMessagesAsRead
  /// Only allows one call every 2 seconds to prevent request spam
  void _markMessagesAsReadDebounced(String conversationId, String userId) {
    // Prevent concurrent calls
    if (_isMarkingAsRead) {
      return;
    }

    // Check cooldown period
    final now = DateTime.now();
    if (_lastMarkAsReadTime != null) {
      final timeSinceLastCall = now.difference(_lastMarkAsReadTime!);
      if (timeSinceLastCall < _markAsReadCooldown) {
        // Schedule for later
        Future.delayed(_markAsReadCooldown - timeSinceLastCall, () {
          if (mounted && _currentConversationId == conversationId) {
            _markMessagesAsReadDebounced(conversationId, userId);
          }
        });
        return;
      }
    }

    // Mark as read
    _isMarkingAsRead = true;
    _lastMarkAsReadTime = now;

    final apiRepository = context.read<ApiRepository>();
    apiRepository
        .markDirectMessagesAsRead(conversationId, userId)
        .then(
          (_) {
            _isMarkingAsRead = false;
          },
          onError: (e) {
            print('Error marking messages as read: $e');
            _isMarkingAsRead = false;
          },
        );
  }

  String _formatMessageTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      // Today - show time
      final hour = dateTime.hour;
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:$minute $period';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
    }
  }
}

/// Animated message widget with smooth slide, fade, and scale effects
class AnimatedMessageWidget extends StatefulWidget {
  final DirectMessageItem message;
  final bool isOwnMessage;
  final String senderName;
  final String Function(DateTime) formatTime;
  final bool shouldAnimate;
  final VoidCallback onAnimationComplete;

  const AnimatedMessageWidget({
    super.key,
    required this.message,
    required this.isOwnMessage,
    required this.senderName,
    required this.formatTime,
    required this.shouldAnimate,
    required this.onAnimationComplete,
  });

  @override
  State<AnimatedMessageWidget> createState() => _AnimatedMessageWidgetState();
}

class _AnimatedMessageWidgetState extends State<AnimatedMessageWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Slide animation - from the side (left for received, right for sent)
    _slideAnimation = Tween<Offset>(
      begin: Offset(widget.isOwnMessage ? 0.3 : -0.3, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    // Fade animation - starts quickly
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );

    // Scale animation with a smooth spring-like effect
    _scaleAnimation = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    // Start animation if needed
    if (widget.shouldAnimate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _controller.forward().then((_) {
            widget.onAnimationComplete();
          });
        }
      });
    } else {
      // If not animating, set to final state immediately
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(AnimatedMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If message ID changed and should animate, restart animation
    if (widget.message.id != oldWidget.message.id && widget.shouldAnimate) {
      _controller.reset();
      _controller.forward().then((_) {
        widget.onAnimationComplete();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.isOwnMessage
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              decoration: BoxDecoration(
                color: widget.isOwnMessage
                    ? AppTheme.accentPrimary
                    : AppTheme.searchBarBackground,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!widget.isOwnMessage) ...[
                    Text(
                      widget.senderName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: widget.isOwnMessage
                            ? Colors.white
                            : AppTheme.accentPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    widget.message.content,
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.isOwnMessage
                          ? Colors.white
                          : AppTheme.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.formatTime(widget.message.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.isOwnMessage
                          ? Colors.white70
                          : AppTheme.secondaryHeadingColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Separate chat screen widget for navigation in narrow screen mode
/// This manages its own message state to avoid conflicts
class _ChatScreen extends StatefulWidget {
  final DirectMessageConversation conversation;
  final String? currentUserId;
  final VoidCallback onBack;
  final UserRole? currentUserRole;
  final Map<String, UserProfile>? userProfilesCache;

  const _ChatScreen({
    required this.conversation,
    required this.currentUserId,
    required this.onBack,
    this.currentUserRole,
    this.userProfilesCache,
  });

  @override
  State<_ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<_ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  List<DirectMessageItem> _messages = [];
  StreamSubscription<List<DirectMessageItem>>? _messagesSubscription;
  String? _currentConversationId;
  Set<String> _animatedMessageIds =
      {}; // Track which messages have been animated
  final ScrollController _messagesScrollController = ScrollController();

  // Rate limiting for markDirectMessagesAsRead
  DateTime? _lastMarkAsReadTime;
  static const Duration _markAsReadCooldown = Duration(seconds: 2);
  bool _isMarkingAsRead = false; // Prevent concurrent calls

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messagesScrollController.dispose();
    _messagesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    if (widget.currentUserId == null) return;

    final conversationId = widget.conversation.id;

    // If we're already loading messages for this conversation, don't reload
    if (_currentConversationId == conversationId &&
        _messages.isNotEmpty &&
        _messagesSubscription != null) {
      return;
    }

    try {
      final apiRepository = context.read<ApiRepository>();

      // Clear messages when switching to a different conversation
      if (_currentConversationId != conversationId) {
        setState(() {
          _messages = [];
          _currentConversationId = conversationId;
          _animatedMessageIds
              .clear(); // Clear animated IDs when switching conversations
        });
      }

      // Load initial messages
      final result = await apiRepository.getDirectMessages(
        conversationId,
        limit: 50,
      );

      if (result.isSuccess) {
        final initialMessages = (result.data ?? []).reversed.toList();
        setState(() {
          _messages = initialMessages; // Reverse to show oldest first
          _currentConversationId = conversationId;
          // Mark initial messages as already animated (no animation on first load)
          _animatedMessageIds.addAll(initialMessages.map((m) => m.id));
        });

        // Scroll to bottom after initial load
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _messagesScrollController.hasClients) {
            _messagesScrollController.animateTo(
              _messagesScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });

        // Mark messages as read (with rate limiting)
        _markMessagesAsReadDebounced(conversationId, widget.currentUserId!);

        // Set up real-time subscription for messages
        _messagesSubscription?.cancel();
        _messagesSubscription = apiRepository
            .streamDirectMessages(conversationId)
            .listen(
              (messages) async {
                if (mounted && _currentConversationId == conversationId) {
                  final previousMessageIds = _messages.map((m) => m.id).toSet();
                  final previousMessageCount = _messages.length;
                  final newMessages = messages.reversed.toList();

                  // Track which messages are new for animation
                  final newMessageIds = newMessages
                      .where((msg) => !previousMessageIds.contains(msg.id))
                      .map((msg) => msg.id)
                      .toSet();

                  setState(() {
                    _messages = newMessages;
                    // Add new message IDs to animated set (they'll animate on next frame)
                    _animatedMessageIds.addAll(newMessageIds);
                  });

                  // Scroll to bottom when new messages arrive
                  if (newMessageIds.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _messagesScrollController.hasClients) {
                        _messagesScrollController.animateTo(
                          _messagesScrollController.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    });
                  }

                  // Mark new messages as read when they arrive in real-time
                  // Only mark messages from others (not the current user)
                  if (newMessages.length > previousMessageCount &&
                      widget.currentUserId != null) {
                    // Check if there are unread messages from others
                    final hasUnreadFromOthers = newMessages.any(
                      (msg) =>
                          !msg.isRead && msg.senderId != widget.currentUserId,
                    );

                    if (hasUnreadFromOthers) {
                      // Mark as read in the background with rate limiting
                      _markMessagesAsReadDebounced(
                        conversationId,
                        widget.currentUserId!,
                      );
                    }
                  }
                }
              },
              onError: (error) {
                print('Error in message stream: $error');
                // Optionally reconnect after a delay
                if (mounted && _currentConversationId == conversationId) {
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted && _currentConversationId == conversationId) {
                      _loadMessages();
                    }
                  });
                }
              },
            );
      }
    } catch (e) {
      print('Error loading messages: $e');
    }
  }

  Future<void> _sendMessage() async {
    final conversationId = widget.conversation.id;
    if (widget.currentUserId == null) {
      print(
        'Cannot send message: conversationId=$conversationId, userId=${widget.currentUserId}',
      );
      return;
    }
    if (_messageController.text.trim().isEmpty) return;

    final content = _messageController.text.trim();
    _messageController.clear();

    try {
      final apiRepository = context.read<ApiRepository>();
      final result = await apiRepository.sendDirectMessage(
        conversationId,
        content,
      );

      if (!result.isSuccess) {
        // Restore message on error
        _messageController.text = content;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'Failed to send message'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      _messageController.text = content;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Rate-limited version of markDirectMessagesAsRead
  /// Only allows one call every 2 seconds to prevent request spam
  void _markMessagesAsReadDebounced(String conversationId, String userId) {
    // Prevent concurrent calls
    if (_isMarkingAsRead) {
      return;
    }

    // Check cooldown period
    final now = DateTime.now();
    if (_lastMarkAsReadTime != null) {
      final timeSinceLastCall = now.difference(_lastMarkAsReadTime!);
      if (timeSinceLastCall < _markAsReadCooldown) {
        // Schedule for later
        Future.delayed(_markAsReadCooldown - timeSinceLastCall, () {
          if (mounted && _currentConversationId == conversationId) {
            _markMessagesAsReadDebounced(conversationId, userId);
          }
        });
        return;
      }
    }

    // Mark as read
    _isMarkingAsRead = true;
    _lastMarkAsReadTime = now;

    final apiRepository = context.read<ApiRepository>();
    apiRepository
        .markDirectMessagesAsRead(conversationId, userId)
        .then(
          (_) {
            _isMarkingAsRead = false;
          },
          onError: (e) {
            print('Error marking messages as read: $e');
            _isMarkingAsRead = false;
          },
        );
  }

  /// Get the display name for a message sender
  String _getMessageSenderName(DirectMessageItem message) {
    final isAdmin = widget.currentUserRole?.isAdminOrSuperAdmin == true;

    if (isAdmin) {
      // For admins: messages from the user show user's name, messages from admins show organization name
      if (message.senderId == widget.conversation.userId) {
        // Message from the user
        return message.sender?.fullName ?? message.sender?.username ?? 'User';
      } else {
        // Message from an admin (sent as the organization)
        return widget.conversation.organizationName;
      }
    } else {
      // For regular users: messages from themselves show their name, messages from admins show organization name
      if (message.senderId == widget.conversation.userId) {
        return message.sender?.fullName ?? message.sender?.username ?? 'User';
      }
      // If sender is not the user, they must be an admin responding as the organization
      return widget.conversation.organizationName;
    }
  }

  String _formatMessageTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      // Today - show time
      final hour = dateTime.hour;
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:$minute $period';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.currentUserRole?.isAdminOrSuperAdmin == true
              ? (widget
                        .userProfilesCache?[widget.conversation.userId]
                        ?.fullName ??
                    widget
                        .userProfilesCache?[widget.conversation.userId]
                        ?.username ??
                    'User')
              : widget.conversation.organizationName,
        ),
        backgroundColor: AppTheme.headerBackground,
        foregroundColor: AppTheme.darkBottomBarBackground,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: AppTheme.secondaryHeadingColor.withOpacity(
                            0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Start chatting with ${widget.conversation.organizationName}',
                          style: AppTheme.chatTitle.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _messagesScrollController,
                    padding: const EdgeInsets.all(16),
                    reverse: false,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isOwnMessage =
                          message.senderId == widget.currentUserId;
                      final senderName = _getMessageSenderName(message);
                      final shouldAnimate = _animatedMessageIds.contains(
                        message.id,
                      );

                      return AnimatedMessageWidget(
                        key: ValueKey(message.id),
                        message: message,
                        isOwnMessage: isOwnMessage,
                        senderName: senderName,
                        formatTime: _formatMessageTime,
                        shouldAnimate: shouldAnimate,
                        onAnimationComplete: () {
                          // Remove from animated set after animation completes
                          setState(() {
                            _animatedMessageIds.remove(message.id);
                          });
                        },
                      );
                    },
                  ),
          ),
          // Message input area
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.searchBarBackground,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: AppTheme.searchInput,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: AppTheme.searchInput.copyWith(
                        color: AppTheme.secondaryHeadingColor,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: AppTheme.headerBackground,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: AppTheme.accentPrimary,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
