// lib/modules/chat/direct_messages_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:mvc_app/modules/cars/vehicle_inquiry_chat_screen.dart';
import 'package:mvc_app/modules/cars/vehicle_inquiry_conversation.dart';
import 'package:mvc_app/modules/market/market_category.dart';
import 'package:mvc_app/modules/profile/profile_onboarding_screen.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/utils/profile_utils.dart';
import 'package:mvc_app/services/amplitude_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mvc_app/main_scaffold.dart';

/// Wraps either an org [DirectMessageConversation] or a Market-listing
/// [VehicleInquiryConversation] so both kinds of chats can be merged into a
/// single recency-sorted inbox list.
class _InboxEntry {
  final DirectMessageConversation? org;
  final VehicleInquiryConversation? vehicle;

  const _InboxEntry.org(DirectMessageConversation this.org) : vehicle = null;
  const _InboxEntry.vehicle(VehicleInquiryConversation this.vehicle)
      : org = null;

  DateTime get sortTime =>
      org?.lastMessage?.createdAt ??
      org?.updatedAt ??
      vehicle?.lastMessage?.createdAt ??
      vehicle?.updatedAt ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

class DirectMessagesScreen extends StatefulWidget {
  final String? initialOrganizationId;

  const DirectMessagesScreen({super.key, this.initialOrganizationId});

  @override
  DirectMessagesScreenState createState() => DirectMessagesScreenState();
}

/// Type alias for accessing DirectMessagesScreen state from MainScaffold
typedef _DirectMessagesScreenStateAccessor = DirectMessagesScreenState;

class DirectMessagesScreenState extends State<DirectMessagesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  DirectMessageConversation? _selectedConversation;
  bool _isNavigatingToChat = false;
  bool _isLoading = true;
  String? _errorMessage;
  bool _showSearchBar = false;
  
  List<DirectMessageConversation> _conversations = [];
  List<VehicleInquiryConversation> _vehicleInquiries = [];
  List<DirectMessageItem> _messages = [];
  StreamSubscription<List<DirectMessageConversation>>? _conversationsSubscription;
  StreamSubscription<List<DirectMessageItem>>? _messagesSubscription;
  String? _currentUserId;
  String? _currentConversationId; // Track which conversation's messages are loaded
  UserRole? _currentUserRole;
  Set<String> _managedOrganizationIds = {}; // Organizations the user can manage
  // Removed _userProfilesCache - user profiles are now included in conversation view
  Set<String> _animatedMessageIds = {}; // Track which messages have been animated
  final ScrollController _messagesScrollController = ScrollController();
  Map<String, DateTime> _lastReadTimes = {}; // Local read timestamps keyed by conversation ID

  // Rate limiting for markDirectMessagesAsRead
  DateTime? _lastMarkAsReadTime;
  static const Duration _markAsReadCooldown = Duration(seconds: 2);
  bool _isMarkingAsRead = false; // Prevent concurrent calls

