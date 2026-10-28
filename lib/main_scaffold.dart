// main_scaffold.dart - Persistent bottom navigation wrapper for all authenticated screens
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mvc_app/testability/screen_state.dart';
import 'package:mvc_app/testability/screen_state_registry.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/chat/real_chat_scree.dart';
import 'package:mvc_app/modules/chat/direct_messages_screen.dart';
import 'package:mvc_app/modules/channels/categories_grid_screen.dart';
import 'package:mvc_app/modules/market/market_screen.dart';
import 'package:mvc_app/modules/cars/vehicle_inquiry_chat_screen.dart';
import 'package:mvc_app/modules/chat/chat_bloc.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/modules/chat/chat_service.dart';
import 'package:mvc_app/modules/chat/widgets/chat_app_bar.dart';
import 'package:mvc_app/utils/chat_menu_actions.dart';
import 'package:mvc_app/services/amplitude_service.dart';
import 'package:mvc_app/services/app_tour_service.dart';
import 'package:mvc_app/services/first_run_service.dart';
import 'package:mvc_app/widgets/app_tour_overlay.dart';

/// Global key to access MainScaffold from anywhere in the app
final GlobalKey<_MainScaffoldState> mainScaffoldKey =
    GlobalKey<_MainScaffoldState>();

/// MainScaffold provides persistent bottom navigation across all authenticated screens
class MainScaffold extends StatefulWidget {
  final String? initialOrganizationId;

