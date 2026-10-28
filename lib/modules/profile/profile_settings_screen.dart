import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/modules/profile/privacy_policy_screen.dart';
import 'package:mvc_app/modules/profile/terms_and_conditions_screen.dart';
import 'package:mvc_app/modules/profile/organizations_i_follow_screen.dart';
import 'package:mvc_app/modules/profile/profile_edit_screen.dart';
import 'package:mvc_app/modules/profile/qa_unread_messages_debug_screen.dart';
import 'package:mvc_app/modules/profile/qa_post_views_debug_screen.dart';
import 'package:mvc_app/modules/profile/profile_onboarding_screen.dart';
import 'package:mvc_app/modules/profile/feedback_screen.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/flavour_config.dart';
import 'package:mvc_app/services/first_run_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mvc_app/services/amplitude_service.dart';
import 'package:mvc_app/main_scaffold.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _hasRequestedManagedOrganizations = false;
  bool _isLoadingManagedOrganizations = false;
  bool _hasManagedOrganizationsLoaded = false;
  String? _managedOrganizationsError;
  List<Organization> _managedOrganizations = [];

  @override
  void initState() {
    super.initState();
    // Ensure we have the latest user data
    context.read<AuthBloc>().add(CheckAuthStatusEvent());
    // Show first-time hint dialog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowFirstTimeHint();
    });
  }

  Future<void> _maybeShowFirstTimeHint() async {
    await FirstRunService.instance.maybeShowHint(
      context,
      key: FirstRunHintKeys.profileSettings,
      icon: Icons.settings,
    );
  }


  Future<void> _loadManagedOrganizations(String userId) async {
    setState(() {
      _isLoadingManagedOrganizations = true;
      _managedOrganizationsError = null;
    });

    try {
      final result = await SupabaseApiService.instance.getUserManagedOrganizations(userId);

      if (!mounted) {
        return;
      }

      if (result.isSuccess && result.data != null) {
        setState(() {
          _managedOrganizations = result.data!;
          _hasManagedOrganizationsLoaded = true;
          _isLoadingManagedOrganizations = false;
        });
      } else {
        setState(() {
          _managedOrganizations = [];
          _managedOrganizationsError =
              result.error ?? 'Failed to load managed organizations.';
          _hasManagedOrganizationsLoaded = true;
          _isLoadingManagedOrganizations = false;
        });
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _managedOrganizations = [];
        _managedOrganizationsError =
            'Failed to load managed organizations. Please try again.';
        _hasManagedOrganizationsLoaded = true;
        _isLoadingManagedOrganizations = false;
      });
    }
  }

  void _clearManagedOrganizationsState() {
    if (!mounted) return;

    final shouldReset =
        _managedOrganizations.isNotEmpty ||
        _isLoadingManagedOrganizations ||
        _hasManagedOrganizationsLoaded ||
        _managedOrganizationsError != null;

    if (!shouldReset) return;

    setState(() {
      _managedOrganizations = [];
      _isLoadingManagedOrganizations = false;
      _hasManagedOrganizationsLoaded = false;
      _managedOrganizationsError = null;
    });
    _hasRequestedManagedOrganizations = false;
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
        title: const Text('Profile'),
      ),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticatedState) {
            final userProfile = state.userProfile;

            if (userProfile != null && userProfile.role.isAdmin) {
              final hasManagedOrgsInState =
                  state.managedOrganizations.isNotEmpty;

              if (hasManagedOrgsInState &&
                  (state.managedOrganizations.length !=
                          _managedOrganizations.length ||
                      !_hasManagedOrganizationsLoaded)) {
                setState(() {
                  _managedOrganizations = state.managedOrganizations;
                  _hasManagedOrganizationsLoaded = true;
                  _isLoadingManagedOrganizations = false;
                  _managedOrganizationsError = null;
                });
              } else if (!_hasRequestedManagedOrganizations &&
                  !_isLoadingManagedOrganizations &&
                  !_hasManagedOrganizationsLoaded) {
                _hasRequestedManagedOrganizations = true;
                _loadManagedOrganizations(userProfile.id);
              }
            } else {
              _clearManagedOrganizationsState();
            }
          } else if (state is AuthErrorState) {
            // Show error message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          } else {
            _clearManagedOrganizationsState();
          }
        },
        builder: (context, state) {
          if (state is AuthLoadingState) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (state is AuthAuthenticatedState) {
            return _buildAuthenticatedContent(state);
          }

          return _buildUnauthenticatedContent();
        },
      ),
    );
  }

  Widget _buildAuthenticatedContent(AuthAuthenticatedState state) {
    final userProfile = state.userProfile;

    return Column(
        children: [
          // Profile Picture Section
          _buildProfilePictureSection(userProfile: userProfile),

          // Settings list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (userProfile != null && userProfile.role.isAdminOrSuperAdmin) ...[
                  _buildRoleAndOrganizationSection(userProfile),
                  const SizedBox(height: 12),
                ],

                // Edit Profile
                _buildSettingsItem(
                  icon: Icons.edit_outlined,
                  label: 'Edit Profile',
                  onTap: () {
                    AmplitudeService.instance.logEvent('profile_screen_tapped', eventProperties: {'item': 'edit_profile'});
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileEditScreen(),
                      ),
                    );
                  },
                ),
                // Profile Setup Wizard (only visible in QA flavor)
                if (FlavorConfig.supabaseEnvironment == 'qa') ...[
                  SizedBox(height: 4),
                  _buildSettingsItem(
                    icon: Icons.person_add_outlined,
                    label: 'QA: Setup Profile Wizard',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfileOnboardingScreen(),
                        ),
                      );
                    },
                  ),
                ],
                SizedBox(height: 4),
                // Account settings
                _buildSettingsItem(
                  icon: Icons.manage_accounts_outlined,
                  label: 'Account settings',
                  onTap: () {
                    AmplitudeService.instance.logEvent('profile_screen_tapped', eventProperties: {'item': 'account_settings'});
                    _showAccountSettingsSheet();
                  },
                ),
                SizedBox(height: 4),
                // Organizations I Follow
                _buildSettingsItem(
                  icon: Icons.business,
                  label: 'Channels I Follow',
                  onTap: () {
                    AmplitudeService.instance.logEvent('profile_screen_tapped', eventProperties: {'item': 'channels_followed'});
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const OrganizationsIFollowScreen(),
                      ),
                    );
                  },
                ),
                // QA: Unread Messages Debug (only visible in QA flavor)
                if (FlavorConfig.supabaseEnvironment == 'qa') ...[
                  SizedBox(height: 4),
                  _buildSettingsItem(
                    icon: Icons.bug_report,
                    label: 'QA: Unread Messages Debug',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const QAUnreadMessagesDebugScreen(),
                        ),
                      );
                    },
                  ),
                ],
                // Post Views Debug (superadmins only, all environments)
                if (userProfile?.role.isSuperAdmin == true) ...[
                  SizedBox(height: 4),
                  _buildSettingsItem(
                    icon: Icons.visibility,
                    label: 'Post Views',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const QAPostViewsDebugScreen(),
                        ),
                      );
                    },
                  ),
                ],
                SizedBox(height: 4),
                _buildSettingsItem(
                  icon: Icons.tour_outlined,
                  label: 'Tour me through the app',
                  onTap: () {
                    AmplitudeService.instance.logEvent('profile_screen_tapped', eventProperties: {'item': 'app_tour'});
                    Navigator.pop(context);
                    // Start the tour from MainScaffold
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      mainScaffoldKey.currentState?.startTour();
                    });
                  },
                ),
                SizedBox(height: 4),
                _buildSettingsItem(
                  icon: Icons.feedback_outlined,
                  label: 'Send Feedback',
                  onTap: () {
                    AmplitudeService.instance.logEvent('profile_screen_tapped', eventProperties: {'item': 'send_feedback'});
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FeedbackScreen(),
                      ),
                    );
                  },
                ),
                SizedBox(height: 4),
                _buildSettingsItem(
                  icon: Icons.help_outline,
                  label: 'About this App',
                  onTap: () {
                    AmplitudeService.instance.logEvent('profile_screen_tapped', eventProperties: {'item': 'about'});
                    _showAboutDialog(context);
                  },
                ),
                SizedBox(height: 4),
                _buildSettingsItem(
                  icon: Icons.info_outline,
                  label: 'Terms & Conditions',
                  onTap: () {
                    AmplitudeService.instance.logEvent('profile_screen_tapped', eventProperties: {'item': 'terms'});
                    _showTermsAndConditions(context);
                  },
                ),
                SizedBox(height: 4),
                _buildSettingsItem(
                  icon: Icons.lock_outline,
                  label: 'Privacy Policy',
                  onTap: () {
                    AmplitudeService.instance.logEvent('profile_screen_tapped', eventProperties: {'item': 'privacy_policy'});
                    _showPrivacyPolicy(context);
                  },
                ),
                const SizedBox(height: 4),
                // Sign out
                _buildSettingsItem(
                  icon: Icons.logout,
                  label: 'Sign out',
                  onTap: () {
                    AmplitudeService.instance.logEvent('profile_screen_tapped', eventProperties: {'item': 'sign_out'});
                    _showSignOutDialog(context);
                  },
                ),
              ],
            ),
          ),
        ],
    );
  }

  Widget _buildProfilePictureSection({UserProfile? userProfile}) {
    final displayName =
        userProfile?.fullName ?? userProfile?.username ?? 'User';
    final role = userProfile?.role ?? UserRole.regular;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: const Color(0xFFF28C6A),
                backgroundImage: userProfile?.profilePictureUrl != null
                    ? NetworkImage(userProfile!.profilePictureUrl!)
                    : null,
                child: userProfile?.profilePictureUrl == null
                    ? Text(
                        _getInitials(displayName),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              if (role.isAdminOrSuperAdmin)
                Positioned(
                  bottom: 0,
                  left: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.star,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            displayName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleAndOrganizationSection(UserProfile userProfile) {
    final role = userProfile.role;
    final accentColor = _getRoleAccentColor(role);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.headerBackground,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Access',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRoleBadge(role, accentColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  role.isSuperAdmin
                      ? 'You can manage every Channel in the platform.'
                      : role.isAdmin
                      ? 'You can manage the Channels assigned to you.'
                      : 'You have standard access to follow and interact with Channels.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
          if (role.isSuperAdmin) ...[
            const SizedBox(height: 16),
            _buildSuperAdminOrganizationsCard(accentColor),
          ],
          if (role.isAdmin) ...[
            const SizedBox(height: 16),
            _buildAdminOrganizationsCard(accentColor),
          ],
        ],
      ),
    );
  }

  Widget _buildRoleBadge(UserRole role, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getRoleIcon(role), size: 18, color: accentColor),
          const SizedBox(width: 8),
          Text(
            _getRoleLabel(role),
            style: TextStyle(
              color: accentColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuperAdminOrganizationsCard(Color accentColor) {
    return _buildInfoContainer(
      backgroundColor: accentColor.withValues(alpha: 0.12),
      borderColor: accentColor.withValues(alpha: 0.35),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.workspace_premium_outlined, color: accentColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'As a super admin you have full access to manage every organization, including assigning admins, updating details, and overseeing platform activity.',
              style: TextStyle(fontSize: 14, color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminOrganizationsCard(Color accentColor) {
    if (_isLoadingManagedOrganizations && !_hasManagedOrganizationsLoaded) {
      return _buildInfoContainer(
        backgroundColor: accentColor.withValues(alpha: 0.12),
        borderColor: accentColor.withValues(alpha: 0.35),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Loading organizations you manage...',
                style: TextStyle(fontSize: 14, color: Colors.grey[800]),
              ),
            ),
          ],
        ),
      );
    }

    if (_managedOrganizationsError != null) {
      return _buildInfoContainer(
        backgroundColor: Colors.red.withValues(alpha: 0.1),
        borderColor: Colors.red.withValues(alpha: 0.3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _managedOrganizationsError!,
                style: TextStyle(fontSize: 14, color: Colors.red[800]),
              ),
            ),
          ],
        ),
      );
    }

    if (!_hasManagedOrganizationsLoaded || _managedOrganizations.isEmpty) {
      return _buildInfoContainer(
        backgroundColor: accentColor.withValues(alpha: 0.12),
        borderColor: accentColor.withValues(alpha: 0.35),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: accentColor, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You are not currently assigned to manage any organizations.',
                style: TextStyle(fontSize: 14, color: Colors.grey[800]),
              ),
            ),
          ],
        ),
      );
    }

    return _buildInfoContainer(
      backgroundColor: accentColor.withValues(alpha: 0.12),
      borderColor: accentColor.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Channels you manage (${_managedOrganizations.length})',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey[900],
            ),
          ),
          const SizedBox(height: 12),
          ..._managedOrganizations.map(
            (organization) =>
                _buildManagedOrganizationTile(organization, accentColor),
          ),
        ],
      ),
    );
  }

  Widget _buildManagedOrganizationTile(
    Organization organization,
    Color accentColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: organization.logoUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      organization.logoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(Icons.business, color: accentColor);
                      },
                    ),
                  )
                : Icon(Icons.business, color: accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  organization.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${organization.id} • ${organization.followerCount} followers',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoContainer({
    required Color backgroundColor,
    required Color borderColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }

  Color _getRoleAccentColor(UserRole role) {
    switch (role) {
      case UserRole.superadmin:
        return Colors.purple;
      case UserRole.admin:
        return Colors.blue;
      default:
        return const Color(0xFFF28C6A);
    }
  }

  String _getRoleLabel(UserRole role) {
    switch (role) {
      case UserRole.superadmin:
        return 'Super Admin';
      case UserRole.admin:
        return 'Channel Admin';
      default:
        return 'Member';
    }
  }

  IconData _getRoleIcon(UserRole role) {
    switch (role) {
      case UserRole.superadmin:
        return Icons.workspace_premium_outlined;
      case UserRole.admin:
        return Icons.manage_accounts_outlined;
      default:
        return Icons.person_outline;
    }
  }

  Widget _buildUnauthenticatedContent() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.account_circle_outlined,
            size: 80,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            'Please sign in to view your profile',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              // Navigate to login screen
              // Navigator.pushReplacementNamed(context, '/home');
              final authBloc = context.read<AuthBloc>();
              authBloc.add(LogoutEvent());
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF28C6A),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Sign In', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }


  Widget _buildSettingsItem({
    required IconData icon,
    required String label,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.headerBackground,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Color(0xFFF28C6A),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        title: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              )
            : null,
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey,
        ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'U';
    final words = name.trim().split(' ');
    if (words.length == 1) {
      return words[0][0].toUpperCase();
    }
    return (words[0][0] + words[words.length - 1][0]).toUpperCase();
  }


  Future<void> _showAboutDialog(BuildContext context) async {
    final packageInfo = await PackageInfo.fromPlatform();

    if (!mounted) return;

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('About'),
          content: Text(
            '${packageInfo.appName}\n'
            '${packageInfo.version}\n',
            // 'Build Number: ${packageInfo.buildNumber}\n'
            // 'Package Name: ${packageInfo.packageName}',
          ),
          actions: [
            // TextButton(
            //   onPressed: () => navigator.pop(),
            //   child: const Text('OK'),
            // ),
          ],
        ),
      );
    }
  }

  Future<void> _showTermsAndConditions(BuildContext context) async {
    // final Uri url = Uri.parse("https://www.magicvalleycentral.com/terms");
    //
    // if (await canLaunchUrl(url)) {
    //   await launchUrl(url, mode: LaunchMode.externalApplication);
    // } else {
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(
    //         content: Text("Could not open the terms & conditions page.")),
    //   );
    // }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const TermsAndConditionsScreen()),
    );

    // showDialog(
    //   context: context,
    //   builder: (context) => AlertDialog(
    //     title: const Text('Terms & Conditions'),
    //     content: const SingleChildScrollView(
    //       child: Text('Terms and conditions content goes here...'),
    //     ),
    //     actions: [
    //       TextButton(
    //         onPressed: () => Navigator.pop(context),
    //         child: const Text('Close'),
    //       ),
    //     ],
    //   ),
    // );
  }

  Future<void> _showPrivacyPolicy(BuildContext context) async {
    // final Uri url = Uri.parse("https://www.magicvalleycentral.com/privacy");
    //
    // if (await canLaunchUrl(url)) {
    //   await launchUrl(url, mode: LaunchMode.externalApplication);
    // } else {
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(
    //         content: Text("Could not open the terms & conditions page.")),
    //   );
    // }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PrivacyPolicyScreen()),
    );

    // showDialog(
    //   context: context,
    //   builder: (context) => AlertDialog(
    //     title: const Text('Privacy Policy'),
    //     content: const SingleChildScrollView(
    //       child: Text('Privacy policy content goes here...'),
    //     ),
    //     actions: [
    //       TextButton(
    //         onPressed: () => Navigator.pop(context),
    //         child: const Text('Close'),
    //       ),
    //     ],
    //   ),
    // );
  }


  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAccount();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    // Implement account deletion logic
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Account deletion feature coming soon...'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<AuthBloc>().add(LogoutEvent());
              Navigator.of(context).pushReplacementNamed('/welcome');
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  void _showAccountSettingsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Account settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showDeleteAccountDialog();
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(
                    Icons.delete_forever,
                    color: Colors.red,
                    size: 20,
                  ),
                  label: const Text(
                    'Delete Account',
                    style: TextStyle(color: Colors.red, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
