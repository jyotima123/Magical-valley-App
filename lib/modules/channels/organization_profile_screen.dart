// lib/modules/organization/organization_profile_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/main_scaffold.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/chat/chat_service.dart';
import 'package:mvc_app/modules/chat/models/organization_event.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';
import 'package:mvc_app/modules/chat/organizations_bloc.dart';
import 'package:mvc_app/modules/channels/organization_followers_screen.dart';
import 'package:mvc_app/modules/chat/widgets/management_button.dart';
import 'package:mvc_app/modules/chat/widgets/image_carousel_screen.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/api_service.dart';
import 'package:mvc_app/utils/profile_utils.dart';
import 'package:url_launcher/url_launcher.dart';

class OrganizationProfileScreen extends StatefulWidget {
  final String organizationId;

  const OrganizationProfileScreen({super.key, required this.organizationId});

  @override
  State<OrganizationProfileScreen> createState() =>
      _OrganizationProfileScreenState();
}

class _OrganizationProfileScreenState extends State<OrganizationProfileScreen> {
  final ApiService _apiService = SupabaseApiService.instance;
  UserRole? _userRole;
  List<Organization> _managedOrganizations = [];
  bool _isUnfollowing = false;
  bool _isLoading = true;
  Organization? _currentOrganization;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchOrganizationAndUserData();
  }

  Future<void> _fetchOrganizationAndUserData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Fetch organization details
      await _fetchOrganizationDetails();

      // Fetch user role and managed organizations
      await _fetchUserRoleAndManagedOrganizations();
    } catch (e) {
      setState(() {
        _error = 'Failed to load organization details: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchOrganizationDetails() async {
    try {
      // You'll need to implement this method in your API service
      // For now, I'll show you how to use the organizations bloc to get the data
      final organizationsBloc = OrganizationsBloc();

      // Listen for the organization data
      organizationsBloc.stream.listen((state) {
        if (state is OrganizationsLoaded) {
          final organization = state.organizations.firstWhere(
            (org) => org.id == widget.organizationId,
            orElse: () => throw Exception('Organization not found'),
          );

          setState(() {
            _currentOrganization = organization;
            _isLoading = false;
          });
        } else if (state is OrganizationsError) {
          setState(() {
            _error = state.message;
            _isLoading = false;
          });
        }
      });

      // Force a fresh network fetch so the profile always shows the latest
      // bio, website, phone numbers, and addresses without being blocked by cache.
      organizationsBloc.add(
        LoadOrganizationsByCategory(
          categoryId: null,
          categoryName: '',
          forceRefresh: true,
        ),
      );
    } catch (e) {
      setState(() {
        _error = 'Failed to load organization: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchUserRoleAndManagedOrganizations() async {
    final currentUser = await _apiService.getCurrentUser();
    if (currentUser == null) return;

    final userRoleResult = await _apiService.getUserRole(
      currentUser.userId ?? "",
    );
    if (userRoleResult.isSuccess) {
      setState(() {
        _userRole = userRoleResult.data;
      });

      if (!_userRole!.isSuperAdmin) {
        final managedOrgsResult = await _apiService.getUserAdminOrganizations(
          currentUser.userId ?? "",
        );
        if (managedOrgsResult.isSuccess) {
          setState(() {
            _managedOrganizations = managedOrgsResult.data ?? [];
          });
        }
      }
    }
  }

  bool get _canSeeFollowerCount {
    if (_userRole?.isSuperAdmin == true) return true;
    if (_userRole?.isAdmin == true && _currentOrganization != null) {
      return _managedOrganizations.any(
        (org) => org.id == _currentOrganization!.id,
      );
    }
    return false;
  }

  Future<void> _handleUnfollow() async {
    if (_currentOrganization == null ||
        !_currentOrganization!.isFollowing ||
        _isUnfollowing)
      return;

    // Show confirmation dialog
    final shouldUnfollow = await _showUnfollowDialog();
    if (!shouldUnfollow) return;

    setState(() {
      _isUnfollowing = true;
    });

    try {
      // Use the API service directly instead of creating a new bloc
      final currentUser = await _apiService.getCurrentUser();
      if (currentUser == null || !currentUser.isSuccess) {
        throw Exception('User not authenticated');
      }

      // Get the user profile ID from the user_profiles table
      final userProfileResult = await _apiService.getAll<Map<String, dynamic>>(
        'user_profiles',
        filters: {'id': currentUser.userId},
        limit: 1,
      );

      if (!userProfileResult.isSuccess || userProfileResult.data!.isEmpty) {
        throw Exception('User profile not found');
      }

      final userProfileId = userProfileResult.data!.first['id'] as String;

      // Delete follow relationship
      final followResult = await _apiService.getAll<Map<String, dynamic>>(
        'user_follows',
        filters: {
          'user_id': userProfileId,
          'organization_id': _currentOrganization!.id,
        },
        limit: 1,
      );

      if (followResult.isSuccess && followResult.data!.isNotEmpty) {
        final followRecord = followResult.data!.first;
        if (followRecord.containsKey('id')) {
          final deleteResult = await _apiService.delete(
            'user_follows',
            followRecord['id'],
          );

          if (!deleteResult.isSuccess) {
            throw Exception(deleteResult.error ?? 'Failed to unfollow');
          }

          // Get updated follower count
          final followerCountResult = await _apiService
              .getAll<Map<String, dynamic>>(
                'public_follower_counts',
                filters: {'organization_id': _currentOrganization!.id},
                limit: 1,
              );

          int updatedFollowerCount = _currentOrganization!.followerCount - 1;
          if (followerCountResult.isSuccess &&
              followerCountResult.data!.isNotEmpty) {
            updatedFollowerCount =
                followerCountResult.data!.first['follower_count'] as int;
          }

          // Update the current organization state
          setState(() {
            _currentOrganization = _currentOrganization!.copyWith(
              isFollowing: false,
              followerCount: updatedFollowerCount,
            );
            _isUnfollowing = false;
          });

          // Refresh channels and update notification badge after unfollow
          try {
            await ChatService.refreshChannelsAndUpdateBadge(userProfileId);
          } catch (e) {
            print('Failed to refresh channels after unfollow: $e');
          }

          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Successfully unfollowed ${_currentOrganization!.name}',
                ),
                backgroundColor: Colors.green,
              ),
            );

            // Navigate back with result
            Navigator.of(context).pop(true);
            Navigator.of(context).pop(true);
          }
        } else {
          throw Exception('Unable to delete follow relationship');
        }
      } else {
        // Already unfollowed or follow relationship doesn't exist
        setState(() {
          _currentOrganization = _currentOrganization!.copyWith(
            isFollowing: false,
          );
          _isUnfollowing = false;
        });

        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      setState(() {
        _isUnfollowing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unfollow: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _showUnfollowDialog() async {
    if (_currentOrganization == null) return false;

    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Unfollow Organization'),
              content: Text(
                'Are you sure you want to unfollow ${_currentOrganization!.name}?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Unfollow'),
                ),
              ],
            );
          },
        ) ??
        false;
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

  Widget _buildOrganizationLogo({double size = 120}) {
    if (_currentOrganization == null) return const SizedBox.shrink();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size / 2),
        color: AppTheme.headerBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child:
          _currentOrganization!.logoUrl != null &&
              _currentOrganization!.logoUrl!.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(size / 2),
              child: Image.network(
                _currentOrganization!.logoUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return _buildDefaultLogo(size: size);
                },
                errorBuilder: (context, error, stackTrace) {
                  return _buildDefaultLogo(size: size);
                },
              ),
            )
          : _buildDefaultLogo(size: size),
    );
  }

  Widget _buildDefaultLogo({double size = 120}) {
    if (_currentOrganization == null) return const SizedBox.shrink();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size / 2),
        gradient: LinearGradient(
          colors: [Colors.blue[300]!, Colors.blue[600]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          _currentOrganization!.name.isNotEmpty
              ? _currentOrganization!.name[0].toUpperCase()
              : '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildErrorView()
          : _currentOrganization == null
          ? const Center(child: Text('Organization not found'))
          : _buildContent(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(
            'Failed to load organization',
            style: AppTheme.chatTitle,
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? 'Unknown error occurred',
            textAlign: TextAlign.center,
            style: AppTheme.managementTitleText,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _fetchOrganizationAndUserData,
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  String _followerText(int count) {
    return (count > 1) ? "followers" : "follower";
  }

  Widget _buildContent() {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Channel Profile'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header Section
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  // Organization Logo
                  _buildOrganizationLogo(),
                  const SizedBox(height: 24),

                  // Organization Name
                  Text(
                    _currentOrganization?.name ?? "No Name",
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  // Follower count (if user can see it)
                  if (_canSeeFollowerCount) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 16,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "${_formatFollowerCount(_currentOrganization?.followerCount ?? 0)} ${_followerText(_currentOrganization?.followerCount ?? 0)}",
                          style: AppTheme.chatTimestamp,
                        ),
                      ],
                    ),
                  ],

                  // Following status indicator
                  if (_currentOrganization?.isFollowing ?? true) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 14,
                            color: Colors.green[600],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Following',
                            style: AppTheme.chatTimestamp.copyWith(
                              color: Colors.green[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (_currentOrganization!.photos.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildPhotoGallery(),
            ],

            if (_hasBusinessInfo) ...[
              const SizedBox(height: 16),
              _buildBusinessInfoSection(),
            ],

            const SizedBox(height: 16),
            _buildActionsSection(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoGallery() {
    final photos = _currentOrganization!.photos;
    final urls = photos.map((p) => p.photoUrl).toList();

    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: photos.length,
        itemBuilder: (context, index) {
          final photo = photos[index];
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ImageCarouselScreen(
                  imageUrls: urls,
                  initialIndex: index,
                  theme: AppThemeMode.light,
                ),
              ),
            ),
            child: Container(
              width: 120,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey.shade200,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      photo.photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.broken_image_outlined,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    if (photo.caption != null && photo.caption!.isNotEmpty)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withOpacity(0.6),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Text(
                            photo.caption!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
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
    );
  }

  bool get _hasBusinessInfo {
    final org = _currentOrganization;
    if (org == null) return false;
    return (org.bio != null && org.bio!.isNotEmpty) ||
        (org.websiteUrl != null && org.websiteUrl!.isNotEmpty) ||
        (org.mapsUrl != null && org.mapsUrl!.isNotEmpty) ||
        org.phoneNumbers.isNotEmpty ||
        org.addresses.isNotEmpty;
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildBusinessInfoSection() {
    final org = _currentOrganization!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bio
          if (org.bio != null && org.bio!.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 20, color: Colors.grey.shade500),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    org.bio!.replaceAll('\\n', '\n'),
                    style: AppTheme.chatMessage.copyWith(
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Website
          if (org.websiteUrl != null && org.websiteUrl!.isNotEmpty) ...[
            if (org.bio != null && org.bio!.isNotEmpty)
              const SizedBox(height: 24),
            ManagementButton(
              icon: Icon(Icons.language, color: Colors.blue.shade600, size: 22),
              title: 'Website',
              subtitle: org.websiteUrl!
                  .replaceFirst(RegExp(r'^https?://'), ''),
              subtitleMaxLines: 1,
              showChevron: false,
              onTap: () => _launchUrl(
                org.websiteUrl!.startsWith('http')
                    ? org.websiteUrl!
                    : 'https://${org.websiteUrl!}',
              ),
            ),
          ],

          // Google Maps link
          if (org.mapsUrl != null && org.mapsUrl!.isNotEmpty) ...[
            if (org.websiteUrl != null || org.bio != null)
              const Divider(height: 8),
            ManagementButton(
              icon: Icon(Icons.location_on_outlined, color: Colors.red.shade500, size: 22),
              title: 'Location',
              subtitle: 'Open in Google Maps',
              showChevron: false,
              onTap: () => _launchUrl(org.mapsUrl!),
            ),
          ],

          // Phone numbers
          for (final phone in org.phoneNumbers) ...[
            if (org.websiteUrl != null ||
                org.mapsUrl != null ||
                org.bio != null ||
                org.phoneNumbers.first != phone)
              const Divider(height: 8),
            ManagementButton(
              icon: Icon(Icons.phone_outlined, color: Colors.green.shade600, size: 22),
              title: phone.label ?? 'Phone',
              subtitle: phone.phoneNumber,
              showChevron: false,
              onTap: () => _launchUrl('tel:${phone.phoneNumber}'),
            ),
          ],

          // Addresses
          for (final address in org.addresses) ...[
            if (org.phoneNumbers.isNotEmpty ||
                org.websiteUrl != null ||
                org.bio != null ||
                org.addresses.first != address)
              const Divider(height: 8),
            ManagementButton(
              icon: Icon(Icons.location_on_outlined, color: Colors.red.shade400, size: 22),
              title: address.label ?? 'Address',
              subtitle: address.formattedAddress.isNotEmpty
                  ? address.formattedAddress
                  : 'No address details',
              showChevron: false,
              onTap: () => _launchUrl(address.mapsLaunchUrl),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionsSection() {
    if (_currentOrganization == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(
                icon: Icons.chat_bubble_outline,
                label: 'View',
                color: Colors.green.shade600,
                onTap: _openChannel,
              ),
              _buildActionButton(
                icon: Icons.forum,
                label: 'Message',
                color: Colors.orange.shade700,
                onTap: _startDirectMessage,
              ),
              if (_canSeeFollowerCount)
                _buildActionButton(
                  icon: Icons.people_outline,
                  label: 'Followers',
                  color: Colors.blue.shade600,
                  onTap: _openFollowersScreen,
                ),
            ],
          ),

          if (_currentOrganization?.isFollowing ?? true) ...[
            const Divider(height: 28, color: AppTheme.cardGreyBackground),
            GestureDetector(
              onTap: _isUnfollowing ? null : _handleUnfollow,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isUnfollowing)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.red.shade400),
                      ),
                    )
                  else
                    Icon(Icons.person_remove_outlined, size: 16, color: Colors.red.shade400),
                  const SizedBox(width: 6),
                  Text(
                    _isUnfollowing ? 'Unfollowing...' : 'Unfollow channel',
                    style: AppTheme.chatTimestamp.copyWith(
                      color: Colors.red.shade400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppTheme.chatTimestamp.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _openChannel() {
    if (_currentOrganization == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            OrganizationProfileScreen(organizationId: _currentOrganization!.id),
      ),
    );

    // // For now, just close this screen to return to the channel
    // Navigator.of(context).pop();
  }

  void _openFollowersScreen() {
    if (_currentOrganization == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OrganizationFollowersScreen(
          organizationId: _currentOrganization!.id,
          organizationName: _currentOrganization!.name,
        ),
      ),
    );
  }

  Future<void> _startDirectMessage() async {
    if (_currentOrganization == null) return;

    // For admins, just switch to the Direct Messages tab
    if (_userRole?.isAdminOrSuperAdmin == true) {
      // Pop back to the root first
      Navigator.of(context).popUntil((route) => route.isFirst);
      // Switch to Direct Messages tab
      mainScaffoldKey.currentState?.switchToDirectMessagesTab();
      return;
    }

    // For regular users, check profile first
    final canContinue = await ProfileUtils.showProfileCompletionBottomSheet(
      context,
      message: 'Please complete your profile to send messages.',
    );

    if (!canContinue || !mounted) return;

    // Pop back to the root first
    Navigator.of(context).popUntil((route) => route.isFirst);

    // Switch to Direct Messages tab and open conversation with this organization
    mainScaffoldKey.currentState?.switchToDirectMessagesTab(
      organizationId: _currentOrganization!.id,
    );
  }

}
