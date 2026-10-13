// lib/modules/admin/organizations_management_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/chat/widgets/image_carousel_screen.dart';
import 'package:mvc_app/widgets/app_tour_overlay.dart';
import 'package:mvc_app/modules/admin/create_organization.dart'
    show CreateOrganizationScreen;
import 'package:mvc_app/modules/admin/user_selector.dart';
import 'package:mvc_app/modules/chat/image_picker_service.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';
import 'package:mvc_app/modules/chat/widgets/management_button.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/api_service.dart';
import 'package:mvc_app/modules/channels/organization_profile_screen.dart';
import 'package:mvc_app/modules/channels/organization_followers_screen.dart';

class OrganizationsManagementScreen extends StatefulWidget {
  const OrganizationsManagementScreen({super.key});

  @override
  State<OrganizationsManagementScreen> createState() =>
      _OrganizationsManagementScreenState();
}

class _UserContextData {
  const _UserContextData({
    this.userId,
    this.role,
    required this.managedOrganizationIds,
  });

  final String? userId;
  final UserRole? role;
  final Set<String> managedOrganizationIds;
}

class _OrganizationsManagementScreenState
    extends State<OrganizationsManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ApiService _apiService = SupabaseApiService.instance;

  List<Organization> _allOrganizations = [];
  List<Organization> _filteredOrganizations = [];
  bool _isLoading = true;
  String? _error;
  UserRole? _currentUserRole;
  Set<String> _managedOrganizationIds = {};
  String? _checkingOrganizationId;

  @override
  void initState() {
    super.initState();
    _fetchOrganizations();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchOrganizations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final userContext = await _loadUserContext();

    try {
      final result = await _apiService.getAllOrganizations(
        orderBy: 'name',
        ascending: true,
      );

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        setState(() {
          _currentUserRole = userContext.role;
          _managedOrganizationIds = userContext.managedOrganizationIds;
          _allOrganizations = result.data!;
          _filteredOrganizations = List.from(_allOrganizations);
          _isLoading = false;
        });
      } else {
        setState(() {
          _currentUserRole = userContext.role;
          _managedOrganizationIds = userContext.managedOrganizationIds;
          _error = result.error ?? 'Failed to load channels';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _currentUserRole = userContext.role;
        _managedOrganizationIds = userContext.managedOrganizationIds;
        _error = 'An error occurred: $e';
        _isLoading = false;
      });
    }
  }

  Future<_UserContextData> _loadUserContext() async {
    try {
      final currentUser = await _apiService.getCurrentUser();

      if (currentUser == null ||
          !currentUser.isSuccess ||
          currentUser.userId == null) {
        return const _UserContextData(managedOrganizationIds: {});
      }

      final userId = currentUser.userId!;
      UserRole? role;

      final roleResult = await _apiService.getUserRole(userId);
      if (roleResult.isSuccess) {
        role = roleResult.data;
      }

      var managedIds = <String>{};
      if (role?.isAdmin == true) {
        final managedResult = await _apiService.getUserAdminOrganizations(
          userId,
        );
        if (managedResult.isSuccess && managedResult.data != null) {
          managedIds = managedResult.data!
              .map((organization) => organization.id)
              .toSet();
        }
      }

      return _UserContextData(
        userId: userId,
        role: role,
        managedOrganizationIds: managedIds,
      );
    } catch (_) {
      return const _UserContextData(managedOrganizationIds: {});
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();

    setState(() {
      if (query.isEmpty) {
        _filteredOrganizations = List.from(_allOrganizations);
      } else {
        _filteredOrganizations = _allOrganizations.where((org) {
          final name = org.name.toLowerCase();
          return name.contains(query);
        }).toList();
      }
    });
  }

  Widget _buildOrganizationsByCategory(
    String categoryTitle,
    List<Organization> organizations,
  ) {
    if (organizations.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(categoryTitle, style: AppTheme.managementHeading),
        ),
        ...organizations.map((org) => _buildOrganizationTile(org)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildOrganizationTile(Organization org) {
    final isCheckingAccess = _checkingOrganizationId == org.id;

    final managementButton = ManagementButton(
      icon: Container(
        width: AppTheme.iconSize * 2, // size of the icon itself
        height: AppTheme.iconSize * 2,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            AppTheme.iconSize / 1,
          ), // Squircle shape
          color: Colors.grey.shade100,
          image: org.logoUrl != null
              ? DecorationImage(
                  image: NetworkImage(org.logoUrl!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: org.logoUrl == null
            ? Center(
                child: Text(
                  org.name[0].toUpperCase(),
                  style: TextStyle(
                    color: AppTheme.accentSecondary,
                    fontSize: AppTheme.iconSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
      ),
      title: org.name,
      subtitle: org.name,
      onTap: isCheckingAccess ? () {} : () => _handleOrganizationTap(org),
    );

    if (!isCheckingAccess) {
      return managementButton;
    }

    return Stack(
      children: [
        Opacity(opacity: 0.6, child: managementButton),
        const Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrganizationHeader(Organization org) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Logo
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(128), // circle
              color: AppTheme.white,
              image: org.logoUrl != null
                  ? DecorationImage(
                      image: NetworkImage(org.logoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: org.logoUrl == null
                ? Center(
                    child: Text(
                      org.name[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 16),
          // Name
          Text(
            org.name,
            style: AppTheme.primaryHeading.copyWith(fontSize: 24),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _handleOrganizationTap(Organization org) async {
    final isSuperAdmin = _currentUserRole?.isSuperAdmin == true;
    if (isSuperAdmin || _managedOrganizationIds.contains(org.id)) {
      if (!mounted) return;
      _openOrganizationManagementSheet(org);
      return;
    }

    setState(() {
      _checkingOrganizationId = org.id;
    });

    bool canManage = false;
    bool permissionCheckFailed = false;

    try {
      final currentUser = await _apiService.getCurrentUser();

      if (currentUser != null &&
          currentUser.isSuccess &&
          currentUser.userId != null) {
        final accessResult = await _apiService.isUserAdminOfOrganization(
          currentUser.userId!,
          org.id,
        );
        canManage = accessResult.isSuccess && (accessResult.data ?? false);
      }
    } catch (_) {
      permissionCheckFailed = true;
    } finally {
      if (mounted) {
        setState(() {
          if (canManage) {
            _managedOrganizationIds = {..._managedOrganizationIds, org.id};
          }
          _checkingOrganizationId = null;
        });
      }
    }

    if (!mounted) return;

    if (permissionCheckFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to verify permissions right now. Showing read-only view.',
          ),
        ),
      );
    }

    if (canManage) {
      _openOrganizationManagementSheet(org);
    } else {
      _openOrganizationProfile(org);
    }
  }

  void _openOrganizationManagementSheet(Organization org) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildFullScreenOrganizationSheet(org),
    );
  }

  void _openOrganizationProfile(Organization org) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrganizationProfileScreen(organizationId: org.id),
      ),
    );
  }

  void _openOrganizationFollowers(Organization org) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrganizationFollowersScreen(
          organizationId: org.id,
          organizationName: org.name,
        ),
      ),
    );
  }

  Widget _buildFullScreenOrganizationSheet(Organization org) {
    return DraggableScrollableSheet(
      initialChildSize: 0.90,
      minChildSize: 0.5,
      maxChildSize: 0.90,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.secondaryHeadingColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    children: [
                      // Organization Header
                      _buildOrganizationHeader(org),
                      const SizedBox(height: 32),
                      // Details Section
                      _buildDetailsSection(org),
                      const SizedBox(height: 32),
                      // Actions Section
                      _buildActionsSection(org),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Widget _buildOrganizationHeader(Organization org) {
  //   return Container(
  //     padding: const EdgeInsets.all(24),
  //     child: Column(
  //       children: [
  //         // Logo
  //         CircleAvatar(
  //           radius: 60,
  //           backgroundImage: org.logoUrl != null
  //               ? NetworkImage(org.logoUrl!)
  //               : null,
  //           backgroundColor: AppTheme.iconBackground,
  //           child: org.logoUrl == null
  //               ? Text(
  //                   org.name[0].toUpperCase(),
  //                   style: const TextStyle(
  //                     color: Colors.white,
  //                     fontSize: 36,
  //                     fontWeight: FontWeight.bold,
  //                   ),
  //                 )
  //               : null,
  //         ),
  //         const SizedBox(height: 16),
  //         // Name
  //         Text(
  //           org.name,
  //           style: AppTheme.primaryHeading.copyWith(fontSize: 24),
  //           textAlign: TextAlign.center,
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildDetailsSection(Organization org) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardGreyBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.managementCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Channel Details',
            style: AppTheme.managementSubtitleText.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 16),
          _buildDetailRow('ID', org.id),
          _buildDetailRow(
            'Created At',
            '${org.createdAt.toLocal()}'.split(' ')[0],
          ),
          _buildDetailRow(
            'Updated At',
            '${org.updatedAt.toLocal()}'.split(' ')[0],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: AppTheme.managementTitleText.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(child: Text(value, style: AppTheme.managementTitleText)),
        ],
      ),
    );
  }

  Widget _buildActionsSection(Organization org) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Channel Actions',
            style: AppTheme.managementSubtitleText.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 16),
          _buildActionTile(
            icon: Icons.edit_outlined,
            title: 'Edit Channel',
            subtitle: 'Modify organization details',
            onTap: () => _showEditOrganizationSheet(org),
          ),
          _buildActionTile(
            icon: Icons.people_outline,
            title: 'View Followers',
            subtitle: 'See the users following this Channel',
            onTap: () => _openOrganizationFollowers(org),
          ),
          _buildActionTile(
            icon: Icons.manage_accounts_outlined,
            title: 'Manage Admins',
            subtitle: 'Add or remove Channel managers',
            onTap: () => _showManageAdminsSheet(org),
          ),
          _buildActionTile(
            icon: Icons.delete_outline,
            title: 'Delete Channel',
            subtitle: 'Permanently remove this Channel',
            onTap: () => _showDeleteOrganizationDialog(org),
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? Colors.red : AppTheme.primaryHeadingColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.managementCardBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTheme.chatTitle.copyWith(
                          color: color,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: AppTheme.managementTitleText.copyWith(
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: AppTheme.managementChevron,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditOrganizationSheet(Organization org) {
    Navigator.pop(context); // Close current sheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditOrganizationSheet(
        organization: org,
        onOrganizationUpdated: () {
          _fetchOrganizations(); // Refresh the list
        },
      ),
    );
  }

  void _showManageAdminsSheet(Organization org) {
    Navigator.pop(context); // Close current sheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ManageAdminsSheet(organization: org),
    );
  }

  void _showDeleteOrganizationDialog(Organization org) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Channel'),
        content: Text('Are you sure you want to delete ${org.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // ! Hidden for now
              final result = await _apiService.deleteOrganization(org.id);
              if (result.isSuccess) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Channel deleted successfully'),
                  ),
                );
                _fetchOrganizations(); // Refresh the list
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Error deleting Channel: ${result.error}',
                    ),
                  ),
                );
              }
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Channel Management'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchOrganizations,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateOrganizationScreen(),
                ),
              );
            },
            tooltip: 'Add Channel',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.headerBackground,
              border: Border(
                bottom: BorderSide(color: AppTheme.transparent, width: 0.5),
              ),
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search Channels by name...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppTheme.searchBarBackground,
              ),
            ),
          ),

          // Organizations list
          Expanded(child: _buildOrganizationsList()),
        ],
      ),
    );
  }

  Widget _buildOrganizationsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading Channels',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchOrganizations,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_filteredOrganizations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.business,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? 'No Channels found'
                  : 'No Channels match your search',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_searchController.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Try a different search term',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Group organizations by categories or alphabetically
    final aToH = _filteredOrganizations
        .where(
          (org) => RegExp(r'^[A-H]', caseSensitive: false).hasMatch(org.name),
        )
        .toList();
    final iToP = _filteredOrganizations
        .where(
          (org) => RegExp(r'^[I-P]', caseSensitive: false).hasMatch(org.name),
        )
        .toList();
    final qToZ = _filteredOrganizations
        .where(
          (org) => RegExp(r'^[Q-Z]', caseSensitive: false).hasMatch(org.name),
        )
        .toList();
    final other = _filteredOrganizations
        .where(
          (org) =>
              !RegExp(r'^[A-Z]', caseSensitive: false).hasMatch(org.name),
        )
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOrganizationsByCategory('Channels #', other),
          _buildOrganizationsByCategory('Channels A-H', aToH),
          _buildOrganizationsByCategory('Channels I-P', iToP),
          _buildOrganizationsByCategory('Channels Q-Z', qToZ),
        ],
      ),
    );
  }
}