  // ── In-app notification banner ──
  DirectMessageConversation? _bannerConversation;
  Timer? _bannerDismissTimer;
  final Map<String, String> _lastKnownMessageIds = {};
  bool _conversationsLoadedOnce = false;
  String? _openConversationId; // narrow-screen: ID of conversation open in pushed _ChatScreen

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterConversations);

    // Set currentUserId immediately and synchronously
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticatedState && authState.userProfile?.id != null) {
      _currentUserId = authState.userProfile!.id;
    }

    _loadLastReadTimes();
    _initializeScreen();
  }

  /// Opens a conversation with the specified organization
  /// Creates the conversation if it doesn't exist
  Future<void> openConversationWithOrganization(String organizationId) async {
    // Reset navigation flag so programmatic navigation is never blocked
    _isNavigatingToChat = false;

    // Ensure we have a current user ID
    if (_currentUserId == null) {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticatedState && authState.userProfile?.id != null) {
        _currentUserId = authState.userProfile!.id;
      } else {
        return;
      }
    }

    try {
      final apiRepository = context.read<ApiRepository>();
      final result = await apiRepository.createOrGetDirectMessageConversation(
        _currentUserId!,
        organizationId,
      );

      if (result.isSuccess && result.data != null && mounted) {
        final conversation = result.data!;
        final bool isWideScreen = MediaQuery.of(context).size.width >= 600;

        // Navigate immediately — don't await _loadConversations before opening the chat
        if (isWideScreen) {
          setState(() {
            _selectedConversation = conversation;
          });
          _loadMessages(conversation.id);
        } else {
          _saveLastReadTime(conversation.id);
          _navigateToChatView(conversation);
        }

        // Refresh conversations list in the background
        _loadConversations();
      }
    } catch (e) {
      print('Error opening conversation with organization: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting conversation: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Opens an existing conversation or creates a new one for [organizationId].
  /// For regular users this is identical to [openConversationWithOrganization].
  /// For admins/superadmins the org is already known so only a user-picker is
  /// shown; the conversation is then created on behalf of the chosen user.
  Future<void> openOrCreateConversation(String organizationId) async {
    if (_currentUserRole?.isAdminOrSuperAdmin != true) {
      // Regular-user path — reuse existing logic
      await openConversationWithOrganization(organizationId);
      return;
    }

    // Admin path: skip org selection (we know it), pick the target user.
    final selectedUsers = await context.showUserSelector(
      title: 'Select User',
      allowMultipleSelection: false,
      excludeUserIds: _currentUserId != null ? [_currentUserId!] : null,
    );

    if (selectedUsers == null || selectedUsers.isEmpty || !mounted) return;
    final selectedUser = selectedUsers.first;

    try {
      final apiRepository = context.read<ApiRepository>();
      final result = await apiRepository.createOrGetDirectMessageConversation(
        selectedUser.id,
        organizationId,
      );

      if (result.isSuccess && result.data != null && mounted) {
        final conversation = result.data!;
        final bool isWideScreen = MediaQuery.of(context).size.width >= 600;
        if (isWideScreen) {
          setState(() {
            _selectedConversation = conversation;
          });
          _loadMessages(conversation.id);
        } else {
          _saveLastReadTime(conversation.id);
          _navigateToChatView(conversation);
        }
        _loadConversations();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Failed to open conversation'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting conversation: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Opens an existing conversation by its ID
  /// Used when navigating from notifications (deeplinks)
  Future<void> openConversationById(String conversationId) async {
    // Reset navigation flag so deeplink navigation is never blocked
    _isNavigatingToChat = false;

    // Wait for conversations to be loaded if they aren't yet
    if (_conversations.isEmpty) {
      await _loadConversations();
    }

    // Find the conversation in the list
    final conversation = _conversations.firstWhere(
      (c) => c.id == conversationId,
      orElse: () => _conversations.first, // Fallback to first if not found
    );

    if (mounted) {
      final bool isWideScreen = MediaQuery.of(context).size.width >= 600;

      if (isWideScreen) {
        setState(() {
          _selectedConversation = conversation;
        });
        _loadMessages(conversation.id);
      } else {
        _saveLastReadTime(conversation.id);
        _navigateToChatView(conversation);
      }
    }
  }

  /// Load user role first, then load conversations
  /// This ensures admin users get the right conversations view
  Future<void> _initializeScreen() async {
    await _loadUserRoleAndOrganizations();
    await _loadConversations();

    // If an initial organization ID was provided, open that conversation
    if (widget.initialOrganizationId != null && _currentUserId != null) {
      // Small delay to ensure conversations are loaded
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          openConversationWithOrganization(widget.initialOrganizationId!);
        }
      });
    }
  }

  Future<void> _loadUserRoleAndOrganizations() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticatedState || authState.userProfile?.id == null) {
      return;
    }

    final userId = authState.userProfile!.id;

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
        final orgsResult = await apiRepository.getUserManagedOrganizations(userId);
        if (orgsResult.isSuccess && orgsResult.data != null) {
          setState(() {
            _managedOrganizationIds = orgsResult.data!.map((org) => org.id).toSet();
          });
        }
      }
    } catch (e) {
      print('Error loading user role and organizations: $e');
    }
  }

  @override
  void dispose() {
    _bannerDismissTimer?.cancel();
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

  /// Loads last-read timestamps from SharedPreferences
  Future<void> _loadLastReadTimes() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('dm_last_read_'));
    final times = <String, DateTime>{};
    for (final key in keys) {
      final value = prefs.getString(key);
      if (value != null) {
        final convId = key.replaceFirst('dm_last_read_', '');
        times[convId] = DateTime.parse(value);
      }
    }
    if (mounted) {
      setState(() {
        _lastReadTimes = times;
      });
    }
  }

  /// Saves the current time as the last-read timestamp for a conversation
  Future<void> _saveLastReadTime(String conversationId) async {
    final now = DateTime.now().toUtc();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dm_last_read_$conversationId', now.toIso8601String());
    if (mounted) {
      setState(() {
        _lastReadTimes[conversationId] = now;
      });
    }
  }

  /// Returns true if the conversation has a message newer than the last local read time
  bool _hasLocalUnread(DirectMessageConversation conversation) {
    final lastMessage = conversation.lastMessage;
    if (lastMessage == null) return false;
    // Never treat own messages as unread.
    // Admins send as the organization, so their messages have senderId != conversation.userId.
    // Regular users send with their own ID.
    final isAdmin = _currentUserRole?.isAdminOrSuperAdmin == true;
    final isOwnMessage = isAdmin
        ? lastMessage.createdBy != conversation.userId
        : lastMessage.createdBy == _currentUserId;
    if (isOwnMessage) return false;
    final lastRead = _lastReadTimes[conversation.id];
    if (lastRead == null) return conversation.hasUnreadMessages;
    return lastMessage.createdAt.isAfter(lastRead);
  }

  /// Get the display name for a message sender
  String _getMessageSenderName(DirectMessageItem message, DirectMessageConversation conversation) {
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
    if (authState is! AuthAuthenticatedState || authState.userProfile?.id == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Let\'s start messaging';
      });
      return;
    }

    _currentUserId = authState.userProfile!.id;
    if (_conversations.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    // Vehicle inquiries (buyer or seller side) load independently of org
    // conversations and merge into the same list once ready.
    _loadVehicleInquiries();

    try {
      final apiRepository = context.read<ApiRepository>();
      
      // Check if user is admin and has managed organizations
      final isAdmin = _currentUserRole?.isAdminOrSuperAdmin == true;
      final hasManagedOrgs = _managedOrganizationIds.isNotEmpty;
      
      if (isAdmin && hasManagedOrgs) {
        // Load conversations for organizations the admin manages
        final result = await apiRepository.getDirectMessageConversationsByOrganizations(
          _managedOrganizationIds.toList(),
        );
        
        if (result.isSuccess) {
          final conversations = result.data ?? [];

          // Seed tracked IDs so existing messages don't trigger banners
          _initializeTrackedMessageIds(conversations);

          // User profiles are now included in the view, no need to load separately
          setState(() {
            _conversations = conversations;
            _isLoading = false;
          });
          _conversationsLoadedOnce = true;

          // Set up real-time subscription for admin
          _conversationsSubscription?.cancel();
          _conversationsSubscription = apiRepository
              .streamDirectMessageConversationsByOrganizations(_managedOrganizationIds.toList())
              .listen((conversations) {
            if (mounted) {
              _onConversationsUpdated(conversations);
              // User profiles are included in the view, no need to load separately
              setState(() {
                _conversations = conversations;
              });
            }
          }, onError: (error) {
            print('Error in admin conversations stream: $error');
            // Optionally reconnect after a delay
            if (mounted) {
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  _loadConversations();
                }
              });
            }
          });
        } else {
          setState(() {
            _errorMessage = result.error ?? 'Failed to load conversations';
            _isLoading = false;
          });
        }
      } else {
        // Regular user: load conversations normally
        final result = await apiRepository.getDirectMessageConversations(_currentUserId!);
        
        if (result.isSuccess) {
          final conversations = result.data ?? [];

          // Seed tracked IDs so existing messages don't trigger banners
          _initializeTrackedMessageIds(conversations);

          setState(() {
            _conversations = conversations;
            _isLoading = false;
          });
          _conversationsLoadedOnce = true;

          // Set up real-time subscription
          _conversationsSubscription?.cancel();
          _conversationsSubscription = apiRepository
              .streamDirectMessageConversations(_currentUserId!)
              .listen((conversations) {
            if (mounted) {
              _onConversationsUpdated(conversations);
              setState(() {
                _conversations = conversations;
              });
            }
          }, onError: (error) {
            print('Error in conversations stream: $error');
            // Optionally reconnect after a delay
            if (mounted) {
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  _loadConversations();
                }
              });
            }
          });
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

  // Removed _loadUserProfilesForConversations - user profiles are now included in the view

  /// Loads Market inquiry conversations — vehicles and items, buyer or seller
  /// side — for the current user so they can be merged into the same inbox
  /// list as org DMs. Failures are silent — the org conversations list is the
  /// primary feature and shouldn't be blocked by this.
  Future<void> _loadVehicleInquiries() async {
    if (_currentUserId == null) return;
    try {
      final apiRepository = context.read<ApiRepository>();
      final result = await apiRepository.getListingInquiries();
      if (mounted && result.isSuccess) {
        setState(() {
          _vehicleInquiries = result.data ?? [];
        });
      }
    } catch (e) {
      print('Error loading vehicle inquiries: $e');
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
      if (_currentConversationId != null && _currentConversationId != conversationId) {
        _messagesSubscription?.cancel();
        _messagesSubscription = null;
      }
      
      // Clear messages when switching to a different conversation
      if (_currentConversationId != conversationId) {
        setState(() {
          _messages = [];
          _currentConversationId = conversationId;
          _animatedMessageIds.clear(); // Clear animated IDs when switching conversations
        });
      }
      
      // Load initial messages
      final result = await apiRepository.getDirectMessages(conversationId, limit: 50);
      
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
            .listen((messages) async {
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
            if (newMessages.length > previousMessageCount && _currentUserId != null) {
              // Check if there are unread messages from others
              final hasUnreadFromOthers = newMessages.any(
                (msg) => !msg.isRead && msg.senderId != _currentUserId,
              );
              
              if (hasUnreadFromOthers) {
                // Mark as read in the background with rate limiting
                _markMessagesAsReadDebounced(conversationId, _currentUserId!);
              }
            }
          }
        }, onError: (error) {
          print('Error in message stream: $error');
          // Optionally reconnect after a delay
          if (mounted && _currentConversationId == conversationId) {
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted && _currentConversationId == conversationId) {
                _loadMessages(conversationId);
              }
            });
          }
        });
      }
    } catch (e) {
      print('Error loading messages: $e');
    }
  }

  Future<void> _startNewConversation() async {
    final organization = await Navigator.push<Organization>(
      context,
      MaterialPageRoute(
        builder: (context) => const SelectOrganizationScreen(),
      ),
    );

    if (organization != null && _currentUserId != null) {
      try {
        final apiRepository = context.read<ApiRepository>();
        final result = await apiRepository.createOrGetDirectMessageConversation(
          _currentUserId!,
          organization.id,
        );

        if (result.isSuccess && result.data != null) {
          final conversation = result.data!;
          AmplitudeService.instance.logEvent('dm_conversation_started', eventProperties: {
            'organization_id': organization.id,
            'organization_name': organization.name,
            'role': 'user',
          });
          final bool isWideScreen = MediaQuery.of(context).size.width >= 600;
          if (isWideScreen) {
            setState(() {
              _selectedConversation = conversation;
            });
            _loadMessages(conversation.id);
          } else {
            _saveLastReadTime(conversation.id);
            _navigateToChatView(conversation);
          }
          // Refresh conversations list in background
          _loadConversations();
        } else {
          AmplitudeService.instance.logEvent('dm_conversation_start_error', eventProperties: {
            'organization_id': organization.id,
            'error': result.error ?? 'unknown',
            'role': 'user',
          });
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
        AmplitudeService.instance.logEvent('dm_conversation_start_error', eventProperties: {
          'organization_id': organization.id,
          'error': e.toString(),
          'role': 'user',
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
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
            content: Text('You need to manage at least one organization to start a conversation'),
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
      excludeUserIds: _currentUserId != null ? [_currentUserId!] : null, // Exclude current user (admin)
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

      if (result.isSuccess && result.data != null) {
        final conversation = result.data!;
        AmplitudeService.instance.logEvent('dm_conversation_started', eventProperties: {
          'organization_id': organization.id,
          'organization_name': organization.name,
          'role': 'admin',
        });
        final bool isWideScreen = MediaQuery.of(context).size.width >= 600;
        if (isWideScreen) {
          setState(() {
            _selectedConversation = conversation;
          });
          _loadMessages(conversation.id);
        } else {
          _saveLastReadTime(conversation.id);
          _navigateToChatView(conversation);
        }
        // Refresh conversations list in background
        _loadConversations();
      } else {
        AmplitudeService.instance.logEvent('dm_conversation_start_error', eventProperties: {
          'organization_id': organization.id,
          'error': result.error ?? 'unknown',
          'role': 'admin',
        });
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
      AmplitudeService.instance.logEvent('dm_conversation_start_error', eventProperties: {
        'organization_id': organization.id,
        'error': e.toString(),
        'role': 'admin',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendMessage([String? conversationId]) async {
    final targetConversationId = conversationId ?? _selectedConversation?.id;
    if (targetConversationId == null || _currentUserId == null) {
      print('Cannot send message: conversationId=$targetConversationId, userId=$_currentUserId');
      return;
    }
    if (_messageController.text.trim().isEmpty) return;

    // Check if profile needs completion before sending message
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticatedState) {
      final userProfile = authState.userProfile;
      if (ProfileUtils.needsProfileCompletion(userProfile)) {
        // Show onboarding screen
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ProfileOnboardingScreen(),
          ),
        );
        // Don't send the message - user needs to complete profile first
        return;
      }
    }

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

  // ── Banner helpers ──

  /// Seeds [_lastKnownMessageIds] from an initial load so pre-existing messages
  /// never trigger a banner on first render.
  void _initializeTrackedMessageIds(List<DirectMessageConversation> conversations) {
    for (final conv in conversations) {
      final msgId = conv.lastMessage?.id;
      if (msgId != null) _lastKnownMessageIds[conv.id] = msgId;
    }
  }

  /// Called on every realtime conversations update. Shows a banner when a new
  /// message arrives in a conversation the user is NOT currently viewing.
  void _onConversationsUpdated(List<DirectMessageConversation> incoming) {
    if (!_conversationsLoadedOnce) return;

    for (final conv in incoming) {
      final newMsgId = conv.lastMessage?.id;
      if (newMsgId == null) continue;

      // Already seen this message — no change
      if (_lastKnownMessageIds[conv.id] == newMsgId) continue;

      // Register the new ID so it isn't re-shown
      _lastKnownMessageIds[conv.id] = newMsgId;

      // Don't notify the sender about their own message
      if (conv.lastMessage?.createdBy == _currentUserId) continue;

      // Don't show banner for the conversation the user is currently viewing
      final currentlyViewingId = _openConversationId ?? _selectedConversation?.id;
      if (currentlyViewingId == conv.id) continue;

      // If the user is not on the DM tab, delegate to the global banner so it
      // remains visible on top of whichever tab is currently active.
      final onDMTab = mainScaffoldKey.currentState?.selectedTabIndex == 1;
      if (!onDMTab) {
        final isAdmin = _currentUserRole?.isAdminOrSuperAdmin == true;
        final displayName = isAdmin
            ? (conv.userFullName ?? conv.userUsername ?? 'User')
            : conv.organizationName;
        mainScaffoldKey.currentState?.showDMBanner(
          title: displayName,
          body: conv.lastMessage?.displayContent ?? '',
          conversationId: conv.id,
        );
      } else {
        _showBanner(conv);
      }
      return; // One banner at a time
    }
  }

  void _showBanner(DirectMessageConversation conversation) {
    _bannerDismissTimer?.cancel();
    setState(() => _bannerConversation = conversation);
    _bannerDismissTimer = Timer(const Duration(seconds: 4), _dismissBanner);
  }

  void _dismissBanner() {
    _bannerDismissTimer?.cancel();
    _bannerDismissTimer = null;
    if (mounted) setState(() => _bannerConversation = null);
  }

  Widget _buildInAppBannerOverlay() {
    final isAdmin = _currentUserRole?.isAdminOrSuperAdmin == true;
    final conv = _bannerConversation;

    final displayName = conv == null
        ? ''
        : isAdmin
            ? (conv.userFullName ?? conv.userUsername ?? 'User')
            : conv.organizationName;

    final logoUrl = conv == null
        ? null
        : isAdmin
            ? conv.userProfilePictureUrl
            : conv.organizationLogoUrl;

    final preview = conv?.lastMessage?.displayContent ?? '';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: conv != null
          ? _InAppDMBanner(
              key: ValueKey(conv.id),
              displayName: displayName,
              logoUrl: logoUrl,
              messagePreview: preview,
              onDismiss: _dismissBanner,
              onTap: () {
                final target = conv;
                _dismissBanner();
                final wide = MediaQuery.of(context).size.width >= 600;
                if (wide) {
                  _saveLastReadTime(target.id);
                  setState(() => _selectedConversation = target);
                  _loadMessages(target.id);
                } else {
                  _navigateToChatView(target);
                }
              },
            )
          : const SizedBox.shrink(key: ValueKey('_banner_empty')),
    );
  }

  List<DirectMessageConversation> get _filteredConversations {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      return _conversations;
    }
    
    final isAdmin = _currentUserRole?.isAdminOrSuperAdmin == true;
    
    if (isAdmin) {
      // For admins, search by user name (from conversation view)
      return _conversations.where((conv) {
        final userName = conv.userFullName ?? conv.userUsername ?? '';
        return userName.toLowerCase().contains(query);
      }).toList();
    } else {
      // For regular users, search by organization name
      return _conversations
          .where((conv) => conv.organizationName.toLowerCase().contains(query))
          .toList();
    }
  }

  List<VehicleInquiryConversation> get _filteredVehicleInquiries {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) return _vehicleInquiries;

    return _vehicleInquiries.where((conv) {
      final otherName = conv.counterpartyName(_currentUserId);
      return otherName.toLowerCase().contains(query) ||
          conv.listingTitle.toLowerCase().contains(query);
    }).toList();
  }

  /// Org DMs and vehicle inquiries merged and sorted by most recent activity,
  /// for the plain (non-grouped-by-org) inbox list.
  List<_InboxEntry> get _inboxEntries {
    final entries = <_InboxEntry>[
      ..._filteredConversations.map(_InboxEntry.org),
      ..._filteredVehicleInquiries.map(_InboxEntry.vehicle),
    ];
    entries.sort((a, b) => b.sortTime.compareTo(a.sortTime));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final bool isWideScreen = MediaQuery.of(context).size.width >= 600;
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 32),
        backgroundColor: AppTheme.headerBackground,
        foregroundColor: AppTheme.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              setState(() {
                _showSearchBar = !_showSearchBar;
                if (!_showSearchBar) _searchController.clear();
              });
            },
          ),
          SizedBox(width: 14),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            color: AppTheme.accentPrimary,
            iconSize: 28,
            onPressed: _currentUserRole?.isAdminOrSuperAdmin == true
                ? _startNewConversationAsAdmin
                : _startNewConversation,
          ),
          SizedBox(width: 10),
        ],
      ),
      body: Stack(
        children: [
          isWideScreen ? _buildWideScreenLayout() : _buildNarrowScreenLayout(),
          _buildInAppBannerOverlay(),
        ],
      ),
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
    // On narrow screens always show the conversations list.
    // Chat views are opened via Navigator.push in _navigateToChatView.
    return _buildConversationsList();
  }

  void _navigateToChatView(DirectMessageConversation conversation) {
    if (_isNavigatingToChat) return; // Prevent double navigation
    _isNavigatingToChat = true;
    _openConversationId = conversation.id;
    _dismissBanner();

    AmplitudeService.instance.logEvent('dm_chat_opened', eventProperties: {
      'conversation_id': conversation.id,
      'organization_id': conversation.organizationId,
      'organization_name': conversation.organizationName,
    });

    // Mark as read immediately so the unread dot clears right away
    _saveLastReadTime(conversation.id);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ChatScreen(
          conversation: conversation,
          currentUserId: _currentUserId,
          currentUserRole: _currentUserRole,
          onBack: () {
            Navigator.pop(context);
          },
        ),
      ),
    ).then((_) {
      _openConversationId = null;
      _isNavigatingToChat = false;
      AmplitudeService.instance.logEvent('dm_chat_closed', eventProperties: {
        'conversation_id': conversation.id,
        'organization_id': conversation.organizationId,
      });
      // Clean up messages when returning from chat
      setState(() {
        _messages = [];
        _currentConversationId = null;
        _animatedMessageIds.clear();
        _messagesSubscription?.cancel();
        _messagesSubscription = null;
      });
      // Refresh the conversations list so last message / timestamps are current
      _loadConversations();
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
              child: const Text('Continue', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    final conversations = _filteredConversations;
    final inboxEntries = _inboxEntries;

    return Column(
      children: [
        // Search bar (toggled by search icon in AppBar)
        if (_showSearchBar)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              autofocus: true,
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
                suffixIcon: IconButton(
                  icon: Icon(
                    Icons.close,
                    color: AppTheme.secondaryHeadingColor,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _showSearchBar = false;
                    });
                  },
                ),
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
          child: inboxEntries.isEmpty
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
                  child: _currentUserRole?.isAdminOrSuperAdmin == true &&
                          _managedOrganizationIds.length > 1
                      ? _buildGroupedConversationsList(conversations)
                      : ListView.separated(
                          itemCount: inboxEntries.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            color: AppTheme.dividerBackground,
                          ),
                          itemBuilder: (context, index) {
                            final entry = inboxEntries[index];
                            return entry.org != null
                                ? _buildConversationTile(entry.org!)
                                : _buildVehicleInquiryTile(entry.vehicle!);
                          },
                        ),
                ),
        ),
      ],
    );
  }

  Widget _buildConversationTile(DirectMessageConversation conversation) {
    final isSelected = _selectedConversation?.id == conversation.id;
    final isAdmin = _currentUserRole?.isAdminOrSuperAdmin == true;

    final displayName = isAdmin
        ? (conversation.userFullName ?? conversation.userUsername ?? 'User')
        : conversation.organizationName;
    final displayLogoUrl = isAdmin
        ? conversation.userProfilePictureUrl
        : conversation.organizationLogoUrl;

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
          HapticFeedback.selectionClick();
          _dismissBanner();
          final bool isWideScreen = MediaQuery.of(context).size.width >= 600;
          if (isWideScreen) {
            _saveLastReadTime(conversation.id);
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
          color: isSelected ? AppTheme.cardGreyBackground : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildChannelAvatar(directMessage),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                        if (conversation.lastMessage != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            conversation.lastMessage!.timeDisplay,
                            style: AppTheme.chatTimestamp,
                          ),
                        ],
                        if (_hasLocalUnread(conversation)) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppTheme.accentPrimary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accentPrimary.withOpacity(0.3),
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
                            conversation.lastMessage!.displayContent,
                            style: AppTheme.chatMessage.copyWith(
                              color: AppTheme.secondaryHeadingColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : Text(
                            'No messages yet',
                            style: AppTheme.chatMessage.copyWith(
                              fontStyle: FontStyle.italic,
                              color: AppTheme.secondaryHeadingColor,
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
  }

  Widget _buildGroupedConversationsList(List<DirectMessageConversation> conversations) {
    final Map<String, List<DirectMessageConversation>> grouped = {};
    final Map<String, String> orgNames = {};

    for (final conv in conversations) {
      grouped.putIfAbsent(conv.organizationId, () => []).add(conv);
      orgNames[conv.organizationId] = conv.organizationName;
    }

    final sortedOrgIds = grouped.keys.toList()
      ..sort((a, b) => (orgNames[a] ?? '').compareTo(orgNames[b] ?? ''));

    // Market inquiries aren't tied to any managed organization (listings
    // belong to the admin personally), so they get their own trailing group
    // sorted by most recent activity, same as the plain inbox list.
    final vehicleEntries = _filteredVehicleInquiries.toList()
      ..sort((a, b) {
        final aTime = a.lastMessage?.createdAt ?? a.updatedAt;
        final bTime = b.lastMessage?.createdAt ?? b.updatedAt;
        return bTime.compareTo(aTime);
      });

    return ListView(
      children: [
        for (final orgId in sortedOrgIds) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(orgNames[orgId] ?? orgId, style: AppTheme.managementHeading),
          ),
          ...grouped[orgId]!.map(_buildConversationTile),
          const Divider(height: 1, color: AppTheme.dividerBackground),
        ],
        if (vehicleEntries.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text('Market Inquiries', style: AppTheme.managementHeading),
          ),
          ...vehicleEntries.map(_buildVehicleInquiryTile),
          const Divider(height: 1, color: AppTheme.dividerBackground),
        ],
      ],
    );
  }

  /// Tile for a Market inquiry (vehicle or item), styled to match
  /// [_buildConversationTile] with an extra line for which listing it's
  /// about (the org tile has no such ambiguity — a DM only concerns one org).
  Widget _buildVehicleInquiryTile(VehicleInquiryConversation conversation) {
    final otherName = conversation.counterpartyName(_currentUserId);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          _dismissBanner();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  VehicleInquiryChatScreen(conversation: conversation),
            ),
          ).then((_) => _loadVehicleInquiries());
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _buildVehicleAvatar(conversation),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            otherName,
                            style: AppTheme.chatTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (conversation.lastMessage != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            conversation.lastMessage!.timeDisplay,
                            style: AppTheme.chatTimestamp,
                          ),
                        ],
                        if (conversation.hasUnreadMessages) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppTheme.accentPrimary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accentPrimary.withOpacity(0.3),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(_listingIcon(conversation),
                            size: 12, color: AppTheme.secondaryHeadingColor),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            conversation.listingTitle,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.secondaryHeadingColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      conversation.lastMessage?.displayContent ?? 'No messages yet',
                      style: AppTheme.chatMessage.copyWith(
                        color: AppTheme.secondaryHeadingColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVehicleAvatar(VehicleInquiryConversation conversation) {
    final imageUrl = conversation.listingImageUrl;
    if (imageUrl != null &&
        imageUrl.isNotEmpty &&
        Uri.tryParse(imageUrl) != null) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.accentPrimary.withOpacity(0.12),
        backgroundImage: CachedNetworkImageProvider(imageUrl),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: AppTheme.accentPrimary.withOpacity(0.15),
      child: Icon(_listingIcon(conversation),
          color: AppTheme.accentPrimary, size: 20),
    );
  }

  IconData _listingIcon(VehicleInquiryConversation conversation) =>
      conversation.isMarketItem
          ? MarketCategory.iconFor(conversation.listingCategory)
          : Icons.directions_car;

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
                ? (isAdmin ? "No messages from users yet" : "No direct messages yet")
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
      children: [
        Expanded(
          child: _buildChatViewContent(conversation),
        ),
      ],
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
        if (mounted && (_currentConversationId != conversation.id || _messages.isEmpty)) {
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
                            ? 'Start chatting with ${conversation.userFullName ?? conversation.userUsername ?? "User"}'
                            : 'Start chatting with ${conversation.organizationName}',
                        style: AppTheme.chatTitle.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              : Builder(builder: (context) {
                  final chatItems = _buildChatItems(_messages);
                  final userName = conversation.userFullName ?? conversation.userUsername ?? 'User';
                  return ListView.builder(
                    controller: _messagesScrollController,
                    padding: const EdgeInsets.all(16),
                    reverse: false,
                    itemCount: chatItems.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _ConversationStartBanner(
                          userName: userName,
                          organizationName: conversation.organizationName,
                        );
                      }
                      final item = chatItems[index - 1];
                      if (item is DateTime) {
                        return _ChatDateBanner(date: item);
                      }
                      final message = item as DirectMessageItem;
                      final isOwnMessage = _currentUserRole?.isAdminOrSuperAdmin == true
                          ? message.senderId != conversation.userId
                          : message.senderId == _currentUserId;
                      final senderName = _getMessageSenderName(message, conversation);
                      final shouldAnimate = _animatedMessageIds.contains(message.id);
                      return AnimatedMessageWidget(
                        key: ValueKey(message.id),
                        message: message,
                        isOwnMessage: isOwnMessage,
                        senderName: senderName,
                        formatTime: _formatMessageTime,
                        shouldAnimate: shouldAnimate,
                        onAnimationComplete: () {
                          setState(() {
                            _animatedMessageIds.remove(message.id);
                          });
                        },
                      );
                    },
                  );
                }),
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
                  icon: const Icon(
                    Icons.send,
                    color: Colors.white,
                    size: 20,
                  ),
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
    apiRepository.markDirectMessagesAsRead(conversationId, userId).then(
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

/// Formats a UTC [DateTime] as a human-readable date label for chat separators,
/// mirroring the bucketing logic of [_formatMessageTime].
String _formatDateLabel(DateTime utcDate) {
  final local = utcDate.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final msgDay = DateTime(local.year, local.month, local.day);
  final diff = today.difference(msgDay).inDays;

  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) {
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return weekdays[local.weekday - 1];
  }
  return '${local.month}/${local.day}/${local.year}';
}

