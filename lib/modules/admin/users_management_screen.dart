// lib/modules/admin/users_management_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/admin/edit_user_screen.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';
import 'package:mvc_app/modules/chat/widgets/management_button.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/api_service.dart';

class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({super.key});

  @override
  State<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends State<UsersManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ApiService _apiService = SupabaseApiService.instance;

  List<UserProfile> _allUsers = [];
  List<UserProfile> _filteredUsers = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _apiService.getAll<Map<String, dynamic>>(
        'user_profiles',
        orderBy: 'full_name',
        ascending: true,
      );

      if (result.isSuccess && result.data != null) {
        setState(() {
          _allUsers = (result.data! as List)
              .map((item) => UserProfile.fromJson(item))
              .toList();
          _filteredUsers = List.from(_allUsers);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = result.error ?? 'Failed to load users';
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

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();

    setState(() {
      if (query.isEmpty) {
        _filteredUsers = List.from(_allUsers);
      } else {
        _filteredUsers = _allUsers.where((user) {
          final name = user.fullName?.toLowerCase() ?? '';
          final email = user.email.toLowerCase();
          final role = user.role.value.toLowerCase();
          return name.contains(query) ||
              email.contains(query) ||
              role.contains(query);
        }).toList();
      }
    });
  }

  Future<List<Organization>> _fetchUserManagedOrganizations(
    String userId,
  ) async {
    try {
      final result = await _apiService.getUserManagedOrganizations(userId);
      if (result.isSuccess && result.data != null) {
        return result.data!;
      } else {
        throw Exception(result.error ?? 'Failed to load organizations');
      }
    } catch (e) {
      throw Exception('Error loading organizations: $e');
    }
  }

  List<UserProfile> _getUsersByRole(String role) {
    return _filteredUsers
        .where((user) => user.role.value.toLowerCase() == role.toLowerCase())
        .toList();
  }

  Widget _buildUsersByRole(String roleTitle, List<UserProfile> users) {
    if (users.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(roleTitle, style: AppTheme.managementHeading),
        ),
        ...users.map((user) => _buildUserTile(user)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildUserTile(UserProfile user) {
    return ManagementButton(
      icon: CircleAvatar(
        radius: AppTheme.iconSize / 2,
        backgroundImage: user.profilePictureUrl != null
            ? NetworkImage(user.profilePictureUrl!)
            : null,
        backgroundColor: AppTheme.iconBackground,
        child: user.profilePictureUrl == null
            ? Text(
                user.fullName?.isNotEmpty == true
                    ? user.fullName![0].toUpperCase()
                    : user.email[0].toUpperCase(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppTheme.iconSize / 3,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
      title: user.fullName ?? 'No name',
      subtitle: user.email,
      onTap: () => _handleUserTap(user),
    );
  }

  void _handleUserTap(UserProfile user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildFullScreenUserSheet(user),
    );
  }

  Widget _buildFullScreenUserSheet(UserProfile user) {
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
                      // Profile Section
                      _buildProfileHeader(user),

                      const SizedBox(height: 32),

                      // Company Management Section
                      _buildCompanyManagementSection(user),

                      const SizedBox(height: 32),

                      // Actions Section
                      _buildActionsSection(user),

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

  Widget _buildProfileHeader(UserProfile user) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Large Profile Picture
          CircleAvatar(
            radius: 60,
            backgroundImage: user.profilePictureUrl != null
                ? NetworkImage(user.profilePictureUrl!)
                : null,
            backgroundColor: AppTheme.iconBackground,
            child: user.profilePictureUrl == null
                ? Text(
                    user.fullName?.isNotEmpty == true
                        ? user.fullName![0].toUpperCase()
                        : user.email[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),

          const SizedBox(height: 16),

          // User Name
          Text(
            user.fullName ?? 'No name',
            style: AppTheme.primaryHeading.copyWith(fontSize: 24),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          // Email
          Text(
            user.email,
            style: AppTheme.secondaryHeading.copyWith(fontSize: 16),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12),

          // Role Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _getRoleColor(user.role.value),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              user.role.value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyManagementSection(UserProfile user) {
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
          Row(
            children: [
              Icon(
                Icons.business,
                color: AppTheme.primaryHeadingColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Company Management',
                style: AppTheme.managementSubtitleText.copyWith(fontSize: 18),
              ),
              Expanded(child: SizedBox(width: 12.0)),
              Icon(Icons.edit, color: AppTheme.primaryHeadingColor, size: 24),
            ],
          ),

          const SizedBox(height: 16),

          _buildCompanyManagementContent(user),
        ],
      ),
    );
  }

  Widget _buildCompanyManagementContent(UserProfile user) {
    final role = user.role.value.toLowerCase();

    if (role == 'superadmin') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.purple.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.purple.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.admin_panel_settings, color: Colors.purple, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'This user has super admin privileges and can manage any company in the system.',
                style: AppTheme.managementTitleText.copyWith(
                  color: Colors.purple[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (role == 'admin') {
      return FutureBuilder<List<Organization>>(
        future: _fetchUserManagedOrganizations(user.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (snapshot.hasError) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700], size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Failed to load managed organizations: ${snapshot.error}',
                      style: AppTheme.managementTitleText.copyWith(
                        color: Colors.red[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final organizations = snapshot.data ?? [];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Managed Companies (${organizations.length})',
                style: AppTheme.managementTitleText.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryHeadingColor,
                ),
              ),

              const SizedBox(height: 12),

              if (organizations.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.grey[700],
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This admin is not managing any organizations yet.',
                          style: AppTheme.managementTitleText.copyWith(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...organizations.map(
                  (organization) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.managementCardBorder),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: organization.logoUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    organization.logoUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        Icons.business,
                                        color: Colors.blue,
                                        size: 20,
                                      );
                                    },
                                  ),
                                )
                              : Icon(
                                  Icons.business,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                organization.name,
                                style: AppTheme.chatTitle.copyWith(
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'ID: ${organization.id} • ${organization.followerCount} followers',
                                style: AppTheme.managementTitleText.copyWith(
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: AppTheme.managementChevron,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange[700], size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'This user cannot manage any organizations. Admin privileges are required for company management.',
                style: AppTheme.managementTitleText.copyWith(
                  color: Colors.orange[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildActionsSection(UserProfile user) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'User Actions',
            style: AppTheme.managementSubtitleText.copyWith(fontSize: 18),
          ),

          const SizedBox(height: 16),

          // _buildActionTile(
          //   icon: Icons.person_outline,
          //   title: 'View Profile',
          //   subtitle: 'View detailed user information',
          //   onTap: () {
          //     Navigator.pop(context);
          //     ScaffoldMessenger.of(context).showSnackBar(
          //       const SnackBar(content: Text('User profile view coming soon')),
          //     );
          //   },
          // ),
          // Show edit button for superadmins (any user) or any user editing themselves
          if (_isCurrentUserSuperAdmin() || _isCurrentUser(user))
            _buildActionTile(
              icon: Icons.edit_outlined,
              title: 'Edit User',
              subtitle: 'Modify user details and settings',
              onTap: () {
                Navigator.pop(context);
                _navigateToEditUser(user);
              },
            ),

          // Only show role change button if user is not superadmin
          if (user.role != UserRole.superadmin)
            _buildActionTile(
              icon: Icons.security_outlined,
              title: 'Change User Role',
              subtitle: (user.role == UserRole.admin)
                  ? 'Convert into superadmin or Downgrade to regular user'
                  : 'Promote user to admin or superadmin',
              isEnabled: false,
            ),

          if (user.role.value.toLowerCase() != 'superadmin')
            _buildActionTile(
              icon: Icons.block_outlined,
              title: 'Suspend User',
              subtitle: 'Temporarily disable user access',
              isDestructive: true,
              isEnabled: false,
            ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool isDestructive = false,
    bool isEnabled = true,
  }) {
    final baseColor =
        isDestructive ? Colors.red : AppTheme.primaryHeadingColor;
    final color = isEnabled ? baseColor : Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: isEnabled && onTap != null ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(
                color: isEnabled
                    ? AppTheme.managementCardBorder
                    : AppTheme.managementCardBorder.withOpacity(0.5),
              ),
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

  void _showSuspendUserDialog(UserProfile user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Suspend User'),
        content: Text(
          'Are you sure you want to suspend ${user.fullName ?? user.email}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User suspension coming soon')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Suspend'),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'superadmin':
        return Colors.purple;
      case 'admin':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  bool _isCurrentUserSuperAdmin() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticatedState && authState.userProfile != null) {
      return authState.userProfile!.role == UserRole.superadmin;
    }
    return false;
  }

  bool _isCurrentUser(UserProfile user) {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticatedState) {
      return authState.userId == user.id;
    }
    return false;
  }

  void _navigateToEditUser(UserProfile user) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => EditUserScreen(user: user)),
    ).then((_) {
      // Refresh the user list when returning from edit screen
      _fetchUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users Management'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchUsers,
            tooltip: 'Refresh',
          ),
          // TODO: Is it really needed?
          // IconButton(
          //   icon: const Icon(Icons.person_add),
          //   onPressed: () {
          //     ScaffoldMessenger.of(context).showSnackBar(
          //       const SnackBar(
          //         content: Text('Add user functionality coming soon'),
          //       ),
          //     );
          //   },
          //   tooltip: 'Add User',
          // ),
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
                hintText: 'Search users by name, email, or role...',
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

          // Users list
          Expanded(child: _buildUsersList()),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
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
              'Error loading users',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchUsers, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_filteredUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_search,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? 'No users found'
                  : 'No users match your search',
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

    // final superadmins = _getUsersByRole('superadmin');
    final admins = _getUsersByRole('admin');
    final users = _getUsersByRole('regular');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // _buildUsersByRole('Super Admins', superadmins),
          _buildUsersByRole('Organization Admins', admins),
          _buildUsersByRole('Regular Users', users),
        ],
      ),
    );
  }
}
