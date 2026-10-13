// lib/modules/channels/categories_grid_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/channels/categories_bloc.dart';
import 'package:mvc_app/modules/channels/category_icons.dart';
import 'package:mvc_app/modules/channels/category_tile.dart';
import 'package:mvc_app/modules/channels/explore_feed_bloc.dart';
import 'package:mvc_app/modules/channels/organization_profile_screen.dart';
import 'package:mvc_app/modules/channels/widgets/explore_feed_tab.dart';
import 'package:mvc_app/modules/chat/widgets/chat_app_bar.dart';
import 'package:mvc_app/modules/chat/organizations_screen.dart';
import 'package:mvc_app/modules/chat/organizations_bloc.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';
import 'package:mvc_app/modules/chat/models/organization_event.dart';
import 'package:mvc_app/main_scaffold.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/api_service.dart';
import 'package:mvc_app/utils/chat_menu_actions.dart';
import 'package:mvc_app/utils/profile_utils.dart';
import 'package:mvc_app/services/notification_preferences_service.dart';
import 'package:mvc_app/widgets/app_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../flavour_config.dart';

class CategoriesGridScreen extends StatefulWidget {
  final VoidCallback? onRefresh; // Add callback parameter
  final VoidCallback? onLogoTap;
  final VoidCallback? onChannelsTabTap;
  final VoidCallback? onManageTabTap;
  final VoidCallback? onCategoriesTabTap;

  const CategoriesGridScreen({
    super.key,
    this.onRefresh,
    this.onLogoTap,
    this.onChannelsTabTap,
    this.onManageTabTap,
    this.onCategoriesTabTap,
  });

  @override
  _CategoriesGridScreenState createState() => _CategoriesGridScreenState();
}