// Edit Organization Sheet
class EditOrganizationSheet extends StatefulWidget {
  final Organization organization;
  final VoidCallback onOrganizationUpdated;

  const EditOrganizationSheet({
    super.key,
    required this.organization,
    required this.onOrganizationUpdated,
  });

  @override
  State<EditOrganizationSheet> createState() => _EditOrganizationSheetState();
}

class _EditOrganizationSheetState extends State<EditOrganizationSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _bioController = TextEditingController();
  final _websiteUrlController = TextEditingController();
  final _mapsUrlController = TextEditingController();
  final ApiService _apiService = SupabaseApiService.instance;

  bool _isLoading = false;
  bool _isUploadingLogo = false;
  bool _isLoadingCategories = true;
  bool _isUploadingPhoto = false;

  String? _logoUrl;
  String? _errorMessage;
  String? _successMessage;

  // Category management
  List<Map<String, dynamic>> _allCategories = [];
  Set<String> _selectedCategoryIds = {};

  // Photo management — mirrors organization_photos table rows
  List<OrgPhoto> _photos = [];

  bool _showingTour = false;

  List<TourStep> _buildEditTourSteps() => const [
        TourStep(
          title: 'Logo & Channel Name',
          body:
              'Tap the profile picture to change your logo. '
              'The channel name is what followers see everywhere in the app — '
              'keep it short and recognisable, e.g. "City Bakery".',
          icon: Icons.store_outlined,
        ),
        TourStep(
          title: 'Bio / Description',
          body:
              'A short paragraph about your channel shown on your public profile. '
              'Example: "The best artisan bread in town, baked fresh Mon–Sat 7 am–6 pm."',
          icon: Icons.info_outline,
        ),
        TourStep(
          title: 'Website & Google Maps Link',
          body:
              'Website — paste your main URL, e.g. "https://mybusiness.com".\n\n'
              'Google Maps Link — open Google Maps, find your place, tap '
              'Share → Copy link, then paste it here. '
              'Followers tap it to open the exact pin on their device.',
          icon: Icons.language_outlined,
        ),
        TourStep(
          title: 'Photos',
          body:
              'Add photos of your space so followers know what to expect. '
              'Tap "Add" to pick multiple images from your gallery. '
              'Tap × on any photo to remove it.\n\n'
              'Tip: bright, well-lit shots make the best impression.',
          icon: Icons.photo_library_outlined,
        ),
        TourStep(
          title: 'Categories',
          body:
              'Select the categories that best describe your channel — '
              'at least one is required. You can pick several if your channel '
              'spans multiple areas, e.g. "Food" + "Hospitality" for a café.',
          icon: Icons.category_outlined,
        ),
      ];

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.organization.name;
    _logoUrlController.text = widget.organization.logoUrl ?? '';
    _logoUrl = widget.organization.logoUrl;
    _bioController.text = widget.organization.bio ?? '';
    _websiteUrlController.text = widget.organization.websiteUrl ?? '';
    _mapsUrlController.text = widget.organization.mapsUrl ?? '';
    _photos = List.from(widget.organization.photos);
    // Don't set from widget.organization.categoryIds yet - we'll fetch fresh data
    _loadCategoriesAndAssignments();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _logoUrlController.dispose();
    _bioController.dispose();
    _websiteUrlController.dispose();
    _mapsUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadCategoriesAndAssignments() async {
    setState(() => _isLoadingCategories = true);

    try {
      // Load all categories
      final categoriesResult = await _apiService.getAll<Map<String, dynamic>>(
        'categories',
      );

      if (!categoriesResult.isSuccess) {
        throw Exception('Failed to load categories: ${categoriesResult.error}');
      }

      // Load current organization category assignments
      final assignmentsResult = await _apiService.getAll<Map<String, dynamic>>(
        'organization_categories',
        filters: {'organization_id': widget.organization.id},
      );

      if (!assignmentsResult.isSuccess) {
        throw Exception(
          'Failed to load category assignments: ${assignmentsResult.error}',
        );
      }

      // Extract the assigned category IDs
      final assignedCategoryIds = assignmentsResult.data!
          .map<String>((assignment) => assignment['category_id'].toString())
          .toSet();

      setState(() {
        _allCategories = categoriesResult.data!;
        _selectedCategoryIds = assignedCategoryIds;
        _isLoadingCategories = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading categories: $e';
        _isLoadingCategories = false;
      });
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate that at least one category is selected
    if (_selectedCategoryIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one category'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updatedOrg = Organization(
        id: widget.organization.id,
        name: _nameController.text.trim(),
        logoUrl: _logoUrl ?? widget.organization.logoUrl,
        bio: _bioController.text.trim().isEmpty ? null : _bioController.text.trim(),
        websiteUrl: _websiteUrlController.text.trim().isEmpty ? null : _websiteUrlController.text.trim(),
        mapsUrl: _mapsUrlController.text.trim().isEmpty ? null : _mapsUrlController.text.trim(),
        createdAt: widget.organization.createdAt,
        updatedAt: DateTime.now(),
        followerCount: widget.organization.followerCount,
        categoryIds: _selectedCategoryIds.toList(),
      );

      final result = await _apiService.updateOrganization(updatedOrg);

      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Channel updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onOrganizationUpdated();
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating Channel: ${result.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showLogoSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Change Logo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(
                Icons.camera_alt,
                color: AppTheme.primaryHeadingColor,
              ),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _uploadLogo(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: AppTheme.primaryHeadingColor,
              ),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _uploadLogo(ImageSource.gallery);
              },
            ),
            if (_logoUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remove Logo'),
                onTap: () {
                  Navigator.pop(context);
                  _removeLogo();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadLogo(ImageSource source) async {
    setState(() {
      _isUploadingLogo = true;
      _errorMessage = null;
    });

    try {
      final imageBytes = await ImagePickerService.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
      );

      if (imageBytes != null) {
        final result = await _apiService.uploadOrganizationLogo(
          fileName: "logo.png",
          organizationId: widget.organization.id,
          fileBytes: imageBytes,
        );

        if (result.isSuccess) {
          setState(() {
            _logoUrl = result.data;
            _logoUrlController.text = _logoUrl!;
            _successMessage = 'Logo updated successfully!';
          });
        } else {
          setState(() {
            _errorMessage = result.error ?? 'Failed to upload logo';
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to upload logo. Please try again.';
      });
    } finally {
      setState(() {
        _isUploadingLogo = false;
      });
    }
  }

  void _removeLogo() {
    setState(() {
      _logoUrl = null;
      _logoUrlController.text = '';
      _successMessage = 'Logo removed successfully!';
    });
  }

  void _toggleCategory(String categoryId) {
    setState(() {
      if (_selectedCategoryIds.contains(categoryId)) {
        // Don't allow removing the last category
        if (_selectedCategoryIds.length > 1) {
          _selectedCategoryIds.remove(categoryId);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Organization must belong to at least one category',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        _selectedCategoryIds.add(categoryId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.90,
      minChildSize: 0.5,
      maxChildSize: 0.90,
      builder: (context, scrollController) {
        return Stack(
          children: [
            Container(
          decoration: const BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.secondaryHeadingColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Edit Channel',
                                style: AppTheme.primaryHeading.copyWith(
                                  fontSize: 20,
                                ),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _saveChanges,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryHeadingColor,
                                foregroundColor: Colors.white,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Save'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Logo Section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(width: 40),
                            _buildLogoSection(),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(
                                Icons.help_outline,
                                color: AppTheme.secondaryHeadingColor,
                              ),
                              tooltip: 'How to fill this form',
                              onPressed: () =>
                                  setState(() => _showingTour = true),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Name Field
                        TextFormField(
                          controller: _nameController,
                          style: AppTheme.managementTitleText.copyWith(
                            color: AppTheme.primaryHeadingColor,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Channel Name',
                            labelStyle: AppTheme.managementTitleText.copyWith(
                              color: AppTheme.primaryHeadingColor,
                            ),
                            filled: true,
                            fillColor: AppTheme.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.managementCardBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.managementCardBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: AppTheme.primaryHeadingColor),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Bio Field
                        TextFormField(
                          controller: _bioController,
                          maxLines: 4,
                          style: AppTheme.managementTitleText.copyWith(
                            color: AppTheme.primaryHeadingColor,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Bio / Description',
                            labelStyle: AppTheme.managementTitleText.copyWith(
                              color: AppTheme.primaryHeadingColor,
                            ),
                            hintText: 'Tell followers what this channel is about…',
                            hintStyle: AppTheme.managementTitleText.copyWith(
                              color: AppTheme.primaryHeadingColor.withOpacity(0.4),
                            ),
                            alignLabelWithHint: true,
                            filled: true,
                            fillColor: AppTheme.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.managementCardBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.managementCardBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: AppTheme.primaryHeadingColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Website URL Field
                        TextFormField(
                          controller: _websiteUrlController,
                          keyboardType: TextInputType.url,
                          style: AppTheme.managementTitleText.copyWith(
                            color: AppTheme.primaryHeadingColor,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Website URL',
                            labelStyle: AppTheme.managementTitleText.copyWith(
                              color: AppTheme.primaryHeadingColor,
                            ),
                            hintText: 'https://example.com',
                            hintStyle: AppTheme.managementTitleText.copyWith(
                              color: AppTheme.primaryHeadingColor.withOpacity(0.4),
                            ),
                            prefixIcon: const Icon(Icons.language_outlined),
                            filled: true,
                            fillColor: AppTheme.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.managementCardBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.managementCardBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: AppTheme.primaryHeadingColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Google Maps Link Field
                        TextFormField(
                          controller: _mapsUrlController,
                          keyboardType: TextInputType.url,
                          style: AppTheme.managementTitleText.copyWith(
                            color: AppTheme.primaryHeadingColor,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Google Maps Link',
                            labelStyle: AppTheme.managementTitleText.copyWith(
                              color: AppTheme.primaryHeadingColor,
                            ),
                            hintText: 'https://maps.app.goo.gl/...',
                            hintStyle: AppTheme.managementTitleText.copyWith(
                              color: AppTheme.primaryHeadingColor.withOpacity(0.4),
                            ),
                            prefixIcon: const Icon(Icons.location_on_outlined),
                            filled: true,
                            fillColor: AppTheme.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.managementCardBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.managementCardBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: AppTheme.primaryHeadingColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Photos Section
                        _buildPhotosSection(),
                        const SizedBox(height: 24),

                        // Categories Section
                        _buildCategoriesSection(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
            if (_showingTour)
              AppTourOverlay(
                steps: _buildEditTourSteps(),
                onStepShown: (_) {},
                onFinish: () => setState(() => _showingTour = false),
                onSkip: () => setState(() => _showingTour = false),
              ),
          ],
        );
      },
    );
  }

  Future<void> _pickAndUploadPhotos() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;

    setState(() => _isUploadingPhoto = true);

    for (final xFile in picked) {
      Uint8List bytes = await xFile.readAsBytes();

      final uploadResult = await SupabaseApiService.instance.uploadGenericFile(
        fileBytes: bytes,
        fileName:
            'org_photo_${widget.organization.id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      if (!uploadResult.isSuccess || uploadResult.data == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(uploadResult.error ?? 'Failed to upload photo'),
              backgroundColor: Colors.red,
            ),
          );
        }
        continue;
      }

      final photoUrl = uploadResult.data as String;

      try {
        final row = await Supabase.instance.client
            .from('organization_photos')
            .insert({
              'organization_id': widget.organization.id,
              'photo_url': photoUrl,
              'display_order': _photos.length,
            })
            .select()
            .single();

        if (mounted) {
          setState(() {
            _photos.add(OrgPhoto(
              id: row['id'] as String,
              photoUrl: photoUrl,
            ));
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save photo: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    if (mounted) setState(() => _isUploadingPhoto = false);
  }

  Future<void> _deletePhoto(OrgPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove photo'),
        content: const Text('Remove this photo from the channel profile?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await _apiService.delete('organization_photos', photo.id);
    if (result.isSuccess && mounted) {
      setState(() => _photos.removeWhere((p) => p.id == photo.id));
    }
  }

  Widget _buildPhotosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Photos',
              style: AppTheme.managementSubtitleText.copyWith(fontSize: 18),
            ),
            const SizedBox(width: 8),
            Text(
              '(${_photos.length})',
              style: AppTheme.managementTitleText.copyWith(
                color: AppTheme.primaryHeadingColor,
              ),
            ),
            const Spacer(),
            if (_isUploadingPhoto)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              TextButton.icon(
                onPressed: _pickAndUploadPhotos,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryHeadingColor,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_photos.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.cardGreyBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.managementCardBorder),
            ),
            child: Column(
              children: [
                Icon(Icons.photo_library_outlined,
                    size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text(
                  'No photos yet',
                  style: AppTheme.managementTitleText.copyWith(
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 110,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              itemBuilder: (context, index) {
                final photo = _photos[index];
                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ImageCarouselScreen(
                        imageUrls: _photos.map((p) => p.photoUrl).toList(),
                        initialIndex: index,
                        theme: AppThemeMode.light,
                      ),
                    ),
                  ),
                  child: Container(
                    width: 100,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.grey.shade200,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(photo.photoUrl, fit: BoxFit.cover),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _deletePhoto(photo),
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close,
                                    size: 14, color: Colors.white),
                              ),
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
      ],
    );
  }

  Widget _buildLogoSection() {
    return GestureDetector(
      onTap: _isUploadingLogo ? null : _showLogoSourceDialog,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircleAvatar(
            radius: 60,
            backgroundImage: _logoUrl != null ? NetworkImage(_logoUrl!) : null,
            backgroundColor: AppTheme.white,
            child: _logoUrl == null
                ? Text(
                    widget.organization.name[0].toUpperCase(),
                    style: TextStyle(
                      color: AppTheme.primaryHeadingColor,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          if (_isUploadingLogo)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryHeadingColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.camera_alt,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Categories',
              style: AppTheme.managementSubtitleText.copyWith(fontSize: 18),
            ),
            const SizedBox(width: 8),
            Text(
              '(${_selectedCategoryIds.length} selected)',
              style: AppTheme.managementTitleText.copyWith(
                fontSize: 14,
                color: AppTheme.primaryHeadingColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Select at least one category for this Channel',
          style: AppTheme.managementTitleText.copyWith(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 16),

        if (_isLoadingCategories)
          const Center(child: CircularProgressIndicator())
        else if (_allCategories.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardGreyBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.managementCardBorder),
            ),
            child: const Text('No categories available'),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppTheme.cardGreyBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.managementCardBorder),
            ),
            child: Column(
              children: _allCategories.asMap().entries.map((entry) {
                final index = entry.key;
                final category = entry.value;
                final categoryId = category['id'].toString();
                final categoryName = category['name'].toString();
                final isSelected = _selectedCategoryIds.contains(categoryId);
                final isLastCategory =
                    _selectedCategoryIds.length == 1 && isSelected;

                return Column(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _toggleCategory(categoryId),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primaryHeadingColor
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primaryHeadingColor
                                        : Colors.grey[400]!,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 16,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      categoryName,
                                      style: AppTheme.chatTitle.copyWith(
                                        fontSize: 16,
                                        color: isSelected
                                            ? AppTheme.primaryHeadingColor
                                            : AppTheme.primaryHeadingColor,
                                      ),
                                    ),
                                    if (category['description'] != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        category['description'].toString(),
                                        style: AppTheme.managementTitleText
                                            .copyWith(
                                              fontSize: 14,
                                              color: Colors.grey[600],
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (isLastCategory)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Required',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange[800],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (index < _allCategories.length - 1)
                      const Divider(
                        height: 1,
                        thickness: 0.5,
                        color: AppTheme.managementCardBorder,
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

// Manage Admins Sheet
class ManageAdminsSheet extends StatefulWidget {
  final Organization organization;

  const ManageAdminsSheet({super.key, required this.organization});

  @override
  State<ManageAdminsSheet> createState() => _ManageAdminsSheetState();
}

class _ManageAdminsSheetState extends State<ManageAdminsSheet> {
  final ApiService _apiService = SupabaseApiService.instance;
  List<UserProfile> _managers = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchOrganizationManagers();
  }

  Future<void> _fetchOrganizationManagers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _apiService.getOrganizationManagers(
        widget.organization.id,
      );

      if (result.isSuccess && result.data != null) {
        setState(() {
          _managers = result.data!;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = result.error ?? 'Failed to load managers';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'An error occurred: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _addAdminToOrganization() async {
    try {
      final selectedUsers = await context.showUserSelector(
        title: 'Choose Admin User',
        allowMultipleSelection: false,
      );

      if (selectedUsers == null || selectedUsers.isEmpty) return;
      final selectedUser = selectedUsers.first;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const Center(child: CircularProgressIndicator()),
      );

      // TODO: remove after debugging BUG-001
      final diag = await Supabase.instance.client.rpc(
        'debug_promote_auth',
        params: {'p_org_id': widget.organization.id},
      );
      debugPrint('DIAG promote_auth: $diag');

      final result = await _apiService.assignUserAsOrganizationAdmin(
        selectedUser.email,
        widget.organization.id,
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${selectedUser.fullName ?? selectedUser.email} added as admin',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _fetchOrganizationManagers();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding admin: ${result.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _removeAdminFromOrganization(UserProfile admin) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Admin'),
        content: Text(
          'Are you sure you want to remove ${admin.fullName ?? admin.email} as admin?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (shouldRemove != true) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await _apiService.removeAdminFromOrganization(
        admin.email,
        widget.organization.id,
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${admin.fullName ?? admin.email} removed as admin'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchOrganizationManagers();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing admin: ${result.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.90,
      minChildSize: 0.5,
      maxChildSize: 0.90,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.secondaryHeadingColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Manage Admins',
                              style: AppTheme.primaryHeading.copyWith(
                                fontSize: 20,
                              ),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: _addAdminToOrganization,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryHeadingColor,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Add Admin'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Managers List
                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (_error != null)
                        Center(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        )
                      else if (_managers.isEmpty)
                        const Center(child: Text('No admins found'))
                      else
                        ..._managers.map(
                          (manager) => _buildManagerTile(manager),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildManagerTile(UserProfile manager) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardGreyBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundImage: manager.profilePictureUrl != null
                ? NetworkImage(manager.profilePictureUrl!)
                : null,
            child: manager.profilePictureUrl == null
                ? Text(
                    (manager.fullName ?? manager.email)[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  manager.fullName ?? 'No name',
                  style: AppTheme.chatTitle.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  manager.email,
                  style: AppTheme.managementTitleText.copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _removeAdminFromOrganization(manager),
            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
          ),
        ],
      ),
    );
  }
}