/// Builds a flat list of chat items interspersed with date-separator [DateTime]s.
/// Each [DateTime] entry represents the local calendar day of the messages that follow.
List<Object> _buildChatItems(List<DirectMessageItem> messages) {
  final items = <Object>[];
  DateTime? lastDay;
  for (final message in messages) {
    final local = message.createdAt.toLocal();
    final msgDay = DateTime(local.year, local.month, local.day);
    if (lastDay == null || msgDay != lastDay) {
      items.add(msgDay);
      lastDay = msgDay;
    }
    items.add(message);
  }
  return items;
}

/// WhatsApp-style banner shown at the very top of a conversation's message list.
class _ConversationStartBanner extends StatelessWidget {
  final String userName;
  final String organizationName;

  const _ConversationStartBanner({
    required this.userName,
    required this.organizationName,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          decoration: BoxDecoration(
            color: AppTheme.secondaryHeadingColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'This is the start of the conversation between $userName and $organizationName',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.secondaryHeadingColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact date-pill separator shown between messages on different calendar days.
class _ChatDateBanner extends StatelessWidget {
  final DateTime date;

  const _ChatDateBanner({required this.date});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.secondaryHeadingColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _formatDateLabel(date),
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.secondaryHeadingColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Slide-down banner shown at the top of the DM screen when a new message
/// arrives in a conversation the user is not currently viewing.
class _InAppDMBanner extends StatelessWidget {
  final String displayName;
  final String? logoUrl;
  final String messagePreview;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _InAppDMBanner({
    super.key,
    required this.displayName,
    required this.logoUrl,
    required this.messagePreview,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    _buildAvatar(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: AppTheme.black,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            messagePreview,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.secondaryHeadingColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onDismiss,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: AppTheme.secondaryHeadingColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    if (logoUrl != null && logoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundImage: CachedNetworkImageProvider(logoUrl!),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: 20,
      backgroundColor: AppTheme.accentPrimary.withOpacity(0.15),
      child: Text(
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
        style: TextStyle(
          color: AppTheme.accentPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    );
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
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    // Fade animation - starts quickly
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );

    // Scale animation with a smooth spring-like effect
    _scaleAnimation = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );

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
      alignment: widget.isOwnMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
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
                      color: widget.isOwnMessage ? Colors.white : AppTheme.black,
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
  // Removed userProfilesCache - user profiles are now included in conversation view

  const _ChatScreen({
    required this.conversation,
    required this.currentUserId,
    required this.onBack,
    this.currentUserRole,
  });

  @override
  State<_ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<_ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  List<DirectMessageItem> _messages = [];
  StreamSubscription<List<DirectMessageItem>>? _messagesSubscription;
  String? _currentConversationId;
  Set<String> _animatedMessageIds = {}; // Track which messages have been animated
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
          _animatedMessageIds.clear(); // Clear animated IDs when switching conversations
        });
      }
      
      // Load initial messages
      final result = await apiRepository.getDirectMessages(conversationId, limit: 50);
      
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
            .listen((messages) async {
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
            if (newMessages.length > previousMessageCount && widget.currentUserId != null) {
              // Check if there are unread messages from others
              final hasUnreadFromOthers = newMessages.any(
                (msg) => !msg.isRead && msg.senderId != widget.currentUserId,
              );

              if (hasUnreadFromOthers) {
                // Mark as read in the background with rate limiting
                _markMessagesAsReadDebounced(conversationId, widget.currentUserId!);
              }
            }
          }
        }, onError: (error) {
          print('Error in message stream: $error');
          // Optionally reconnect after a delay
          if (mounted && _currentConversationId == conversationId) {
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted && _currentConversationId == conversationId) {
                _loadMessages();
              }
            });
          }
        });
      }
    } catch (e) {
      print('Error loading messages: $e');
    }
  }

  Future<void> _sendMessage() async {
    final conversationId = widget.conversation.id;
    if (widget.currentUserId == null) {
      print('Cannot send message: conversationId=$conversationId, userId=${widget.currentUserId}');
      return;
    }
    if (_messageController.text.trim().isEmpty) return;

    // Check if profile needs completion before sending message
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticatedState) {
      final userProfile = authState.userProfile;
      if (ProfileUtils.needsProfileCompletion(userProfile)) {
        // Show onboarding screen
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ProfileOnboardingScreen(),
          ),
        );
        // Don't send the message - user needs to complete profile first
        return;
      }
    }

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
    apiRepository.markDirectMessagesAsRead(conversationId, userId).then(
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
              ? (widget.conversation.userFullName ??
                 widget.conversation.userUsername ??
                 'User')
              : widget.conversation.organizationName,
          style: AppTheme.chatTitle,
        ),
        backgroundColor: AppTheme.headerBackground,
        foregroundColor: AppTheme.black,
        elevation: 0,
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
                          color: AppTheme.secondaryHeadingColor.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.currentUserRole?.isAdminOrSuperAdmin == true
                              ? 'Start chatting with ${widget.conversation.userFullName ?? widget.conversation.userUsername ?? "User"}'
                              : 'Start chatting with ${widget.conversation.organizationName}',
                          style: AppTheme.chatTitle.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : Builder(builder: (context) {
                    final chatItems = _buildChatItems(_messages);
                    final userName = widget.conversation.userFullName ?? widget.conversation.userUsername ?? 'User';
                    return ListView.builder(
                      controller: _messagesScrollController,
                      padding: const EdgeInsets.all(16),
                      reverse: false,
                      itemCount: chatItems.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _ConversationStartBanner(
                            userName: userName,
                            organizationName: widget.conversation.organizationName,
                          );
                        }
                        final item = chatItems[index - 1];
                        if (item is DateTime) {
                          return _ChatDateBanner(date: item);
                        }
                        final message = item as DirectMessageItem;
                        final isOwnMessage = widget.currentUserRole?.isAdminOrSuperAdmin == true
                            ? message.senderId != widget.conversation.userId
                            : message.senderId == widget.currentUserId;
                        final senderName = _getMessageSenderName(message);
                        final shouldAnimate = _animatedMessageIds.contains(message.id);
                        return AnimatedMessageWidget(
                          key: ValueKey(message.id),
                          message: message,
                          isOwnMessage: isOwnMessage,
                          senderName: senderName,
                          formatTime: _formatMessageTime,
                          shouldAnimate: shouldAnimate,
                          onAnimationComplete: () {
                            setState(() {
                              _animatedMessageIds.remove(message.id);
                            });
                          },
                        );
                      },
                    );
                  }),
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
                    icon: const Icon(
                      Icons.send,
                      color: Colors.white,
                      size: 20,
                    ),
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

