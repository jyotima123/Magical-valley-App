import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/channels/organization_profile_screen.dart';
import 'package:mvc_app/modules/chat/chat_service.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';
import 'package:mvc_app/services/api_repository.dart';

class OrganizationsIFollowScreen extends StatefulWidget {
  const OrganizationsIFollowScreen({super.key});

  @override
  State<OrganizationsIFollowScreen> createState() =>
      _OrganizationsIFollowScreenState();
}

class _OrganizationsIFollowScreenState
    extends State<OrganizationsIFollowScreen> {
  List<Organization>? _followedOrganizations;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFollowedOrganizations();
  }

  Future<void> _loadFollowedOrganizations() async {
    print("🔍 Starting to load followed organizations...");

    final authState = context.read<AuthBloc>().state;
    print("🔍 Auth State Type: ${authState.runtimeType}");
    print("🔍 Auth State: $authState");

    if (authState is! AuthAuthenticatedState) {
      print("🔴 User is not in authenticated state");
      setState(() {
        _isLoading = false;
        _errorMessage =
            'User not authenticated - State: ${authState.runtimeType}';
      });
      return;
    }

    if (authState.userProfile?.id == null) {
      print("🔴 User profile or ID is null");
      print("🔍 User Profile: ${authState.userProfile}");
      setState(() {
        _isLoading = false;
        _errorMessage = 'User profile not found';
      });
      return;
    }

    print("✅ User authenticated with ID: ${authState.userProfile!.id}");

    try {
      print("🔍 Getting ApiRepository...");
      final apiRepository = context.read<ApiRepository>();
      print("✅ ApiRepository obtained: ${apiRepository.runtimeType}");

      print("🔍 Calling getUserFollowedOrganizations...");
      final result = await apiRepository.getUserFollowedOrganizations(
        authState.userProfile!.id,
      );
      print(
        "🔍 API Result: Success=${result.isSuccess}, Data=${result.data?.length ?? 'null'}, Error=${result.error}",
      );

      if (result.isSuccess) {
        print(
          "✅ Successfully loaded ${result.data?.length ?? 0} organizations",
        );
        setState(() {
          _followedOrganizations = result.data;
          _isLoading = false;
        });
      } else {
        print("🔴 API call failed: ${result.error}");
        setState(() {
          _errorMessage =
              result.error ?? 'Failed to load followed organizations';
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      print("🔴🔴🔴🔴🔴🔴🔴ERROR $e");
      print("🔴 Stack trace: $stackTrace");
      setState(() {
        _errorMessage = 'An error occurred while loading organizations: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _unfollowOrganization(String organizationId) async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticatedState ||
        authState.userProfile?.id == null) {
      return;
    }

    try {
      final apiRepository = context.read<ApiRepository>();
      final result = await apiRepository.unfollowOrganization(
        authState.userProfile!.id,
        organizationId,
      );

      if (result.isSuccess) {
        // Remove the organization from the local list
        setState(() {
          _followedOrganizations?.removeWhere(
            (org) => org.id == organizationId,
          );
        });

        // Refresh channels and update notification badge after unfollow
        try {
          await ChatService.refreshChannelsAndUpdateBadge(
            authState.userProfile!.id,
          );
        } catch (e) {
          print('Failed to refresh channels after unfollow: $e');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Successfully unfollowed organization'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'Failed to unfollow organization'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e, stacktrace) {
      print("Error unfollow $e, $stacktrace");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An error occurred while unfollowing'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showUnfollowDialog(Organization organization) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unfollow Organization'),
        content: Text(
          'Are you sure you want to unfollow ${organization.name}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _unfollowOrganization(organization.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Unfollow'),
          ),
        ],
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  String _getOrganizationInitials(String name) {
    if (name.isEmpty) return 'O';
    final words = name.split(' ');
    if (words.length == 1) {
      return words[0][0].toUpperCase();
    }
    return (words[0][0] + words[words.length - 1][0]).toUpperCase();
  }

  void _navigateToOrganizationProfile(Organization organization) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            OrganizationProfileScreen(organizationId: organization.id),
      ),
    );
  }

  void _navigateToChat(Organization organization) {
    // Navigate to the chat screen and select this organization's channel
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/home',
      (route) => false,
      arguments: {'organizationId': organization.id},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Organizations I Follow'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
              _loadFollowedOrganizations();
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
                _loadFollowedOrganizations();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF28C6A),
              ),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (_followedOrganizations == null || _followedOrganizations!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.business_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No organizations followed yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Start following organizations to see them here',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFollowedOrganizations,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _followedOrganizations!.length,
        itemBuilder: (context, index) {
          final organization = _followedOrganizations![index];
          return _buildOrganizationCard(organization);
        },
      ),
    );
  }

  Widget _buildOrganizationCard(Organization organization) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.headerBackground,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: GestureDetector(
          onTap: () => _navigateToOrganizationProfile(organization),
          child: CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFF28C6A),
            backgroundImage:
                organization.logoUrl != null && organization.logoUrl!.isNotEmpty
                ? NetworkImage(organization.logoUrl!)
                : null,
            child: organization.logoUrl == null || organization.logoUrl!.isEmpty
                ? Text(
                    _getOrganizationInitials(organization.name),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
        ),
        title: GestureDetector(
          onTap: () => _navigateToChat(organization),
          child: Text(
            organization.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        subtitle: Text(
          // '${organization.followerCount ?? 0} followers',
          '',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _getTimeAgo(organization.createdAt),
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => _showUnfollowDialog(organization),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Unfollow',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
        onTap: () => _navigateToChat(organization),
      ),
    );
  }
}
