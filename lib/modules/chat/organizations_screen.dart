// lib/screens/organizations_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/channels/organization_profile_screen.dart';
import 'package:mvc_app/modules/chat/models/organization_event.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';
import 'package:mvc_app/modules/chat/organizations_bloc.dart';
import 'package:mvc_app/main_scaffold.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/api_service.dart';
import 'package:mvc_app/services/notification_preferences_service.dart';
import 'package:mvc_app/widgets/app_dialog.dart';
import 'package:mvc_app/utils/profile_utils.dart';

enum SortType { name, popularity, following }

class OrganizationsScreen extends StatelessWidget {
  final String? categoryId;
  final String categoryName;
  final VoidCallback? onOrganizationFollowChanged; // Add callback
  final String? initialSearchTerm; // Add initial search term

  const OrganizationsScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.onOrganizationFollowChanged, // Add callback parameter
    this.initialSearchTerm, // Add initial search term parameter
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => OrganizationsBloc()
        ..add(
          LoadOrganizationsByCategory(
            categoryId: categoryId,
            categoryName: categoryName,
          ),
        ),
      child: OrganizationsView(
        categoryName: categoryName,
        onOrganizationFollowChanged:
            onOrganizationFollowChanged, // Pass callback
        initialSearchTerm: initialSearchTerm, // Pass initial search term
      ),
    );
  }
}

class OrganizationsView extends StatefulWidget {
  final String categoryName;
  final VoidCallback? onOrganizationFollowChanged; // Add callback
  final String? initialSearchTerm; // Add initial search term

  const OrganizationsView({
    super.key,
    required this.categoryName,
    this.onOrganizationFollowChanged, // Add callback parameter
    this.initialSearchTerm, // Add initial search term parameter
  });

  @override
  State<OrganizationsView> createState() => _OrganizationsViewState();
}

class _OrganizationsViewState extends State<OrganizationsView> {
  final TextEditingController _searchController = TextEditingController();
  final ApiService _apiService = SupabaseApiService.instance;
  final NotificationPreferencesService _notificationService =
      NotificationPreferencesService.instance;
  final GlobalKey _sortMenuKey = GlobalKey();
  UserRole? _userRole;
  List<Organization> _managedOrganizations = [];
  OrganizationsState? _previousState;
  SortType _currentSort = SortType.popularity;

  @override
  void initState() {
    super.initState();
    // Set initial search term if provided
    if (widget.initialSearchTerm != null) {
      _searchController.text = widget.initialSearchTerm!;
    }
    _searchController.addListener(_onSearchChanged);
    _fetchUserRoleAndManagedOrganizations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
  }

  void _showSortMenu(BuildContext context) {
    final RenderBox? button =
        _sortMenuKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    if (button == null) return;

    // Get button's bottom-right corner position
    final buttonBottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );

    // Position menu below the search bar, aligned to the right
    // Add 8px spacing below the button
    final menuTopLeft = Offset(
      buttonBottomRight.dx - 120,
      buttonBottomRight.dy + 8,
    );
    final menuBottomRight = Offset(
      buttonBottomRight.dx,
      buttonBottomRight.dy + 8,
    );

    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(menuTopLeft, menuBottomRight),
      Offset.zero & overlay.size,
    );

    showMenu<SortType>(
      context: context,
      position: position,
      items: [
        _buildSortMenuItem('POPULARITY', SortType.popularity),
        _buildSortMenuItem('NAME', SortType.name),
        _buildSortMenuItem('FOLLOWING', SortType.following),
      ],
    ).then((selectedSort) {
      if (selectedSort != null) {
        setState(() {
          _currentSort = selectedSort;
        });
      }
    });
  }

  PopupMenuItem<SortType> _buildSortMenuItem(String label, SortType sortType) {
    final isActive = _currentSort == sortType;
    return PopupMenuItem<SortType>(
      value: sortType,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.accentPrimary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(
              '↑',
              style: TextStyle(
                fontSize: 12,
                color: isActive ? AppTheme.accentPrimary : Colors.grey[400],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? AppTheme.accentPrimary : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchUserRoleAndManagedOrganizations() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticatedState || authState.userProfile == null) return;

    final userProfile = authState.userProfile!;
    setState(() {
      _userRole = userProfile.role;
    });

    if (!userProfile.role.isSuperAdmin) {
      final managedOrgsResult = await _apiService.getUserManagedOrganizations(
        userProfile.id,
      );
      if (managedOrgsResult.isSuccess && mounted) {
        setState(() {
          _managedOrganizations = managedOrgsResult.data ?? [];
        });
      }
    }
  }

  List<Organization> _filterOrganizations(List<Organization> organizations) {
    // Filter organizations if search term exists
    List<Organization> filtered = organizations;
    if (_searchController.text.isNotEmpty) {
      final searchTerm = _searchController.text.toLowerCase();
      filtered = organizations.where((organization) {
        return organization.name.toLowerCase().contains(searchTerm);
      }).toList();
    }

    // Sort based on current sort type
    switch (_currentSort) {
      case SortType.name:
        // Sort alphabetically (case-insensitive)
        filtered.sort(
          (a, b) => a.name.toLowerCase().trim().compareTo(
            b.name.toLowerCase().trim(),
          ),
        );
        break;
      case SortType.popularity:
        // Sort by follower count (descending), then alphabetically
        filtered.sort((a, b) {
          final followerComparison = b.followerCount.compareTo(a.followerCount);
          if (followerComparison != 0) return followerComparison;
          return a.name.toLowerCase().trim().compareTo(
            b.name.toLowerCase().trim(),
          );
        });
        break;
      case SortType.following:
        // Sort by following status (following first), then alphabetically
        filtered.sort((a, b) {
          if (a.isFollowing && !b.isFollowing) return -1;
          if (!a.isFollowing && b.isFollowing) return 1;
          return a.name.toLowerCase().trim().compareTo(
            b.name.toLowerCase().trim(),
          );
        });
        break;
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.categoryName,
          style: AppTheme.managementHeading.copyWith(fontSize: 20),
        ),
        backgroundColor: AppTheme.white,
        foregroundColor: AppTheme.black,
        elevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.searchBarBackground,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search channels...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: IconButton(
                        key: _sortMenuKey,
                        icon: const Icon(Icons.list, color: Colors.grey),
                        onPressed: () => _showSortMenu(context),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: BlocListener<OrganizationsBloc, OrganizationsState>(
        listener: (context, state) {
          // Handle follow/unfollow completion
          if (state is OrganizationsLoaded &&
              _previousState is OrganizationFollowLoading) {
            final loadingState = _previousState as OrganizationFollowLoading;
            final organizationId = loadingState.loadingOrganizationId;

            // Find the organization in both states safely
            Organization? previousOrg;
            Organization? currentOrg;

            try {
              previousOrg = loadingState.organizations.firstWhere(
                (org) => org.id == organizationId,
              );
            } catch (e) {
              // Organization not in previous state, might have been just added
            }

            try {
              currentOrg = state.organizations.firstWhere(
                (org) => org.id == organizationId,
              );
            } catch (e) {
              // Organization not found, skip dialog
              widget.onOrganizationFollowChanged?.call();
              _previousState = state;
              return;
            }

            // Determine if it was a follow or unfollow
            if (previousOrg != null) {
              final wasFollow =
                  !previousOrg.isFollowing && currentOrg.isFollowing;
              final wasUnfollow =
                  previousOrg.isFollowing && !currentOrg.isFollowing;

              if (wasFollow) {
                // Follow: Enable notifications and show dialog
                _handleFollowAction(currentOrg);
              } else if (wasUnfollow) {
                // Unfollow: Show dialog explaining how to mute
                _handleUnfollowAction(currentOrg);
              }
            } else if (currentOrg.isFollowing) {
              // Organization was just added (new follow)
              _handleFollowAction(currentOrg);
            }

            widget.onOrganizationFollowChanged?.call();
          }
          _previousState = state;
        },
        child: BlocBuilder<OrganizationsBloc, OrganizationsState>(
          builder: (context, state) {
            if (state is OrganizationsLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is OrganizationsError) {
              return _buildErrorView(state.message);
            } else if (state is OrganizationsLoaded ||
                state is OrganizationFollowLoading) {
              final allOrganizations = state is OrganizationsLoaded
                  ? state.organizations
                  : (state as OrganizationFollowLoading).organizations;

              final filteredOrganizations = _filterOrganizations(
                allOrganizations,
              );

              final loadingOrganizationId = state is OrganizationFollowLoading
                  ? state.loadingOrganizationId
                  : null;

              return RefreshIndicator(
                onRefresh: () async {
                  context.read<OrganizationsBloc>().add(RefreshOrganizations());
                },
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredOrganizations.length,
                  itemBuilder: (context, index) {
                    final organization = filteredOrganizations[index];
                    final isLoading = loadingOrganizationId == organization.id;

                    return OrganizationCard(
                      organization: organization,
                      isLoading: isLoading,
                      searchTerm: _searchController.text,
                      userRole: _userRole,
                      managedOrganizations: _managedOrganizations,
                      onFollowPressed: () async {
                        // Check if profile needs completion before following
                        final canContinue = await ProfileUtils.showProfileCompletionBottomSheet(
                          context,
                          message: 'Please complete your profile to follow channels.',
                        );

                        if (canContinue && context.mounted) {
                          if (organization.isFollowing) {
                            context.read<OrganizationsBloc>().add(
                              UnfollowOrganization(
                                organizationId: organization.id,
                              ),
                            );
                          } else {
                            context.read<OrganizationsBloc>().add(
                              FollowOrganization(organizationId: organization.id),
                            );
                          }
                        }
                      },
                    );
                  },
                ),
              );
            }

            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Future<void> _handleFollowAction(Organization organization) async {
    // Enable notifications for the channel (unmute)
    await _notificationService.enableChannelNotification(organization.id);

    // Show dialog with auto-dismiss after 2 seconds
    if (mounted) {
      await AppDialog.show(
        context: context,
        icon: Icons.notifications_active,
        heading: 'You\'ll receive notifications',
        subheading:
            'You will get notifications from ${organization.name}. You can disable them by holding on the channel name and choosing to mute notifications.',
        dismissible: false,
        autoCloseDuration: const Duration(seconds: 2),
        opacity: 0.0,
      );
    }
  }

  Future<void> _handleUnfollowAction(Organization organization) async {
    // Show dialog explaining how to mute (auto-dismiss after 2 seconds)
    if (mounted) {
      await AppDialog.show(
        context: context,
        icon: Icons.notifications_off,
        heading: 'Notifications disabled',
        subheading:
            'You will no longer receive notifications from ${organization.name}. To enable them again, follow the channel and hold on it to manage notifications.',
        dismissible: false,
        autoCloseDuration: const Duration(seconds: 2),
      );
    }
  }

  Widget _buildErrorView(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(
            'Oops! Something went wrong',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              context.read<OrganizationsBloc>().add(RefreshOrganizations());
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}

// Updated OrganizationCard to conditionally display follower count
class OrganizationCard extends StatefulWidget {
  final Organization organization;
  final bool isLoading;
  final String searchTerm;
  final UserRole? userRole;
  final List<Organization> managedOrganizations;
  final VoidCallback onFollowPressed;

  const OrganizationCard({
    super.key,
    required this.organization,
    required this.onFollowPressed,
    this.isLoading = false,
    this.searchTerm = '',
    this.userRole,
    this.managedOrganizations = const [],
  });

  @override
  State<OrganizationCard> createState() => _OrganizationCardState();
}

class _OrganizationCardState extends State<OrganizationCard> {
  int? _followerCount;
  bool _isLoadingFollowerCount = false;
  final ApiService _apiService = SupabaseApiService.instance;

  bool get _canSeeFollowerCount {
    if (widget.userRole?.isSuperAdmin == true) return true;
    if (widget.userRole?.isAdmin == true) {
      return widget.managedOrganizations.any(
        (org) => org.id == widget.organization.id,
      );
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    if (_canSeeFollowerCount) {
      _fetchFollowerCount();
    }
  }

  @override
  void didUpdateWidget(OrganizationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refetch if organization changed, follow status changed, or visibility changed
    if (_canSeeFollowerCount &&
        (oldWidget.organization.id != widget.organization.id ||
            oldWidget.organization.isFollowing !=
                widget.organization.isFollowing ||
            oldWidget.userRole != widget.userRole ||
            oldWidget.managedOrganizations.length !=
                widget.managedOrganizations.length)) {
      _fetchFollowerCount();
    }
  }

  Future<void> _fetchFollowerCount() async {
    if (!_canSeeFollowerCount) return;

    setState(() {
      _isLoadingFollowerCount = true;
    });

    try {
      final result = await _apiService.getOrganizationFollowers(
        widget.organization.id,
      );

      if (mounted && result.isSuccess) {
        setState(() {
          _followerCount = result.data?.length ?? 0;
          _isLoadingFollowerCount = false;
        });
      } else if (mounted) {
        setState(() {
          _isLoadingFollowerCount = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFollowerCount = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: AppTheme.accentSecondary.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // Navigate to chat screen and select this organization's channel
            _navigateToChat(context);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Organization Logo with loading shimmer - separate tap area
                GestureDetector(
                  onTap: () {
                    // Navigate to organization profile screen
                    _navigateToOrganizationProfile(context);
                  },
                  child: _buildOrganizationLogo(),
                ),
                const SizedBox(width: 16),

                // Organization Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHighlightedText(
                        widget.organization.name,
                        widget.searchTerm,
                        const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      if (_canSeeFollowerCount) ...[
                        const SizedBox(height: 4),
                        _buildFollowerCount(),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // Follow and Message Buttons
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {},
                      child: _buildFollowButton(context),
                    ),
                    if (_showOpenChatButton || _showMessageButton) ...[
                      const SizedBox(height: 8),
                      _buildMessageButton(context),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _showOpenChatButton {
    if (widget.userRole?.isSuperAdmin == true) return true;
    if (widget.userRole?.isAdmin == true) {
      return widget.managedOrganizations.any(
        (org) => org.id == widget.organization.id,
      );
    }
    return false;
  }

  // Only regular users (non-admin) see the Message button
  bool get _showMessageButton => widget.userRole?.isAdminOrSuperAdmin != true;

  Widget _buildMessageButton(BuildContext context) {
    final buttonText = _showOpenChatButton ? 'Open Chat' : 'Message';
    final buttonIcon = _showOpenChatButton ? Icons.chat_outlined : Icons.mail_outline;

    return SizedBox(
      width: 100,
      height: 36,
      child: OutlinedButton(
        onPressed: () => _startDirectMessage(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.accentPrimary,
          side: BorderSide(color: AppTheme.accentPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(buttonIcon, size: 14),
              const SizedBox(width: 4),
              Text(
                buttonText,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startDirectMessage(BuildContext context) async {
    // For regular users, check profile completion first
    if (!_showOpenChatButton) {
      final canContinue = await ProfileUtils.showProfileCompletionBottomSheet(
        context,
        message: 'Please complete your profile to send messages.',
      );
      if (!canContinue || !context.mounted) return;
    }

    // Pop back to the navigator root, then switch to DM tab.
    // openOrCreateConversation handles both roles: regular users create/open
    // immediately; admins are prompted to pick a user first.
    Navigator.of(context).popUntil((route) => route.isFirst);
    mainScaffoldKey.currentState?.switchToDirectMessagesTab(
      organizationId: widget.organization.id,
    );
  }

  Widget _buildHighlightedText(
    String text,
    String searchTerm,
    TextStyle style,
  ) {
    if (searchTerm.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerSearchTerm = searchTerm.toLowerCase();
    final startIndex = lowerText.indexOf(lowerSearchTerm);

    if (startIndex == -1) {
      return Text(
        text,
        style: style,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          if (startIndex > 0)
            TextSpan(text: text.substring(0, startIndex), style: style),
          TextSpan(
            text: text.substring(startIndex, startIndex + searchTerm.length),
            style: style.copyWith(
              backgroundColor: Colors.orange.withOpacity(0.3),
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          if (startIndex + searchTerm.length < text.length)
            TextSpan(
              text: text.substring(startIndex + searchTerm.length),
              style: style,
            ),
        ],
      ),
    );
  }

  Widget _buildOrganizationLogo() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: AppTheme.headerBackground,
      ),
      child:
          widget.organization.logoUrl != null &&
              widget.organization.logoUrl!.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Image.network(
                widget.organization.logoUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return _buildDefaultLogo();
                },
                errorBuilder: (context, error, stackTrace) {
                  return _buildDefaultLogo();
                },
              ),
            )
          : _buildDefaultLogo(),
    );
  }

  Widget _buildDefaultLogo() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [Colors.blue[300]!, Colors.blue[600]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          widget.organization.name.isNotEmpty
              ? widget.organization.name[0].toUpperCase()
              : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildFollowerCount() {
    final count = _followerCount ?? widget.organization.followerCount;
    return Row(
      children: [
        Icon(Icons.people_outline, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        _isLoadingFollowerCount
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[600]!),
                ),
              )
            : Text(
                '${_formatFollowerCount(count)} follower${count > 1 ? "s" : ""}',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
      ],
    );
  }

  Widget _buildFollowButton(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 100,
      height: 36,
      child: widget.isLoading
          ? Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : ElevatedButton(
              onPressed: widget.onFollowPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.organization.isFollowing
                    ? AppTheme.accentSecondary.withOpacity(0.1)
                    : AppTheme.accentPrimary,
                foregroundColor: widget.organization.isFollowing
                    ? AppTheme.accentSecondary
                    : AppTheme.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                elevation: widget.organization.isFollowing ? 0 : 2,
                shadowColor: AppTheme.accentPrimary.withOpacity(0.3),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    widget.organization.isFollowing ? 'Un-follow' : 'Follow',
                    key: ValueKey(widget.organization.isFollowing),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  void _navigateToChat(BuildContext context) async {
    // Check if profile needs completion before navigating to channel
    final canContinue = await ProfileUtils.showProfileCompletionBottomSheet(
      context,
      message: 'Please complete your profile to access channels and start chatting.',
    );

    if (canContinue && context.mounted) {
      // Pop back to the root of the Explore tab's navigator
      Navigator.of(context).popUntil((route) => route.isFirst);

      // Use the global key to access MainScaffold and switch to Channels tab
      mainScaffoldKey.currentState?.switchToChannelsTab(
        organizationId: widget.organization.id,
      );
    }
  }

  void _navigateToOrganizationProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            OrganizationProfileScreen(organizationId: widget.organization.id),
      ),
    );
  }

  String _formatFollowerCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    } else {
      return count.toString();
    }
  }
}