  const MainScaffold({super.key, this.initialOrganizationId});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _selectedTabIndex = 0;
  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(), // Channels (0)
    GlobalKey<NavigatorState>(), // Direct (1)
    GlobalKey<NavigatorState>(), // (2, unused — reserved)
    GlobalKey<NavigatorState>(), // Explore (3)
    GlobalKey<NavigatorState>(), // Market (4)
  ];

  // Key to access DirectMessagesScreen state for opening specific conversations
  final GlobalKey<DirectMessagesScreenState> _directMessagesKey =
      GlobalKey<DirectMessagesScreenState>();
  String? _pendingOrganizationId; // Organization ID to open after tab switch

  // App tour state
  bool _showingTour = false;

  // --- Global app banner (DM notifications + snackbar-style alerts) ---
  _AppBannerPayload? _bannerPayload;
  Timer? _bannerTimer;
  StreamSubscription<RemoteMessage>? _dmFcmSubscription;

  /// Current tab index — used by DirectMessagesScreen to decide whether to
  /// delegate banner display here (non-DM tab) or show its own in-screen banner.
  int get selectedTabIndex => _selectedTabIndex;

  @override
  void initState() {
    super.initState();
    // Secondary FCM trigger: catches DM push notifications that arrive while
    // the app is already open and the user is on a non-DM tab.
    _dmFcmSubscription =
        FirebaseMessaging.onMessage.listen(_onDMForegroundMessage);
    if (!kReleaseMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScreenStateRegistry.instance.update(const ScreenState(
          screen: 'MainScaffold',
          subState: 'authenticated',
          metadata: {'tab': 'channels'},
        ));
      });
    }
    // Trigger the app tour on first install (after any first-run hint dialogs
    // from individual screens have had a chance to appear — so we use a short
    // post-frame delay here and the actual hint dialogs use their own delays).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeTriggerTourAfterHints();
    });
  }

  /// Waits a beat so existing first-run hint dialogs can appear first, then
  /// starts the tour if it has never been shown.
  Future<void> _maybeTriggerTourAfterHints() async {
    // Small delay so individual screen hints (profile, chat, etc.) render first
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    final shouldShow = await FirstRunService.instance.shouldShow(
      FirstRunKeys.appTour,
    );
    if (!mounted || !shouldShow) return;
    startTour();
  }

  /// Starts the app tour overlay. Can also be called programmatically (e.g. from
  /// the profile settings "Tour me through the app" option).
  void startTour() {
    if (!mounted) return;
    setState(() => _showingTour = true);
    AmplitudeService.instance.logEvent('app_tour_started');
  }

  void _endTour({required bool completed}) {
    if (!mounted) return;
    setState(() => _showingTour = false);
    FirstRunService.instance.markShown(FirstRunKeys.appTour);
    AmplitudeService.instance.logEvent(
      completed ? 'app_tour_completed' : 'app_tour_skipped',
    );
  }

  List<TourStep> _buildTourSteps() {
    // Mirrors the items built in _buildBottomNavigationBar: Home, Messages,
    // Directory, Market.
    const numItems = 4;
    return [
      const TourStep(
        title: 'Welcome!',
        body: "Let's take a quick tour of the app so you know your way around.",
        icon: Icons.waving_hand_outlined,
      ),
      TourStep(
        title: 'Home — Channels',
        body:
            'Your main feed. Stay up to date with news, events, and updates from all the organizations you follow.',
        icon: Icons.home_outlined,
        anchorProvider: () =>
            AppTourService.instance.navItemRect(0, numItems),
      ),
      TourStep(
        title: 'Messages',
        body:
            'Chat directly with companies and organizations. Start a conversation or continue an existing one.',
        icon: Icons.forum_outlined,
        anchorProvider: () =>
            AppTourService.instance.navItemRect(1, numItems),
      ),
      TourStep(
        title: 'Directory',
        body:
            'Explore and discover new channels. Browse by category or search for specific topics that interest you.',
        icon: Icons.explore_outlined,
        // Directory is the 3rd tab (index 2), not the last: Market follows it.
        anchorProvider: () =>
            AppTourService.instance.navItemRect(2, numItems),
      ),
      TourStep(
        title: 'Your Profile',
        body:
            'Tap the menu icon at the top to access your profile, settings, privacy preferences, and more.',
        icon: Icons.menu,
        anchorProvider: () {
          // The hamburger/menu button is always in the top-right corner of the
          // app bar. We approximate its rect from screen + safe-area dimensions
          // instead of using a GlobalKey (which would conflict across the
          // multiple Offstage-kept app bars in different tabs).
          final mq = MediaQuery.of(context);
          final topPad = mq.padding.top;
          final screenW = mq.size.width;
          // kToolbarHeight / 2 centres vertically within the app bar
          return Rect.fromCenter(
            center: Offset(screenW - 32, topPad + kToolbarHeight / 2),
            width: 48,
            height: 48,
          );
        },
      ),
      const TourStep(
        title: 'Manage Your Feed',
        body:
            'In the Channels list, swipe LEFT on any channel to mute or unmute it. Swipe RIGHT to mark it as read or unread.',
        icon: Icons.swipe_outlined,
      ),
      const TourStep(
        title: 'Follow Channels',
        body:
            'Channels you follow in the Directory appear in your Home feed automatically. Head to Directory to get started!',
        icon: Icons.bookmark_add_outlined,
      ),
    ];
  }

  @override
  void dispose() {
    _dmFcmSubscription?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }

  void _onDMForegroundMessage(RemoteMessage message) {
    final notificationType = message.data['notification_type'];
    final convId = message.data['conversation_id'] as String?;
    if (convId == null) return;

    if (notificationType == 'direct_message') {
      if (_selectedTabIndex == 1) return; // DM screen handles it itself
      showDMBanner(
        title: message.notification?.title ?? 'New message',
        body: message.notification?.body ?? '',
        conversationId: convId,
      );
    } else if (notificationType == 'vehicle_inquiry') {
      // Don't notify about the conversation the user is currently viewing
      if (VehicleInquiryChatScreen.currentOpenConversationId == convId) return;
      // Not yet known whether this one is about a car or another Market item.
      showBanner(
        title: message.notification?.title ?? 'New message',
        body: message.notification?.body ?? '',
        icon: Icons.storefront,
        onTap: () {
          dismissBanner();
          openVehicleInquiryConversation(convId);
        },
      );
    }
  }

  /// Opens a Market inquiry chat — about a car or any other listing — from a
  /// push notification / deep link: switches to the Market tab and pushes the
  /// conversation on its navigator.
  Future<void> openVehicleInquiryConversation(String conversationId) async {
    final result = await context
        .read<ApiRepository>()
        .getVehicleInquiryById(conversationId);

    if (!mounted) return;
    if (!result.isSuccess || result.data == null) {
      showBanner(
        title: 'Conversation unavailable',
        body: result.error ?? 'Could not open the conversation',
        icon: Icons.error_outline,
        iconColor: Colors.red,
      );
      return;
    }

    switchToMarketTab();

    // Wait for the Market navigator to exist (first render after un-offstaging),
    // mirroring the retry pattern used by switchToDirectMessagesTab.
    void push(NavigatorState navigator) {
      // Avoid stacking the same chat twice when tapping repeated notifications
      if (VehicleInquiryChatScreen.currentOpenConversationId ==
          conversationId) {
        return;
      }
      navigator.push(
        MaterialPageRoute(
          builder: (_) =>
              VehicleInquiryChatScreen(conversation: result.data!),
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = _navigatorKeys[4].currentState;
      if (navigator != null) {
        push(navigator);
      } else {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (!mounted) return;
          final retryNavigator = _navigatorKeys[4].currentState;
          if (retryNavigator != null) push(retryNavigator);
        });
      }
    });
  }

  /// Shows a DM-style banner on the currently visible tab.
  /// Called by [DirectMessagesScreen] via [mainScaffoldKey] when the user is
  /// NOT on the DM tab so the Realtime-driven banner remains visible.
  void showDMBanner({
    required String title,
    required String body,
    required String conversationId,
  }) {
    showBanner(
      title: title,
      body: body,
      icon: Icons.forum,
      onTap: () {
        dismissBanner();
        switchToDirectMessagesTab(conversationId: conversationId);
      },
    );
  }

  /// Shows a generic slide-down banner on top of all content.
  ///
  /// Use [backgroundColor] / [titleColor] / [bodyColor] to create
  /// warning (amber), error (red), success (green) variants, etc.
  /// The banner auto-dismisses after [duration] (default 4 s).
  void showBanner({
    required String title,
    String body = '',
    IconData icon = Icons.info_outline,
    Color backgroundColor = Colors.white,
    Color titleColor = AppTheme.black,
    Color bodyColor = AppTheme.secondaryHeadingColor,
    Color iconColor = AppTheme.accentPrimary,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 4),
  }) {
    _bannerTimer?.cancel();
    setState(() {
      _bannerPayload = _AppBannerPayload(
        title: title,
        body: body,
        icon: icon,
        backgroundColor: backgroundColor,
        titleColor: titleColor,
        bodyColor: bodyColor,
        iconColor: iconColor,
        onTap: onTap,
      );
    });
    _bannerTimer = Timer(duration, dismissBanner);
  }

  /// Dismisses the banner immediately.
  void dismissBanner() {
    _bannerTimer?.cancel();
    if (mounted) setState(() => _bannerPayload = null);
  }

  int _getActualTabIndex(AuthState authState, int visualIndex) {
    // 0=Channels, 1=Direct, 2=Explore (actual 3), 3=Market (actual 4)
    if (visualIndex == 0) return 0;
    if (visualIndex == 1) return 1;
    if (visualIndex == 2) return 3;
    if (visualIndex == 3) return 4;
    return visualIndex;
  }

  int _getVisualTabIndex(AuthState authState, int actualIndex) {
    // 0=Channels, 1=Direct, 3=Explore (visual 2), 4=Market (visual 3)
    if (actualIndex == 0) return 0;
    if (actualIndex == 1) return 1;
    if (actualIndex == 3) return 2;
    if (actualIndex == 4) return 3;
    return actualIndex;
  }

  Future<bool> _onWillPop() async {
    // _selectedTabIndex is already the actual index
    final currentNavigator = _navigatorKeys[_selectedTabIndex].currentState;

    if (currentNavigator != null && currentNavigator.canPop()) {
      currentNavigator.pop();
      return false;
    }
    return true;
  }

  Widget _buildOffstageNavigator(int index, Widget child) {
    final visible = _selectedTabIndex == index;
    return Offstage(
      offstage: !visible,
      // Offstage stops the painting, not the clock: an animation in a hidden
      // tab keeps running and keeps costing battery. TickerMode is what
      // actually pauses it — the Market tab's rolling car strip, for one.
      child: TickerMode(
        enabled: visible,
        child: Navigator(
          key: _navigatorKeys[index],
          onGenerateRoute: (routeSettings) {
            return MaterialPageRoute(builder: (context) => child);
          },
        ),
      ),
    );
  }

  /// Method to switch to Channels tab and optionally select a channel by organization ID
  void switchToChannelsTab({String? organizationId}) {
    setState(() {
      _selectedTabIndex = 0; // Switch to Channels tab
    });

    // Update badge when switching to Channels tab
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final chatState = context.read<ChatBloc>().state;
        if (chatState is ChatLoadedState) {
          // Update badge based on current unread count when viewing chats
          ChatService.updateNotificationBadgeFromChannels(chatState.allChannels);
        }
      }
    });

    if (organizationId != null) {
      // Select the channel for this organization
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<ChatBloc>().add(
            SelectChannelByOrganizationIdEvent(organizationId),
          );
        }
      });
    }
  }

  /// Method to switch to Explore tab
  void switchToExploreTab() {
    setState(() {
      _selectedTabIndex = 3; // Switch to Explore tab (always at index 3)
    });
  }

  /// Switches to the Market tab (Cars & Trucks and every other category).
  void switchToMarketTab() {
    setState(() {
      _selectedTabIndex = 4;
    });
  }

  /// Method to switch to Direct Messages tab and optionally open a conversation
  /// Use organizationId to create/open a conversation with a specific organization
  /// Use conversationId to open an existing conversation directly (e.g., from notifications)
  void switchToDirectMessagesTab({String? organizationId, String? conversationId}) {
    // Store the organization ID to open after tab switch
    _pendingOrganizationId = organizationId;

    setState(() {
      _selectedTabIndex = 1; // Switch to Direct Messages tab
    });

    // If organizationId is provided, open/create that conversation after tab switch.
    // Two attempts: postFrameCallback for the common case, then a short delay as
    // fallback for the first render after un-offstaging the DM Navigator.
    if (organizationId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _pendingOrganizationId == null) return;
        final directMessagesState = _directMessagesKey.currentState;
        if (directMessagesState != null) {
          directMessagesState.openOrCreateConversation(_pendingOrganizationId!);
          _pendingOrganizationId = null;
        } else {
          // Navigator not ready yet — retry after a short delay
          Future.delayed(const Duration(milliseconds: 150), () {
            if (!mounted || _pendingOrganizationId == null) return;
            _directMessagesKey.currentState
                ?.openOrCreateConversation(_pendingOrganizationId!);
            _pendingOrganizationId = null;
          });
        }
      });
    }

    // If conversationId is provided, open that specific conversation after tab switch
    if (conversationId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final directMessagesState = _directMessagesKey.currentState;
          if (directMessagesState != null) {
            directMessagesState.openConversationById(conversationId);
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        return WillPopScope(
          onWillPop: _onWillPop,
          child: Scaffold(
            body: Stack(
              children: [
                // Channels (index 0)
                _buildOffstageNavigator(
                  0,
                  RealChatScreen(organizationId: widget.initialOrganizationId),
                ),
                // Direct (index 1)
                _buildOffstageNavigator(
                  1,
                  DirectMessagesScreen(key: _directMessagesKey),
                ),
                // Explore (index 3)
                _buildOffstageNavigator(
                  3,
                  CategoriesGridScreen(
                    onRefresh: () {
                      context.read<ChatBloc>().add(LoadChannelsEvent());
                    },
                    onLogoTap: () => switchToChannelsTab(),
                    onChannelsTabTap: () => switchToChannelsTab(),
                    onManageTabTap: () {},
                    onCategoriesTabTap: () {
                      setState(() {
                        _selectedTabIndex = 3;
                      });
                    },
                  ),
                ),
                // Market (index 4)
                _buildOffstageNavigator(
                  4,
                  const MarketScreen(),
                ),
                // Global banner overlay — DM notifications + snackbar alerts
                _buildGlobalBanner(),
                // App tour overlay (first-run or triggered from profile)
                if (_showingTour)
                  _buildTourOverlay(authState),
              ],
            ),
            bottomNavigationBar: _buildBottomNavigationBar(authState),
          ),
        );
      },
    );
  }

  Widget _buildTourOverlay(AuthState authState) {
    return Positioned.fill(
      child: AppTourOverlay(
        steps: _buildTourSteps(),
        onStepShown: (index) {
          AmplitudeService.instance.logEvent(
            'app_tour_step_viewed',
            eventProperties: {'step': index + 1},
          );
        },
        onFinish: () => _endTour(completed: true),
        onSkip: () => _endTour(completed: false),
      ),
    );
  }

  Widget _buildGlobalBanner() {
    final payload = _bannerPayload;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
            reverseCurve: Curves.easeIn,
          ));
          return SlideTransition(
            position: slide,
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: payload != null
            ? _AppBannerCard(
                key: ValueKey(payload.title + payload.body),
                payload: payload,
                onDismiss: dismissBanner,
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildBottomNavigationBar(AuthState authState) {
    List<BottomNavigationBarItem> items = [
      const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
    ];

    // Add Direct tab (available to everyone)
    items.add(
      const BottomNavigationBarItem(
        icon: Icon(Icons.forum),
        label: 'Messages',
      ),
    );

    // Add Explore tab
    items.add(
      const BottomNavigationBarItem(
        icon: Icon(Icons.explore),
        label: 'Directory',
      ),
    );

    // Add Market tab. "Magic Market" is wider than a quarter of a phone
    // screen, so it takes two lines: the storefront and "Magic" go in the icon
    // slot, letter-sized rather than above the words, and "Market" is the
    // label on the line below.
    items.add(
      const BottomNavigationBarItem(
        icon: _MagicMarketIcon(),
        label: 'Market',
        tooltip: 'Magic Market',
        semanticsLabel: 'Magic Market',
      ),
    );

    // Convert actual index to visual index for display
    final displayIndex = _getVisualTabIndex(authState, _selectedTabIndex);

    return KeyedSubtree(
      key: AppTourService.instance.bottomNavKey,
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: displayIndex.clamp(0, items.length - 1),
          onTap: (visualIndex) {
            // Provide subtle haptic feedback on tab taps (Android & iOS)
            HapticFeedback.selectionClick();
            // Map visual index to actual screen index
            final actualIndex = _getActualTabIndex(authState, visualIndex);

            // Special handling for Channels tab: if we're already on Channels tab and a chat is open, go back to channels list
            if (actualIndex == 0 && _selectedTabIndex == 0) {
              final channelsNavigator = _navigatorKeys[0].currentState;
              if (channelsNavigator != null && channelsNavigator.canPop()) {
                // We're in a chat, pop back to channels list
                channelsNavigator.pop();
                return;
              }
            }

            // Special handling for Direct tab: if we're already on Direct tab and a conversation is open, go back to messages list
            if (actualIndex == 1 && _selectedTabIndex == 1) {
              final directNavigator = _navigatorKeys[1].currentState;
              if (directNavigator != null && directNavigator.canPop()) {
                // We're in a conversation, pop back to messages list
                directNavigator.pop();
                return;
              }
            }

            // Special handling for Explore tab: if we're already on Explore tab and navigated deeper, go back to explore home
            if (actualIndex == 3 && _selectedTabIndex == 3) {
              final exploreNavigator = _navigatorKeys[3].currentState;
              if (exploreNavigator != null && exploreNavigator.canPop()) {
                exploreNavigator.pop();
                return;
              }
            }

            setState(() {
              _selectedTabIndex = actualIndex;
            });
            const tabNames = {0: 'home', 1: 'messages', 2: 'manage', 3: 'directory', 4: 'market'};
            AmplitudeService.instance.logEvent(
              'tab_viewed',
              eventProperties: {'tab': tabNames[actualIndex] ?? 'unknown'},
            );
          },
          items: items,
          backgroundColor: AppTheme.headerBackground,
          selectedItemColor: AppTheme.accentPrimary,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: _navLabelFontSize,
          unselectedFontSize: _navLabelFontSize,
          elevation: 8,
        ),
      ),
    );
  }
}

