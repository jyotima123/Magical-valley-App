// lib/modules/chat/real_chat_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/channels/organization_profile_screen.dart';
import 'package:mvc_app/modules/chat/models/chat_channel.dart';
import 'package:mvc_app/modules/chat/chat_bloc.dart';
import 'package:mvc_app/modules/chat/chat_service.dart';
import 'package:mvc_app/services/first_run_service.dart';
import 'package:mvc_app/main_scaffold.dart';
import 'package:mvc_app/utils/chat_menu_actions.dart';
import 'package:mvc_app/services/amplitude_service.dart';

// Import the new widget files
import 'widgets/chat_app_bar.dart';
import 'widgets/chat_view.dart';
import 'widgets/channels_list.dart';

class RealChatScreen extends StatefulWidget {
  final String? organizationId;

  const RealChatScreen({super.key, this.organizationId});

  @override
  State<RealChatScreen> createState() => _RealChatScreenState();
}

class _RealChatScreenState extends State<RealChatScreen>
    with WidgetsBindingObserver {
  // Controllers
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  // Breakpoint for responsive design
  static const double _breakpoint = 600;

  // Flags
  bool _isNavigatingToChat = false; // Flag to prevent recursive navigation

  AppThemeMode theme = AppThemeMode.light;

  // New state variables for filtering
  bool showBottomNavigation = false;
  bool showSearchBar = false; // Changed default to false

  // Track the previously selected channel to detect changes
  String? _previouslySelectedChannelId;

  // Track previous auth state to detect login
  bool _wasAuthenticated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _searchController.addListener(_onSearchChanged);
    context.read<AuthBloc>().add(CheckAuthStatusEvent());
    context.read<ChatBloc>().add(LoadChannelsEvent());

    // Check initial auth state
    final authState = context.read<AuthBloc>().state;
    _wasAuthenticated = authState is AuthAuthenticatedState;

    // If an organization ID is provided, select its channel after channels are loaded
    if (widget.organizationId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Wait for channels to load, then select the organization's channel
        _selectOrganizationChannel();
      });
    }

    // Scroll logic is now handled by ChatView widget
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowFirstTimeHint();
      // Update badge when screen first becomes visible
      _updateBadgeOnScreenVisible();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _messagesScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When app becomes visible/resumed, update badge based on current unread count
    if (state == AppLifecycleState.resumed) {
      _updateBadgeOnScreenVisible();
    }
  }

  /// Update notification badge when screen becomes visible
  /// This ensures the badge reflects the current unread count when viewing chats
  Future<void> _updateBadgeOnScreenVisible() async {
    if (!mounted) return;

    final chatState = context.read<ChatBloc>().state;
    if (chatState is ChatLoadedState) {
      // Update badge based on current unread channel count
      await ChatService.updateNotificationBadgeFromChannels(
        chatState.allChannels,
      );
      print('🔍 RealChatScreen: Updated badge on screen visible');
    }
  }

  void _onSearchChanged() {
    // Dispatch search filter event to ChatBloc
    context.read<ChatBloc>().add(SetSearchFilterEvent(_searchController.text));
    setState(() {});
  }

  Future<void> _maybeShowFirstTimeHint() async {
    await FirstRunService.instance.maybeShowHint(
      context,
      key: FirstRunHintKeys.chatFollow,
      icon: Icons.explore,
    );
  }

  // Method to select organization channel
  void _selectOrganizationChannel() {
    // Use a timer to check for channels after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && widget.organizationId != null) {
        final chatState = context.read<ChatBloc>().state;
        if (chatState is ChatLoadedState && chatState.allChannels.isNotEmpty) {
          // Check if we haven't already selected this organization's channel
          if (chatState.selectedChannel?.organizationId !=
              widget.organizationId) {
            context.read<ChatBloc>().add(
              SelectChannelByOrganizationIdEvent(widget.organizationId!),
            );
          }
        } else {
          // If channels are not loaded yet, try again after another delay
          _selectOrganizationChannel();
        }
      }
    });
  }

  // Method to navigate to chat view on mobile
  void _navigateToChatView(ChatChannel channel) {
    // Set navigation flag to prevent recursive calls
    _isNavigatingToChat = true;

    AmplitudeService.instance.logEvent(
      'chat_opened',
      eventProperties: {
        'channel_id': channel.id,
        'channel_name': channel.name,
        'organization_id': channel.organizationId,
      },
    );

    // Provide subtle haptic feedback when opening a chat (Android & iOS)
    HapticFeedback.selectionClick();

    // Note: SelectChannelEvent was already dispatched when user tapped the channel
    // No need to dispatch it again here

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: GestureDetector(
              onTap: () => {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OrganizationProfileScreen(
                      organizationId: channel.organizationId,
                    ),
                  ),
                ).then((wasUnfollowed) {
                  if (wasUnfollowed == true) {
                    // Reload channels - this will automatically filter out unfollowed channels
                    // and clear the selected channel if it was the one that was unfollowed
                    context.read<ChatBloc>().add(LoadChannelsEvent());
                  }
                }),
              },
              child: Text(
                channel.name,
                style: TextStyle(
                  color: (theme != AppThemeMode.dark)
                      ? AppTheme.darkBottomBarBackground
                      : AppTheme.cardGreyBackground,
                ),
              ),
            ),
            backgroundColor: (theme == AppThemeMode.dark)
                ? AppTheme.darkBottomBarBackground
                : AppTheme.cardGreyBackground,
          ),
          body: BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              if (state is ChatLoadedState) {
                return ChatView(
                  messageController: TextEditingController(),
                  messagesScrollController: ScrollController(),
                  theme: theme,
                );
              }
              return const Center(child: CircularProgressIndicator());
            },
          ),
        ),
      ),
    ).then((_) {
      // Save post views when returning from chat view (mobile navigation)
      if (_previouslySelectedChannelId != null) {
        ChatView.savePostViewsForChannel(_previouslySelectedChannelId, context);
      }

      AmplitudeService.instance.logEvent(
        'chat_closed',
        eventProperties: {
          'channel_id': channel.id,
          'channel_name': channel.name,
          'organization_id': channel.organizationId,
        },
      );

      // Reset navigation flags when returning from chat view
      _isNavigatingToChat = false;
      context.read<ChatBloc>().add(ClearSelectedChannelEvent());
      // Reset the previously selected channel so user can tap same channel again
      _previouslySelectedChannelId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, authState) {
        // When user becomes authenticated, reload channels to update badge
        final isAuthenticated = authState is AuthAuthenticatedState;
        if (isAuthenticated && !_wasAuthenticated) {
          // User just logged in - reload channels to update badge with unread status
          context.read<ChatBloc>().add(LoadChannelsEvent());
        }
        _wasAuthenticated = isAuthenticated;
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, authState) {
          return Scaffold(
            appBar: ChatAppBar(
              showSearchBar: showSearchBar,
              onToggleSearchBar: () {
                setState(() {
                  showSearchBar = !showSearchBar;
                });
                _onSearchChanged();
              },
              theme: theme,
              searchController: _searchController,
              selectedTabIndex: 0, // Channels is always at index 0
              onChannelsTabTap: () {}, // Not used in this screen anymore
              onCategoriesTabTap: () {}, // Not used in this screen anymore
              onManageTabTap: () {}, // Not used in this screen anymore
              onCreateOrganization: () => handleCreateOrganization(context),
              onCreatePost: (selectedChannel, userId) =>
                  handleCreatePost(context, selectedChannel, userId),
              onLogout: () => handleLogout(context),
              showBottomNavigation: showBottomNavigation,
              onLogoTap: () {
                setState(() {
                  showBottomNavigation = !showBottomNavigation;
                });
              },
            ),
            body: BlocConsumer<ChatBloc, ChatState>(
              listener: (context, state) {
                if (state is ChatLoadedState && state.error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.error!),
                      backgroundColor: Colors.red,
                    ),
                  );
                }

                // Update notification badge whenever channels are loaded
                // This ensures badge is updated even if channels were loaded before authentication
                if (state is ChatLoadedState) {
                  // Update badge based on unread channel count
                  // This will set badge to 0 if no unread channels, clearing it on iOS
                  ChatService.updateNotificationBadgeFromChannels(
                    state.allChannels,
                  );
                }

                // Navigate to chat view on mobile ONLY when selected channel actually changes
                // (not on every state rebuild like search filter changes)
                // Check this BEFORE saving post views to ensure navigation happens
                if (state is ChatLoadedState &&
                    state.selectedChannel != null &&
                    MediaQuery.of(context).size.width < _breakpoint &&
                    !_isNavigatingToChat &&
                    state.selectedChannel!.id != _previouslySelectedChannelId) {
                  print(
                    '📱 Navigating to chat: channelId=${state.selectedChannel!.id}, previousChannelId=$_previouslySelectedChannelId',
                  );
                  // Save post views from previous channel before switching
                  if (_previouslySelectedChannelId != null) {
                    ChatView.savePostViewsForChannel(
                      _previouslySelectedChannelId,
                      context,
                    );
                  }

                  // Update the tracked channel BEFORE navigating to prevent loops
                  _previouslySelectedChannelId = state.selectedChannel!.id;
                  _navigateToChatView(state.selectedChannel!);
                }

                // Save post views when channel changes or is cleared (for desktop/tablet mode)
                if (state is ChatLoadedState) {
                  final currentChannelId = state.selectedChannel?.id;

                  // If channel changed (including when cleared to null) and we're not navigating
                  // (navigation already handled post views saving above)
                  if (!_isNavigatingToChat &&
                      _previouslySelectedChannelId != currentChannelId) {
                    // Save post views from previous channel before switching
                    if (_previouslySelectedChannelId != null) {
                      ChatView.savePostViewsForChannel(
                        _previouslySelectedChannelId,
                        context,
                      );
                    }

                    // Update tracked channel ID
                    _previouslySelectedChannelId = currentChannelId;
                  }
                }
              },
              builder: (context, state) {
                if (state is ChatLoadingState) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is ChatErrorState) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Error: ${state.error}'),
                        ElevatedButton(
                          onPressed: () {
                            context.read<ChatBloc>().add(LoadChannelsEvent());
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                // Only show Channels content now
                if (state is ChatLoadedState) {
                  final bool isWideScreen =
                      MediaQuery.of(context).size.width >= _breakpoint;
                  return isWideScreen
                      ? _buildWideScreenLayout(state)
                      : _buildNarrowScreenLayout(state);
                }
                return const Center(child: Text('Loading channels...'));
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildWideScreenLayout(ChatLoadedState state) {
    return Row(
      children: [
        SizedBox(
          width: MediaQuery.of(context).size.width * 0.35,
          child: ChannelsList(
            searchController: _searchController,
            breakpoint: _breakpoint,
            theme: theme,
            onExplorePressed: () {
              // Switch to Explore tab using MainScaffold
              mainScaffoldKey.currentState?.switchToExploreTab();
            },
          ),
        ),
        const VerticalDivider(
          width: 1,
          thickness: 1,
          color: AppTheme.dividerBackground,
        ),
        Expanded(
          child: state.selectedChannel != null
              ? ChatView(
                  messageController: _messageController,
                  messagesScrollController: _messagesScrollController,
                  theme: theme,
                )
              : const Center(child: Text('Select a channel to start chatting')),
        ),
      ],
    );
  }

  Widget _buildNarrowScreenLayout(ChatLoadedState state) {
    // TODO: This is not taking into account back button behaviour
    // If a channel is selected, show the chat view
    // if (state.selectedChannel != null) {
    //   return ChatView(
    //     messageController: _messageController,
    //     messagesScrollController: _messagesScrollController,
    //     theme: theme,
    //   );
    // }

    // Otherwise show the channels list
    return ChannelsList(
      searchController: _searchController,
      breakpoint: _breakpoint,
      theme: theme,
      onExplorePressed: () {
        // Switch to Explore tab using MainScaffold
        mainScaffoldKey.currentState?.switchToExploreTab();
      },
    );
  }
}
