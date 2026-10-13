// lib/modules/profile/qa_post_views_debug_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/chat/chat_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QAPostViewsDebugScreen extends StatefulWidget {
  const QAPostViewsDebugScreen({super.key});

  @override
  State<QAPostViewsDebugScreen> createState() => _QAPostViewsDebugScreenState();
}

class _QAPostViewsDebugScreenState extends State<QAPostViewsDebugScreen> {
  List<OrganizationBasicInfo> _organizations = [];
  Map<String, OrganizationPostViewsData> _loadedOrganizationData = {};
  Set<String> _loadingOrganizations = {};
  Set<String> _expandedOrganizations = {};
  bool _isLoadingOrganizations = true;
  bool _showOnlyActivePosts = false; // Toggle to show only active posts
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadOrganizations();
    // Load channels if not already loaded
    context.read<ChatBloc>().add(LoadChannelsEvent());
  }

  Future<void> _loadOrganizations() async {
    setState(() {
      _isLoadingOrganizations = true;
      _errorMessage = null;
    });

    try {
      final client = Supabase.instance.client;
      final orgsResponse = await client
          .from('organizations')
          .select('id, name, logo_url, follower_count')
          .order('name');
      final organizations = orgsResponse as List<dynamic>;

      setState(() {
        _organizations = organizations.map((org) {
          return OrganizationBasicInfo(
            id: org['id'] as String,
            name: org['name'] as String,
            logoUrl: org['logo_url'] as String?,
            followerCount: (org['follower_count'] as int?) ?? 0,
          );
        }).toList();
        _isLoadingOrganizations = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading organizations: $e';
        _isLoadingOrganizations = false;
      });
    }
  }

  Future<void> _loadOrganizationData(String organizationId) async {
    // If already loaded, don't reload
    if (_loadedOrganizationData.containsKey(organizationId)) {
      return;
    }

    setState(() {
      _loadingOrganizations.add(organizationId);
    });

    try {
      final client = Supabase.instance.client;

      // Get organization name
      final orgResponse = await client
          .from('organizations')
          .select('name')
          .eq('id', organizationId)
          .single();
      final orgName = orgResponse['name'] as String;

      // Fetch all posts for this organization (debug: try without status filter first)
      // First, let's check all posts regardless of status
      final allPostsResponse = await client
          .from('posts')
          .select('*')
          .eq('organization_id', organizationId)
          .order('created_at', ascending: false);

      final allPosts = allPostsResponse as List<dynamic>;

      // Debug: Log post counts and statuses
      print('📊 Organization: $orgName (ID: $organizationId)');
      print('   Total posts (all statuses): ${allPosts.length}');
      if (allPosts.isNotEmpty) {
        final statusCounts = <String, int>{};
        for (final post in allPosts) {
          final status = post['status'] as String? ?? 'null';
          statusCounts[status] = (statusCounts[status] ?? 0) + 1;
        }
        print('   Post statuses: $statusCounts');
      }

      // Apply status filter if toggle is enabled
      final posts = _showOnlyActivePosts
          ? allPosts
                .where((p) => (p['status'] as String? ?? '') == 'active')
                .toList()
          : allPosts;

      print(
        '   Posts to display: ${posts.length} (filter active: $_showOnlyActivePosts)',
      );

      // Fetch followers count for this organization
      final followersResponse = await client
          .from('user_follows')
          .select('user_id')
          .eq('organization_id', organizationId);
      final followers = followersResponse as List<dynamic>;
      final followerCount = followers.length;

      // Get all follower IDs
      final followerIds = followers
          .map<String>((f) => f['user_id'] as String)
          .toSet();

      final postViews = <PostViewData>[];

      for (final post in posts) {
        final postId = post['id'] as String;
        final postTitle = post['title'] as String? ?? '';
        final postContent = post['content'] as String? ?? '';
        final postCreatedAt = DateTime.parse(post['created_at'] as String);

        // Fetch views via SECURITY DEFINER RPC (post_views has no SELECT RLS policy)
        final viewsResponse = await client.rpc(
          'get_post_views',
          params: {'p_post_id': postId},
        );

        final views = viewsResponse as List<dynamic>;
        final viewerIds = views
            .map<String>((v) => v['user_id'] as String)
            .toSet();

        // Get user profiles for viewers separately
        final viewers = <PostViewer>[];
        if (viewerIds.isNotEmpty) {
          final viewerProfilesResponse = await client
              .from('user_profiles')
              .select('id, username, full_name, email')
              .inFilter('id', viewerIds.toList());

          final viewerProfiles = {
            for (final p in viewerProfilesResponse as List<dynamic>)
              p['id'] as String: p,
          };

          for (final view in views) {
            final userId = view['user_id'] as String;
            final userProfile = viewerProfiles[userId];
            viewers.add(
              PostViewer(
                userId: userId,
                username: userProfile?['username'] as String? ?? '',
                fullName: userProfile?['full_name'] as String? ?? '',
                email: userProfile?['email'] as String? ?? '',
                viewedAt: DateTime.parse(view['viewed_at'] as String),
              ),
            );
          }
        }

        // Calculate who hasn't viewed yet
        final nonViewerIds = followerIds.difference(viewerIds);
        final nonViewers = <String>[];
        if (nonViewerIds.isNotEmpty) {
          // Fetch user profiles for non-viewers
          final nonViewerProfilesResponse = await client
              .from('user_profiles')
              .select('id, username, full_name, email')
              .inFilter('id', nonViewerIds.toList());

          final nonViewerProfiles = nonViewerProfilesResponse as List<dynamic>;
          nonViewers.addAll(
            nonViewerProfiles.map<String>((p) {
              final username = p['username'] as String? ?? '';
              final fullName = p['full_name'] as String? ?? '';
              final email = p['email'] as String? ?? '';
              return fullName.isNotEmpty
                  ? fullName
                  : (username.isNotEmpty ? username : email);
            }),
          );
        }

        postViews.add(
          PostViewData(
            postId: postId,
            title: postTitle,
            content: postContent,
            createdAt: postCreatedAt,
            viewCount: views.length,
            viewerCount: viewerIds.length,
            followerCount: followerCount,
            viewers: viewers,
            nonViewers: nonViewers,
          ),
        );
      }

      // Calculate organization statistics
      final totalPosts = posts.length;
      final totalViews = postViews.fold<int>(
        0,
        (sum, pv) => sum + pv.viewCount,
      );
      final avgViews = totalPosts > 0 ? totalViews / totalPosts : 0.0;
      final postsWithViews = postViews.where((pv) => pv.viewCount > 0).length;
      final postsWithoutViews = postViews
          .where((pv) => pv.viewCount == 0)
          .length;

      print('   Final stats - Posts: $totalPosts, Views: $totalViews');

      final stats = OrganizationStats(
        organizationId: organizationId,
        organizationName: orgName,
        totalPosts: totalPosts,
        totalViews: totalViews,
        averageViews: avgViews,
        postsWithViews: postsWithViews,
        postsWithoutViews: postsWithoutViews,
        followerCount: followerCount,
      );

      setState(() {
        _loadedOrganizationData[organizationId] = OrganizationPostViewsData(
          stats: stats,
          postViews: postViews,
        );
        _loadingOrganizations.remove(organizationId);
      });
    } catch (e) {
      setState(() {
        _loadingOrganizations.remove(organizationId);
        _errorMessage = 'Error loading organization data: $e';
      });
    }
  }

  void _onOrganizationExpansionChanged(String organizationId, bool isExpanded) {
    setState(() {
      if (isExpanded) {
        _expandedOrganizations.add(organizationId);
        // Load data when expanded
        _loadOrganizationData(organizationId);
      } else {
        _expandedOrganizations.remove(organizationId);
      }
    });
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final month = months[dateTime.month - 1];
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$month ${dateTime.day}, ${dateTime.year} $hour:$minute';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
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
        title: const Text('Post Views'),
        actions: [
          IconButton(
            icon: Icon(
              _showOnlyActivePosts
                  ? Icons.filter_alt
                  : Icons.filter_alt_outlined,
            ),
            onPressed: () {
              setState(() {
                _showOnlyActivePosts = !_showOnlyActivePosts;
                _loadedOrganizationData.clear();
                _expandedOrganizations.clear();
              });
            },
            tooltip: _showOnlyActivePosts
                ? 'Show all posts'
                : 'Show only active posts',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<ChatBloc>().add(LoadChannelsEvent());
              _loadedOrganizationData.clear();
              _expandedOrganizations.clear();
              _loadOrganizations();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoadingOrganizations
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && _organizations.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Error: $_errorMessage',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadOrganizations,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                context.read<ChatBloc>().add(LoadChannelsEvent());
                _loadedOrganizationData.clear();
                _expandedOrganizations.clear();
                await _loadOrganizations();
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(
                  16,
                ), // Padding around the whole list of organizations
                itemCount: _organizations.length,
                itemBuilder: (context, index) {
                  final org = _organizations[index];
                  return _buildOrganizationCard(org);
                },
              ),
            ),
    );
  }

  Widget _buildOrganizationCard(OrganizationBasicInfo org) {
    final isExpanded = _expandedOrganizations.contains(org.id);
    final isLoading = _loadingOrganizations.contains(org.id);
    final loadedData = _loadedOrganizationData[org.id];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              side: BorderSide.none,
            ),
            collapsedShape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              side: BorderSide.none,
            ),
            initiallyExpanded: isExpanded,
            onExpansionChanged: (expanded) {
              _onOrganizationExpansionChanged(org.id, expanded);
            },
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: org.logoUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        org.logoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.business, color: Colors.blue);
                        },
                      ),
                    )
                  : const Icon(Icons.business, color: Colors.blue),
            ),
            title: Text(
              org.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(

              org.followerCount > 1 ? '${org.followerCount} followers': '${org.followerCount} follower',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            children: [
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (loadedData != null)
                _buildOrganizationContent(loadedData)
              else
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Failed to load data')),
                ),
            ],
            childrenPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }

  Widget _buildOrganizationContent(OrganizationPostViewsData data) {
    final stats = data.stats;
    final postViews = data.postViews;
    final avgUniqueViewers = postViews.isNotEmpty
        ? postViews.fold<int>(0, (sum, pv) => sum + pv.viewerCount) /
              postViews.length
        : 0.0;
    final viewPercentage = stats.followerCount > 0
        ? (avgUniqueViewers / stats.followerCount * 100)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Organization Stats
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Statistics',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildStatRow('Total Posts', stats.totalPosts.toString()),
              const SizedBox(height: 8),
              _buildStatRow('Total Views', stats.totalViews.toString()),
              const SizedBox(height: 8),
              _buildStatRow(
                'Average Views',
                stats.averageViews.toStringAsFixed(1),
              ),
              const SizedBox(height: 8),
              _buildStatRow('Followers', stats.followerCount.toString()),
              const SizedBox(height: 8),
              _buildStatRow(
                'View Rate',
                '${viewPercentage.toStringAsFixed(1)}%',
              ),
              const SizedBox(height: 8),
              _buildStatRow(
                'Posts with Views',
                '${stats.postsWithViews} / ${stats.totalPosts}',
              ),
              const SizedBox(height: 8),
              _buildStatRow(
                'Posts without Views',
                stats.postsWithoutViews.toString(),
              ),
            ],
          ),
        ),

        // Posts List
        if (postViews.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Posts',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...postViews.map((pv) => _buildPostCard(pv)),
              ],
            ),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: Text(
                'No posts found',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildPostCard(PostViewData postView) {
    final viewPercentage = postView.followerCount > 0
        ? (postView.viewerCount / postView.followerCount * 100)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: postView.viewCount > 0
              ? Colors.green.withOpacity(0.3)
              : Colors.grey.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    postView.title.isNotEmpty
                        ? postView.title
                        : (postView.content.isNotEmpty
                              ? postView.content
                              : 'Untitled Post'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (postView.viewCount > 0 ? Colors.green : Colors.orange)
                            .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${postView.viewerCount}/${postView.followerCount}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: postView.viewCount > 0
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatDateTime(postView.createdAt)} • ${viewPercentage.toStringAsFixed(1)}% viewed • ${postView.viewCount} views',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        children: [
          if (postView.viewers.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Viewed by (${postView.viewerCount}):',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...postView.viewers.map(
                    (viewer) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            size: 16,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              viewer.fullName.isNotEmpty
                                  ? viewer.fullName
                                  : (viewer.username.isNotEmpty
                                        ? viewer.username
                                        : viewer.email),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(
                            _formatDateTime(viewer.viewedAt),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (postView.nonViewers.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Not viewed by (${postView.nonViewers.length}):',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...postView.nonViewers.map(
                    (nonViewer) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.radio_button_unchecked,
                            size: 16,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              nonViewer,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
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
}

class OrganizationBasicInfo {
  final String id;
  final String name;
  final String? logoUrl;
  final int followerCount;

  OrganizationBasicInfo({
    required this.id,
    required this.name,
    this.logoUrl,
    required this.followerCount,
  });
}

class OrganizationPostViewsData {
  final OrganizationStats stats;
  final List<PostViewData> postViews;

  OrganizationPostViewsData({required this.stats, required this.postViews});
}

class PostViewData {
  final String postId;
  final String title;
  final String content;
  final DateTime createdAt;
  final int viewCount;
  final int viewerCount;
  final int followerCount;
  final List<PostViewer> viewers;
  final List<String> nonViewers;

  PostViewData({
    required this.postId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.viewCount,
    required this.viewerCount,
    required this.followerCount,
    required this.viewers,
    required this.nonViewers,
  });
}

class PostViewer {
  final String userId;
  final String username;
  final String fullName;
  final String email;
  final DateTime viewedAt;

  PostViewer({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.email,
    required this.viewedAt,
  });
}

class OrganizationStats {
  final String organizationId;
  final String organizationName;
  final int totalPosts;
  final int totalViews;
  final double averageViews;
  final int postsWithViews;
  final int postsWithoutViews;
  final int followerCount;

  OrganizationStats({
    required this.organizationId,
    required this.organizationName,
    required this.totalPosts,
    required this.totalViews,
    required this.averageViews,
    required this.postsWithViews,
    required this.postsWithoutViews,
    required this.followerCount,
  });
}