/// Size of the bottom bar's labels, shared with [_MagicMarketIcon] so that its
/// icon and its half of the wordmark match the label printed under them.
const double _navLabelFontSize = 12;

/// The Market tab's icon slot: a storefront no bigger than the letters beside
/// it, then "Magic". "Market" is the tab's own label on the line below, which
/// keeps the colour animating with the rest of the bar and keeps this tab
/// exactly as tall as the ones whose icon sits above their label.
class _MagicMarketIcon extends StatelessWidget {
  const _MagicMarketIcon();

  @override
  Widget build(BuildContext context) {
    // The bar hands its icons the colour it animates between selected and
    // unselected, and the height it gives every other tab's icon.
    final iconTheme = IconTheme.of(context);
    final color = iconTheme.color;

    return SizedBox(
      height: iconTheme.size,
      child: Center(
        // As the bar itself does with labels: a bottom bar has no room to grow.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront, size: _navLabelFontSize, color: color),
              const SizedBox(width: 3),
              // Read out by the item's semanticsLabel instead, in one piece.
              ExcludeSemantics(
                child: Text(
                  'Magic',
                  style: TextStyle(fontSize: _navLabelFontSize, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data class for the global app banner payload
// ---------------------------------------------------------------------------
class _AppBannerPayload {
  final String title;
  final String body;
  final IconData icon;
  final Color backgroundColor;
  final Color titleColor;
  final Color bodyColor;
  final Color iconColor;
  final VoidCallback? onTap;

  const _AppBannerPayload({
    required this.title,
    required this.body,
    required this.icon,
    required this.backgroundColor,
    required this.titleColor,
    required this.bodyColor,
    required this.iconColor,
    this.onTap,
  });
}

// ---------------------------------------------------------------------------
// Slide-down banner card — used by MainScaffold._buildGlobalBanner()
// ---------------------------------------------------------------------------
class _AppBannerCard extends StatelessWidget {
  final _AppBannerPayload payload;
  final VoidCallback onDismiss;

  const _AppBannerCard({
    super.key,
    required this.payload,
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
            color: payload.backgroundColor,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: payload.onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: payload.iconColor,
                      child: Icon(payload.icon, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            payload.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: payload.titleColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (payload.body.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              payload.body,
                              style: TextStyle(
                                fontSize: 13,
                                color: payload.bodyColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onDismiss,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: payload.bodyColor,
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
}
