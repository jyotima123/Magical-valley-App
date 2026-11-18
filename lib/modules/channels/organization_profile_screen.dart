// lib/modules/organization/organization_profile_screen.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/main_scaffold.dart';
import 'package:mvc_app/modules/admin/organizations_management_screen.dart';
import 'package:mvc_app/modules/chat/chat_service.dart';
import 'package:mvc_app/modules/chat/models/organization_event.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';
import 'package:mvc_app/modules/chat/organizations_bloc.dart';
import 'package:mvc_app/modules/channels/organization_followers_screen.dart';
import 'package:mvc_app/modules/chat/widgets/image_carousel_screen.dart';
import 'package:mvc_app/modules/market/widgets/hero_carousel.dart';
import 'package:mvc_app/modules/market/widgets/pressable_scale.dart';
import 'package:mvc_app/modules/market/widgets/staggered_entrance.dart';
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

class _OrganizationProfileScreenState extends State<OrganizationProfileScreen>
    with TickerProviderStateMixin {
  final ApiService _apiService = SupabaseApiService.instance;
  UserRole? _userRole;
  List<Organization> _managedOrganizations = [];
  bool _isUnfollowing = false;
  bool _isLoading = true;
  Organization? _currentOrganization;
  String? _error;

  /// Plays once, when the profile first arrives: the header, gallery and info
  /// cards rise into place one after another, the way the Market home does.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// The photo on stage in the gallery, so a tap opens that one full screen.
  int _photoIndex = 0;

  /// How far the action card rides up over the bottom of the header. The
  /// header's bottom padding leaves room for it, so the chips stay clear.
  static const double _actionCardOverlap = 22;

  @override
  void initState() {
    super.initState();
    _fetchOrganizationAndUserData();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _fetchOrganizationAndUserData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await Future.wait([
        _fetchOrganizationDetails(),
        _fetchUserRoleAndManagedOrganizations(),
      ]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load organization details: $e';
        _isLoading = false;
      });
    }
  }

  /// Loads this channel fresh from the network, so the profile always shows
  /// the latest bio, links, photos and addresses. Also used to refresh in place
  /// (pull to refresh, or after an admin saves an edit) without a spinner.
  Future<void> _fetchOrganizationDetails() async {
    final organizationsBloc = OrganizationsBloc();
    try {
      final result = organizationsBloc.stream
          .firstWhere(
            (state) =>
                state is OrganizationsLoaded || state is OrganizationsError,
          )
          .timeout(const Duration(seconds: 30));
      organizationsBloc.add(
        LoadOrganizationsByCategory(
          categoryId: null,
          categoryName: '',
          forceRefresh: true,
        ),
      );
      final state = await result;
      if (!mounted) return;

      if (state is OrganizationsLoaded) {
        Organization? organization;
        for (final org in state.organizations) {
          if (org.id == widget.organizationId) organization = org;
        }
        setState(() {
          _currentOrganization = organization ?? _currentOrganization;
          if (organization == null && _currentOrganization == null) {
            _error = 'Organization not found';
          }
          _isLoading = false;
        });
        if (_currentOrganization != null && _entrance.isDismissed) {
          _entrance.forward();
        }
      } else if (state is OrganizationsError) {
        setState(() {
          // Keep showing what we have if this was only a refresh.
          if (_currentOrganization == null) _error = state.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_currentOrganization == null) {
          _error = 'Failed to load organization: $e';
        }
        _isLoading = false;
      });
    } finally {
      organizationsBloc.close();
    }
  }

  Future<void> _fetchUserRoleAndManagedOrganizations() async {
    final currentUser = await _apiService.getCurrentUser();
    if (currentUser == null) return;

    final userRoleResult = await _apiService.getUserRole(
      currentUser.userId ?? "",
    );
    if (!mounted) return;
    if (userRoleResult.isSuccess) {
      setState(() {
        _userRole = userRoleResult.data;
      });

      if (!_userRole!.isSuperAdmin) {
        final managedOrgsResult = await _apiService.getUserAdminOrganizations(
          currentUser.userId ?? "",
        );
        if (managedOrgsResult.isSuccess && mounted) {
          setState(() {
            _managedOrganizations = managedOrgsResult.data ?? [];
          });
        }
      }
    }
  }

  /// A super admin, or an admin of this very channel: they see the follower
  /// count and get the Edit profile button.
  bool get _canManage => _canSeeFollowerCount;

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

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_isLoading) {
      body = const _ProfileSkeleton();
    } else if (_error != null) {
      body = SafeArea(child: _buildErrorView());
    } else if (_currentOrganization == null) {
      body = const Center(child: Text('Organization not found'));
    } else {
      body = _buildContent();
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White status bar icons over the colourful header.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _ProfilePalette.background,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: KeyedSubtree(
            key: ValueKey(
              _isLoading ? 'loading' : (_error != null ? 'error' : 'ready'),
            ),
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Stack(
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text('Failed to load organization', style: AppTheme.chatTitle),
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
          ),
        ),
      ],
    );
  }

  String _followerText(int count) {
    return (count == 1) ? "follower" : "followers";
  }

  Widget _buildContent() {
    final org = _currentOrganization!;
    var section = 0;
    Widget enter(Widget child) => StaggeredEntrance(
          animation: _entrance,
          index: section++,
          child: child,
        );

    final photoCount = org.photos.length;

    return RefreshIndicator(
      onRefresh: _fetchOrganizationDetails,
      color: AppTheme.accentPrimary,
      edgeOffset: MediaQuery.of(context).padding.top,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // Header and action card share one sliver: a viewport paints earlier
          // slivers over later ones, so in separate slivers the header would
          // cover the top of the buttons. Here the card, laid out after the
          // header, paints on top of it.
          SliverToBoxAdapter(
            child: Column(
              children: [
                enter(_buildHeader(org)),
                // Tucks just the card's top edge under the header's curve.
                Transform.translate(
                  offset: const Offset(0, -_actionCardOverlap),
                  child: enter(_buildActionsCard()),
                ),
              ],
            ),
          ),
          if (_canManage && _missingProfileParts(org).isNotEmpty)
            SliverToBoxAdapter(child: enter(_buildCompleteProfileCard(org))),
          if (photoCount > 0) ...[
            SliverToBoxAdapter(
              child: enter(
                _SectionTitle(
                  title: 'Gallery',
                  trailing: '$photoCount photo${photoCount == 1 ? '' : 's'}',
                ),
              ),
            ),
            SliverToBoxAdapter(child: enter(_buildGallery(org))),
          ],
          if (org.bio != null && org.bio!.trim().isNotEmpty) ...[
            SliverToBoxAdapter(
              child: enter(const _SectionTitle(title: 'About')),
            ),
            SliverToBoxAdapter(child: enter(_buildAboutCard(org))),
          ],
          if (_hasContactInfo) ...[
            SliverToBoxAdapter(
              child: enter(const _SectionTitle(title: 'Find us')),
            ),
            SliverToBoxAdapter(child: enter(_buildLinkTiles(org))),
          ],
          if (org.isFollowing)
            SliverToBoxAdapter(child: enter(_buildUnfollow())),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 32 + MediaQuery.of(context).padding.bottom,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader(Organization org) {
    final topInset = MediaQuery.of(context).padding.top;
    String? city;
    for (final address in org.addresses) {
      if (address.city != null && address.city!.isNotEmpty) {
        city = address.city;
        break;
      }
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: Stack(
        children: [
          const Positioned.fill(child: _AnimatedGradientBackdrop()),
          Padding(
            padding: EdgeInsets.fromLTRB(12, topInset + 6, 12, 50),
            child: Column(
              children: [
                Row(
                  children: [
                    _CircleGlassButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    if (_canManage) _EditProfileButton(onTap: _openEditProfile),
                  ],
                ),
                const SizedBox(height: 4),
                _PopIn(child: _buildOrganizationLogo(size: 104)),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    org.name.isNotEmpty ? org.name : 'No Name',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 25,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: Colors.white,
                      shadows: [
                        Shadow(color: Color(0x33000000), blurRadius: 12),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (org.isFollowing)
                      const _HeaderChip(
                        icon: Icons.check_circle_rounded,
                        label: 'Following',
                      ),
                    if (_canSeeFollowerCount)
                      _HeaderChip(
                        icon: Icons.people_alt_rounded,
                        label:
                            '${_formatFollowerCount(org.followerCount)} ${_followerText(org.followerCount)}',
                        onTap: _openFollowersScreen,
                      ),
                    if (city != null)
                      _HeaderChip(icon: Icons.place_rounded, label: city),
                    if (org.photos.isNotEmpty)
                      _HeaderChip(
                        icon: Icons.photo_library_rounded,
                        label: '${org.photos.length}',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrganizationLogo({double size = 104}) {
    final org = _currentOrganization!;
    final hasLogo = org.logoUrl != null && org.logoUrl!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipOval(
        child: hasLogo
            ? Image.network(
                org.logoUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : _buildDefaultLogo(size: size),
                errorBuilder: (_, __, ___) => _buildDefaultLogo(size: size),
              )
            : _buildDefaultLogo(size: size),
      ),
    );
  }

  Widget _buildDefaultLogo({double size = 104}) {
    final name = _currentOrganization?.name ?? '';
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: _ProfilePalette.brand),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Widget _buildActionsCard() {
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.chat_bubble_rounded,
            label: 'View',
            gradient: _ProfilePalette.green,
            onTap: _openChannel,
          ),
          _ActionButton(
            icon: Icons.forum_rounded,
            label: 'Message',
            gradient: _ProfilePalette.brand,
            onTap: _startDirectMessage,
          ),
          if (_canSeeFollowerCount)
            _ActionButton(
              icon: Icons.people_alt_rounded,
              label: 'Followers',
              gradient: _ProfilePalette.blue,
              onTap: _openFollowersScreen,
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Gallery
  // ---------------------------------------------------------------------------

  Widget _buildGallery(Organization org) {
    final photos = org.photos;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: PressableScale(
        pressedScale: 0.98,
        semanticLabel: 'Open photo gallery',
        onTap: () => _openPhoto(_photoIndex.clamp(0, photos.length - 1)),
        child: Container(
          height: 260,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 20,
                spreadRadius: -4,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: HeroCarousel(
              // A different photo set (after an edit) starts a fresh rotation.
              key: ValueKey(photos.map((p) => p.id).join(',')),
              itemCount: photos.length,
              onIndexChanged: (i) => _photoIndex = i,
              topBar: Row(
                children: [
                  const GlassPill(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.photo_camera_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                        SizedBox(width: 6),
                        Text('Photos', style: _ProfileText.pill),
                      ],
                    ),
                  ),
                  const Spacer(),
                  GlassPill(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          photos.length > 1 ? 'View all' : 'View',
                          style: _ProfileText.pill,
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.open_in_full_rounded,
                          color: Colors.white,
                          size: 13,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              photoBuilder: (_, i) => Image.network(
                photos[i].photoUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                // Full card width on a large phone, no more.
                cacheWidth: 1080,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white38,
                    size: 40,
                  ),
                ),
              ),
              captionBuilder: (_, i) {
                final caption = photos[i].caption;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'PHOTO ${i + 1} OF ${photos.length}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      caption != null && caption.isNotEmpty
                          ? caption
                          : org.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _openPhoto(int index) {
    final urls = _currentOrganization!.photos.map((p) => p.photoUrl).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageCarouselScreen(
          imageUrls: urls,
          initialIndex: index,
          theme: AppThemeMode.light,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // About & links
  // ---------------------------------------------------------------------------

  Widget _buildAboutCard(Organization org) {
    return _Card(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: const BoxDecoration(
                gradient: _ProfilePalette.brandVertical,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShaderMask(
                      shaderCallback: (r) =>
                          _ProfilePalette.brand.createShader(r),
                      child: const Icon(
                        Icons.format_quote_rounded,
                        size: 30,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      org.bio!.replaceAll('\\n', '\n'),
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14.5,
                        height: 1.6,
                        color: Color(0xFF4A4642),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasContactInfo {
    final org = _currentOrganization;
    if (org == null) return false;
    return (org.websiteUrl != null && org.websiteUrl!.isNotEmpty) ||
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

  Widget _buildLinkTiles(Organization org) {
    final tiles = <_LinkTile>[
      if (org.websiteUrl != null && org.websiteUrl!.isNotEmpty)
        _LinkTile(
          icon: Icons.language_rounded,
          title: 'Website',
          subtitle: org.websiteUrl!
              .replaceFirst(RegExp(r'^https?://'), '')
              .replaceFirst(RegExp(r'/$'), ''),
          gradient: _ProfilePalette.blue,
          onTap: () => _launchUrl(
            org.websiteUrl!.startsWith('http')
                ? org.websiteUrl!
                : 'https://${org.websiteUrl!}',
          ),
        ),
      if (org.mapsUrl != null && org.mapsUrl!.isNotEmpty)
        _LinkTile(
          icon: Icons.map_rounded,
          title: 'Directions',
          subtitle: 'Open in Google Maps',
          gradient: _ProfilePalette.green,
          onTap: () => _launchUrl(org.mapsUrl!),
        ),
      for (final phone in org.phoneNumbers)
        _LinkTile(
          icon: Icons.phone_rounded,
          title: phone.label ?? 'Call',
          subtitle: phone.phoneNumber,
          gradient: _ProfilePalette.amber,
          onTap: () => _launchUrl('tel:${phone.phoneNumber}'),
        ),
      for (final address in org.addresses)
        _LinkTile(
          icon: Icons.place_rounded,
          title: address.label ?? 'Address',
          subtitle: address.formattedAddress.isNotEmpty
              ? address.formattedAddress
              : 'No address details',
          gradient: _ProfilePalette.brand,
          wide: true,
          onTap: () => _launchUrl(address.mapsLaunchUrl),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          final full = constraints.maxWidth;
          final half = (full - gap) / 2;

          // Short tiles sit two to a row; addresses, and a short tile left
          // alone at the end of the short ones, take the whole row.
          final narrowCount = tiles.where((t) => !t.wide).length;
          var narrowSeen = 0;
          final widths = <double>[];
          for (final tile in tiles) {
            if (tile.wide) {
              widths.add(full);
            } else {
              narrowSeen++;
              final lastAndAlone = narrowCount.isOdd && narrowSeen == narrowCount;
              widths.add(lastAndAlone ? full : half);
            }
          }

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < tiles.length; i++)
                SizedBox(width: widths[i], child: tiles[i]),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Admin: complete your profile
  // ---------------------------------------------------------------------------

  List<String> _missingProfileParts(Organization org) => [
        if (org.logoUrl == null || org.logoUrl!.isEmpty) 'Logo',
        if (org.photos.isEmpty) 'Photos',
        if (org.bio == null || org.bio!.trim().isEmpty) 'Bio',
        if (org.websiteUrl == null || org.websiteUrl!.isEmpty) 'Website',
        if (org.mapsUrl == null || org.mapsUrl!.isEmpty) 'Maps link',
      ];

  Widget _buildCompleteProfileCard(Organization org) {
    final missing = _missingProfileParts(org);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: PressableScale(
        pressedScale: 0.98,
        semanticLabel: 'Complete your profile',
        onTap: _openEditProfile,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: const Color(0xFFFFF1EB),
            border: Border.all(
              color: AppTheme.accentPrimary.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _ProfilePalette.brand,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Make your profile shine',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Add: ${missing.join(' · ')}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.accentPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Unfollow
  // ---------------------------------------------------------------------------

  Widget _buildUnfollow() {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Center(
        child: TextButton.icon(
          onPressed: _isUnfollowing ? null : _handleUnfollow,
          style: TextButton.styleFrom(
            foregroundColor: Colors.red.shade400,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          icon: _isUnfollowing
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.red.shade400),
                  ),
                )
              : const Icon(Icons.person_remove_outlined, size: 17),
          label: Text(
            _isUnfollowing ? 'Unfollowing...' : 'Unfollow channel',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  /// The same edit sheet admins get from Manage → Channels; it saves, closes
  /// itself and tells us, and the profile refreshes in place.
  void _openEditProfile() {
    final org = _currentOrganization;
    if (org == null || !_canManage) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditOrganizationSheet(
        organization: org,
        onOrganizationUpdated: _fetchOrganizationDetails,
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

// =============================================================================
// Building blocks
// =============================================================================

/// The profile's colours: the app's coral, warmed into pink and amber for the
/// header, plus one gradient per kind of link so each reads at a glance.
abstract final class _ProfilePalette {
  /// The Market home's warm off-white, so the two screens feel like one app.
  static const Color background = Color(0xFFF7F5F3);

  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF9A62), AppTheme.accentPrimary, Color(0xFFF0627E)],
  );

  static const LinearGradient brandVertical = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFF9A62), AppTheme.accentPrimary, Color(0xFFF0627E)],
  );

  static const LinearGradient blue = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5AB2FF), Color(0xFF3D6DF2)],
  );

  static const LinearGradient green = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4ADE9B), Color(0xFF16A37A)],
  );

  static const LinearGradient amber = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFC857), Color(0xFFF59331)],
  );

  /// The header's colours, which [_AnimatedGradientBackdrop] slowly turns.
  static const List<Color> header = [
    Color(0xFFFF9A62),
    AppTheme.accentPrimary,
    Color(0xFFF0627E),
    Color(0xFFB66CF0),
  ];
}

abstract final class _ProfileText {
  static const TextStyle pill = TextStyle(
    fontFamily: 'Poppins',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );
}

/// The header's backdrop: a warm gradient whose direction slowly turns, with
/// soft light blobs drifting across it, so the top of the profile breathes
/// instead of sitting still.
class _AnimatedGradientBackdrop extends StatefulWidget {
  const _AnimatedGradientBackdrop();

  @override
  State<_AnimatedGradientBackdrop> createState() =>
      _AnimatedGradientBackdropState();
}

class _AnimatedGradientBackdropState extends State<_AnimatedGradientBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          final t = _clock.value * 2 * math.pi;
          return CustomPaint(painter: _BackdropPainter(t));
        },
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.t);

  /// Phase in radians, one full turn per loop.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final begin = Alignment(math.cos(t) * 0.9, -1 + math.sin(t) * 0.3);
    final end = Alignment(-math.cos(t) * 0.9, 1 - math.sin(t) * 0.3);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: begin,
          end: end,
          colors: _ProfilePalette.header,
        ).createShader(rect),
    );

    // Soft light blobs, each on its own slow orbit.
    void blob(double cx, double cy, double r, double phase, double alpha) {
      final center = Offset(
        size.width * (cx + 0.08 * math.cos(t + phase)),
        size.height * (cy + 0.10 * math.sin(t * 1.0 + phase)),
      );
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: alpha),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }

    blob(0.12, 0.25, size.width * 0.45, 0, 0.30);
    blob(0.88, 0.70, size.width * 0.50, 2.1, 0.22);
    blob(0.55, 0.05, size.width * 0.30, 4.2, 0.18);
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.t != t;
}

/// Grows the child in with a little overshoot the first time it is built.
class _PopIn extends StatelessWidget {
  const _PopIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 750),
      curve: Curves.elasticOut,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}

class _CircleGlassButton extends StatelessWidget {
  const _CircleGlassButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.9,
        semanticLabel: tooltip,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

/// The admin's way into the edit sheet: a small white pill in the header that
/// stands out against the colour without shouting.
class _EditProfileButton extends StatelessWidget {
  const _EditProfileButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.92,
      semanticLabel: 'Edit profile',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_rounded, size: 16, color: AppTheme.accentPrimary),
            SizedBox(width: 6),
            Text(
              'Edit profile',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.accentPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A frosted fact under the channel name.
class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(label, style: _ProfileText.pill),
        ],
      ),
    );
    if (onTap == null) return chip;
    return PressableScale(onTap: onTap!, semanticLabel: label, child: chip);
  }
}

/// A white rounded card with the soft shadow the Market uses.
class _Card extends StatelessWidget {
  const _Card({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final LinearGradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.9,
      semanticLabel: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradient,
              boxShadow: [
                BoxShadow(
                  color: gradient.colors.last.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 19,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: AppTheme.black,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
        ],
      ),
    );
  }
}

/// One way to reach the channel — website, directions, a phone, an address —
/// as a tinted tile with a gradient badge in that link's colour.
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
    this.wide = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final LinearGradient gradient;
  final VoidCallback onTap;

  /// Takes a whole row: addresses are too long to share one.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final tint = gradient.colors.last;
    return PressableScale(
      onTap: onTap,
      semanticLabel: '$title, $subtitle',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: tint.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: tint.withValues(alpha: 0.12),
              blurRadius: 16,
              spreadRadius: -4,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: gradient,
              ),
              child: Icon(icon, color: Colors.white, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.black,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: wide ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      height: 1.35,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.north_east_rounded, size: 16, color: tint),
          ],
        ),
      ),
    );
  }
}

/// The profile's shape in shimmering placeholders while it loads.
class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          ShimmerBox(height: 300 + top, borderRadius: 32),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 120, height: 20, borderRadius: 6),
                SizedBox(height: 14),
                ShimmerBox(height: 260, borderRadius: 22),
                SizedBox(height: 24),
                ShimmerBox(width: 90, height: 20, borderRadius: 6),
                SizedBox(height: 14),
                ShimmerBox(height: 110, borderRadius: 22),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