class _CategoriesGridScreenState extends State<CategoriesGridScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late TabController _tabController;
  bool _showSearchBar = false; // Hidden by default, toggled via search icon
  final TextEditingController _searchController = TextEditingController();
  bool _hasNavigatedForSearch =
      false; // Track if we've navigated for current search

  // For All Channels tab
  final ApiService _apiService = SupabaseApiService.instance;
  UserRole? _userRole;
  List<Organization> _managedOrganizations = [];

  @override
  void initState() {
    super.initState();

    // Initialize tab controller - default to "All Channels" tab (index 0)
    // Explore tab only available in QA environment
    _tabController = TabController(
      length: FlavorConfig.supabaseEnvironment == 'qa' ? 3 : 2,
      vsync: this,
    );

    // Initialize fade animation controller
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    // Add search controller listener to navigate when user types
    _searchController.addListener(_onSearchChanged);

    // Reload categories when switching to the Categories tab
    _tabController.addListener(_onTabChanged);

    // Load categories with organization status when screen initializes
    context.read<CategoriesBloc>().add(LoadCategoriesWithStatus());

    // Fetch user role for follower count visibility
    _fetchUserRoleAndManagedOrganizations();
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

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _fadeController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      if (_tabController.index == 1) {
        context.read<CategoriesBloc>().add(LoadCategoriesWithStatus());
      }
      // Explore tab will load via its own BlocProvider initialization
    }
  }

  void _onSearchChanged() {
    final searchTerm = _searchController.text.trim();

    // If user starts typing and we haven't navigated yet, navigate to "All" category with search term
    if (searchTerm.isNotEmpty && mounted && !_hasNavigatedForSearch) {
      _hasNavigatedForSearch = true; // Mark that we've navigated

      // Find the "All" category
      final allCategory = StaticCategories.categories.firstWhere(
        (cat) => cat['id'] == null,
        orElse: () => {'id': null, 'label': 'All', 'icon': Icons.star},
      );

      // Navigate to OrganizationsScreen with the search term
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OrganizationsScreen(
            categoryId: null, // null means "All"
            categoryName: allCategory['label'] as String,
            onOrganizationFollowChanged: widget.onRefresh,
            initialSearchTerm: searchTerm, // Pass the search term
          ),
        ),
      ).then((_) {
        // Reset flag and clear search when returning from the organizations screen
        if (mounted) {
          _hasNavigatedForSearch = false;
          _searchController.clear();
        }
      });
    } else if (searchTerm.isEmpty && _hasNavigatedForSearch) {
      // If search is cleared, reset the flag
      _hasNavigatedForSearch = false;
    }
  }

  bool _isAdminUser(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticatedState && authState.userProfile != null) {
      final role = authState.userProfile!.role.value.toLowerCase();
      return role == 'admin' || role == 'superadmin';
    }
    return false;
  }

  int _selectedTabIndex(BuildContext context) {
    return _isAdminUser(context) ? 2 : 1;
  }

  VoidCallback _wrapCallback(VoidCallback? callback) {
    return callback ?? () {};
  }

  Future<void> _launchChannelApplicationForm() async {
    const url =
        'https://docs.google.com/forms/d/e/1FAIpQLScfR6CCqEU3V_pPOD5BcABZtYG6M6lBOSRJVlT_2Vwtly2iYA/viewform';
    final uri = Uri.parse(url);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Could not open form')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error opening form: $e')));
      }
    }
  }

  Future<void> _showCreateChannelDialog() async {
    await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: AppTheme.accentPrimary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.add_business,
                      size: 48,
                      color: AppTheme.accentPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Create Channel',
                    textAlign: TextAlign.center,
                    style: AppTheme.managementTitleText.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You will be redirected to a form to request the creation of a new channel.',
                    textAlign: TextAlign.center,
                    style: AppTheme.secondaryHeading.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 36),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop(false);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[200],
                            foregroundColor: Colors.grey[700],
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop(true);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentPrimary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Continue',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((confirmed) {
      if (confirmed == true) {
        _launchChannelApplicationForm();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ChatAppBar(
        searchController: _searchController,
        selectedTabIndex: _selectedTabIndex(context),
        onChannelsTabTap: _wrapCallback(widget.onChannelsTabTap),
        onCategoriesTabTap: _wrapCallback(widget.onCategoriesTabTap),
        onManageTabTap: _wrapCallback(widget.onManageTabTap),
        onCreateOrganization: () => handleCreateOrganization(context),
        onCreatePost: (selectedChannel, userId) =>
            handleCreatePost(context, selectedChannel, userId),
        onLogout: () => handleLogout(context),
        theme: AppThemeMode.light,
        showBottomNavigation: false,
        showSearchBar: _showSearchBar,
        onToggleSearchBar: () {
          setState(() {
            _showSearchBar = !_showSearchBar;
            if (!_showSearchBar) {
              _searchController.clear();
            }
          });
        },
        onLogoTap:
            widget.onLogoTap ??
            widget.onChannelsTabTap ??
            () {}, // default no-op if null
        enableSearchToggle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: AppTheme.white,
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    labelColor: AppTheme.accentPrimary,
                    unselectedLabelColor: Colors.grey[600],
                    indicator: BoxDecoration(
                      color: AppTheme.accentPrimary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerHeight: 0,
                    labelStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: [
                      Tab(text: 'Channels'),
                      Tab(text: 'Categories'),
                      if (FlavorConfig.supabaseEnvironment == 'qa')
                        Tab(text: 'Explore'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 0),
                    child: IconButton(
                      icon: const Icon(
                        Icons.add,
                        size: 20,
                        color: AppTheme.accentPrimary,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: _showCreateChannelDialog,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: All Channels List
          _buildAllChannelsTab(),
          // Tab 2: Categories Grid
          _buildCategoriesTab(),
          // Tab 3: Explore Feed (only in QA environment)
          if (FlavorConfig.supabaseEnvironment == 'qa')
            _buildExploreFeedTab(),
        ],
      ),
    );
  }

  Widget _buildCategoriesTab() {
    return BlocListener<CategoriesBloc, CategoriesState>(
      listener: (context, state) {
        if (state is CategoriesWithStatusLoaded) {
          // Start fade in animation when data is loaded
          _fadeController.forward();
        } else if (state is CategoriesLoading) {
          // Reset animation when loading starts
          _fadeController.reset();
        }
      },
      child: BlocBuilder<CategoriesBloc, CategoriesState>(
        builder: (context, state) {
          if (state is CategoriesError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: ${state.message}'),
                  ElevatedButton(
                    onPressed: () {
                      context.read<CategoriesBloc>().add(
                        LoadCategoriesWithStatus(),
                      );
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              context.read<CategoriesBloc>().add(
                RefreshCategoriesWithStatus(),
              );
              // Wait a bit for the refresh to complete
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(
                  child: SizedBox(height: 16),
                ),
                // Loading shimmer grid (only show during loading)
                if (state is CategoriesLoading)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final category = StaticCategories.categories[index];
                        return _ShimmerCategoryTile(
                          icon: category['icon'],
                          label: category['label'],
                        );
                      }, childCount: StaticCategories.categories.length),
                    ),
                  )
                // Actual content with fade animation
                else if (state is CategoriesWithStatusLoaded)
                  _buildCategoriesSliverGrid(state)
                else if (state is! CategoriesLoading &&
                    state is! CategoriesError)
                  // Fallback to static data with fade
                  _buildFallbackCategoriesGrid(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAllChannelsTab() {
    return BlocProvider(
      create: (context) => OrganizationsBloc()
        ..add(
          LoadOrganizationsByCategory(
            categoryId: null, // null loads all organizations
            categoryName: 'All Channels',
          ),
        ),
      child: _AllChannelsList(
        userRole: _userRole,
        managedOrganizations: _managedOrganizations,
        onRefresh: widget.onRefresh,
      ),
    );
  }

  Widget _buildExploreFeedTab() {
    // Get current user ID from auth state
    final authState = context.read<AuthBloc>().state;
    String? userId;
    if (authState is AuthAuthenticatedState && authState.userProfile != null) {
      userId = authState.userProfile!.id;
    }

    if (userId == null) {
      return const Center(
        child: Text('Please sign in to explore posts'),
      );
    }

    return BlocProvider(
      create: (context) => ExploreFeedBloc(),
      child: ExploreFeedTab(
        userId: userId,
        onRefresh: widget.onRefresh,
      ),
    );
  }

  Widget _buildCategoriesSliverGrid(CategoriesWithStatusLoaded state) {
    // Compute reordered categories once
    final categoryStatusMap = <String, bool>{};
    final categoryNameMap = <String, String>{};
    for (final apiCategory in state.categoriesWithStatus) {
      final id = apiCategory['id']?.toString();
      if (id != null) {
        categoryStatusMap[id] = apiCategory['isSelected'] ?? false;
        // Store API category name for sorting
        final apiName = apiCategory['name']?.toString();
        if (apiName != null) {
          categoryNameMap[id] = apiName;
        }
      }
    }
    final reorderedCategories = _reorderCategoriesByStatus(
      categoryStatusMap,
      categoryNameMap,
    );

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final category = reorderedCategories[index];
          final categoryId = category['id']?.toString();
          final isSelected = categoryId == null
              ? true
              : (categoryStatusMap[categoryId] ?? false);

          return FadeTransition(
            opacity: _fadeAnimation,
            child: CategoryTile(
              icon: category['icon'],
              label: category['label'],
              hasContent: isSelected,
              categoryId: category['id'],
              onOrganizationFollowChanged: widget.onRefresh,
            ),
          );
        }, childCount: reorderedCategories.length),
      ),
    );
  }

  Widget _buildFallbackCategoriesGrid() {
    final categories = StaticCategories.categories;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final category = categories[index];
          final isSelected = index == 0;

          return FadeTransition(
            opacity: _fadeAnimation,
            child: CategoryTile(
              icon: category['icon'],
              label: category['label'],
              hasContent: isSelected,
              categoryId: category['id'],
              onOrganizationFollowChanged: widget.onRefresh,
            ),
          );
        }, childCount: categories.length),
      ),
    );
  }

  /// Reorder categories: "All" first, then non-empty (alphabetically), then empty (alphabetically)
  List<Map<String, dynamic>> _reorderCategoriesByStatus(
    Map<String, bool> statusMap,
    Map<String, String> categoryNameMap,
  ) {
    final List<Map<String, dynamic>> reordered = [];

    // Always put "All" first
    final allCategory = StaticCategories.categories.firstWhere(
      (cat) => cat['id'] == null,
    );
    reordered.add(allCategory);

    // Separate categories with and without organizations
    final categoriesWithOrgs = <Map<String, dynamic>>[];
    final categoriesWithoutOrgs = <Map<String, dynamic>>[];

    for (final category in StaticCategories.categories) {
      if (category['id'] == null) continue; // Skip "All" as it's already added

      final categoryId = category['id']?.toString();
      final hasOrgs = statusMap[categoryId] ?? false;

      if (hasOrgs) {
        categoriesWithOrgs.add(category);
      } else {
        categoriesWithoutOrgs.add(category);
      }
    }

    // Helper function to get the name for sorting (prefer API name, fallback to static label)
    String getSortName(Map<String, dynamic> category) {
      final categoryId = category['id']?.toString();
      if (categoryId != null && categoryNameMap.containsKey(categoryId)) {
        return categoryNameMap[categoryId]!;
      }
      return category['label'] as String;
    }

    // Sort each group alphabetically (case-insensitive) using API names when available
    categoriesWithOrgs.sort(
      (a, b) => getSortName(
        a,
      ).toLowerCase().trim().compareTo(getSortName(b).toLowerCase().trim()),
    );
    categoriesWithoutOrgs.sort(
      (a, b) => getSortName(
        a,
      ).toLowerCase().trim().compareTo(getSortName(b).toLowerCase().trim()),
    );

    // Combine: All + Non-empty + Empty
    reordered.addAll(categoriesWithOrgs);
    reordered.addAll(categoriesWithoutOrgs);

    return reordered;
  }
}

