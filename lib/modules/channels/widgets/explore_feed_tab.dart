// lib/modules/channels/widgets/explore_feed_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/channels/explore_feed_bloc.dart';
import 'package:mvc_app/modules/channels/widgets/explore_feed_post_card.dart';
import 'package:mvc_app/services/api_repository.dart';

class ExploreFeedTab extends StatefulWidget {
  final String userId;
  final VoidCallback? onRefresh;

  const ExploreFeedTab({
    super.key,
    required this.userId,
    this.onRefresh,
  });

  @override
  State<ExploreFeedTab> createState() => _ExploreFeedTabState();
}

class _ExploreFeedTabState extends State<ExploreFeedTab> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Trigger load more when user is near the bottom
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final bloc = context.read<ExploreFeedBloc>();
      final state = bloc.state;

      if (state is ExploreFeedLoaded && !state.isLoadingMore && state.hasMorePosts) {
        bloc.add(LoadMoreExploreFeed(userId: widget.userId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ExploreFeedBloc, ExploreFeedState>(
      builder: (context, state) {
        if (state is ExploreFeedInitial) {
          // Trigger initial load
          context.read<ExploreFeedBloc>().add(
            LoadExploreFeed(userId: widget.userId),
          );
          return const Center(child: CircularProgressIndicator());
        }

        if (state is ExploreFeedLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is ExploreFeedError) {
          return _buildErrorView(state.message);
        }

        if (state is ExploreFeedLoaded) {
          return _buildFeedList(state);
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildFeedList(ExploreFeedLoaded state) {
    if (state.posts.isEmpty) {
      return _buildEmptyView();
    }

    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        String currentUserId = '';
        UserRole currentUserRole = UserRole.regular;
        List<String> currentUserManagedOrganizations = [];
        if (authState is AuthAuthenticatedState) {
          currentUserId = authState.userId;
          currentUserRole =
              authState.userProfile?.role ?? UserRole.regular;
          currentUserManagedOrganizations =
              authState.managedOrganizations.map((org) => org.id).toList();
        }

        return RefreshIndicator(
          onRefresh: () async {
            context.read<ExploreFeedBloc>().add(
              RefreshExploreFeed(userId: widget.userId),
            );
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            itemCount: state.posts.length + (state.isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == state.posts.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final feedItem = state.posts[index];
              return ExploreFeedPostCard(
                feedItem: feedItem,
                onFollowChanged: widget.onRefresh,
                currentUserId: currentUserId,
                currentUserRole: currentUserRole,
                currentUserManagedOrganizations:
                    currentUserManagedOrganizations,
                reactions:
                    state.messageReactions[feedItem.post.id] ?? const [],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyView() {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<ExploreFeedBloc>().add(
          RefreshExploreFeed(userId: widget.userId),
        );
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(
            Icons.explore_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'No posts yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Discover new channels and their posts here. Follow channels to see their content first!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              onPressed: () {
                context.read<ExploreFeedBloc>().add(
                  RefreshExploreFeed(userId: widget.userId),
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildErrorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                context.read<ExploreFeedBloc>().add(
                  LoadExploreFeed(userId: widget.userId),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