// All Channels List Widget
class _AllChannelsList extends StatelessWidget {
  final UserRole? userRole;
  final List<Organization> managedOrganizations;
  final VoidCallback? onRefresh;

  const _AllChannelsList({
    this.userRole,
    this.managedOrganizations = const [],
    this.onRefresh,
  });

  List<Organization> _sortOrganizationsByPopularity(
    List<Organization> organizations,
  ) {
    final sorted = List<Organization>.from(organizations);
    sorted.sort((a, b) {
      final followerComparison = b.followerCount.compareTo(a.followerCount);
      if (followerComparison != 0) return followerComparison;
      return a.name.toLowerCase().trim().compareTo(
        b.name.toLowerCase().trim(),
      );
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrganizationsBloc, OrganizationsState>(
      builder: (context, state) {
        if (state is OrganizationsLoading) {
          return const Center(child: CircularProgressIndicator());
        } else if (state is OrganizationsError) {
          return _buildErrorView(context, state.message);
        } else if (state is OrganizationsLoaded ||
            state is OrganizationFollowLoading) {
          final allOrganizations = state is OrganizationsLoaded
              ? state.organizations
              : (state as OrganizationFollowLoading).organizations;

          final sortedOrganizations = _sortOrganizationsByPopularity(
            allOrganizations,
          );

          final loadingOrganizationId = state is OrganizationFollowLoading
              ? state.loadingOrganizationId
              : null;

          return RefreshIndicator(
            onRefresh: () async {
              context.read<OrganizationsBloc>().add(RefreshOrganizations());
            },
            child: sortedOrganizations.isEmpty
                ? _buildEmptyView()
                : ListView.separated(
                    itemCount: sortedOrganizations.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      color: AppTheme.dividerBackground,
                    ),
                    itemBuilder: (context, index) {
                      final organization = sortedOrganizations[index];
                      final isLoading =
                          loadingOrganizationId == organization.id;

                      return _CleanOrganizationCard(
                        organization: organization,
                        isLoading: isLoading,
                        userRole: userRole,
                        managedOrganizations: managedOrganizations,
                        onFollowPressed: () async {
                          final canContinue =
                              await ProfileUtils.showProfileCompletionBottomSheet(
                            context,
                            message:
                                'Please complete your profile to follow channels.',
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
                                FollowOrganization(
                                  organizationId: organization.id,
                                ),
                              );
                              await NotificationPreferencesService.instance
                                  .enableChannelNotification(organization.id);
                            }
                          }
                        },
                        onRefresh: onRefresh,
                      );
                    },
                  ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildEmptyView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        Icon(Icons.explore_outlined, size: 64, color: Colors.grey),
        SizedBox(height: 16),
        Center(
          child: Text(
            'No channels available',
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
        ),
        SizedBox(height: 8),
        Center(
          child: Text(
            'Channels will appear here once they are created.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.black45),
          ),
        ),
        SizedBox(height: 120),
      ],
    );
  }

  Widget _buildErrorView(BuildContext context, String message) {
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

// Clean Organization Card for All Channels list
class _CleanOrganizationCard extends StatelessWidget {
  final Organization organization;
  final bool isLoading;
  final UserRole? userRole;
  final List<Organization> managedOrganizations;
  final VoidCallback onFollowPressed;
  final VoidCallback? onRefresh;

  const _CleanOrganizationCard({
    required this.organization,
    required this.onFollowPressed,
    this.isLoading = false,
    this.userRole,
    this.managedOrganizations = const [],
    this.onRefresh,
  });

  bool get _canSeeFollowerCount {
    if (userRole?.isSuperAdmin == true) return true;
    if (userRole?.isAdmin == true) {
      return managedOrganizations.any((org) => org.id == organization.id);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _navigateToChat(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _navigateToOrganizationProfile(context),
              child: _buildOrganizationLogo(),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    organization.name,
                    style: AppTheme.chatTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_canSeeFollowerCount) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.people_outline, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          '${_formatFollowerCount(organization.followerCount)} ${organization.followerCount == 1 ? 'follower' : 'followers'}',
                          style: AppTheme.chatTimestamp,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFollowButton(),
                if (_showOpenChatButton || _showMessageButton) ...[
                  const SizedBox(height: 8),
                  _buildMessageButton(context),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrganizationLogo() {
    if (organization.logoUrl != null && organization.logoUrl!.isNotEmpty) {
      return Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: AppTheme.headerBackground,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Image.network(
            organization.logoUrl!,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : _buildDefaultLogo(),
            errorBuilder: (_, __, ___) => _buildDefaultLogo(),
          ),
        ),
      );
    }
    return _buildDefaultLogo();
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
          organization.name.isNotEmpty ? organization.name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildFollowButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 100,
      height: 36,
      child: isLoading
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
              onPressed: onFollowPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: organization.isFollowing
                    ? AppTheme.accentSecondary.withOpacity(0.1)
                    : AppTheme.accentPrimary,
                foregroundColor: organization.isFollowing
                    ? AppTheme.accentSecondary
                    : AppTheme.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                elevation: organization.isFollowing ? 0 : 2,
                shadowColor: AppTheme.accentPrimary.withOpacity(0.3),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    organization.isFollowing ? 'Un-follow' : 'Follow',
                    key: ValueKey(organization.isFollowing),
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

  Widget _buildMessageButton(BuildContext context) {
    final buttonText = _showOpenChatButton ? 'Open Chat' : 'Message';
    final buttonIcon = _showOpenChatButton ? Icons.chat_outlined : Icons.forum;

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

  bool get _showOpenChatButton {
    if (userRole?.isSuperAdmin == true) return true;
    if (userRole?.isAdmin == true) {
      return managedOrganizations.any((org) => org.id == organization.id);
    }
    return false;
  }

  // Only regular users (non-admin) see the Message button
  bool get _showMessageButton => userRole?.isAdminOrSuperAdmin != true;

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
      organizationId: organization.id,
    );
  }

  void _navigateToChat(BuildContext context) async {
    // Check if profile needs completion before navigating to channel
    final canContinue = await ProfileUtils.showProfileCompletionBottomSheet(
      context,
      message:
          'Please complete your profile to access channels and start chatting.',
    );

    if (canContinue && context.mounted) {
      // Pop back to the root of the Explore tab's navigator
      Navigator.of(context).popUntil((route) => route.isFirst);

      // Use the global key to access MainScaffold and switch to Channels tab
      mainScaffoldKey.currentState?.switchToChannelsTab(
        organizationId: organization.id,
      );
    }
  }

  void _navigateToOrganizationProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            OrganizationProfileScreen(organizationId: organization.id),
      ),
    ).then((result) {
      // If result is true, it means organization was unfollowed
      if (result == true && onRefresh != null) {
        onRefresh!();
      }
    });
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

// Shimmer effect category tile widget
class _ShimmerCategoryTile extends StatefulWidget {
  final IconData icon;
  final String label;

  const _ShimmerCategoryTile({required this.icon, required this.label});

  @override
  State<_ShimmerCategoryTile> createState() => _ShimmerCategoryTileState();
}

class _ShimmerCategoryTileState extends State<_ShimmerCategoryTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: AppTheme.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: [
                (_shimmerAnimation.value - 0.3).clamp(0.0, 1.0),
                _shimmerAnimation.value.clamp(0.0, 1.0),
                (_shimmerAnimation.value + 0.3).clamp(0.0, 1.0),
              ],
              colors: [
                Colors.grey.shade300.withOpacity(0.3),
                Colors.grey.shade100.withOpacity(0.3),
                Colors.grey.shade300.withOpacity(0.3),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon shimmer
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 8),
              // Label shimmer
              Container(
                width: widget.label.length * 6.0,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
