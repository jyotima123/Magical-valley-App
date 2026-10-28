import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/services/api_repository.dart';

class OrganizationFollowersScreen extends StatefulWidget {
  final String organizationId;
  final String organizationName;

  const OrganizationFollowersScreen({
    super.key,
    required this.organizationId,
    required this.organizationName,
  });

  @override
  State<OrganizationFollowersScreen> createState() =>
      _OrganizationFollowersScreenState();
}

class _OrganizationFollowersScreenState
    extends State<OrganizationFollowersScreen> {
  List<UserProfile>? _followers;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFollowers();
  }

  Future<void> _loadFollowers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiRepository = context.read<ApiRepository>();
      final result =
          await apiRepository.getOrganizationFollowers(widget.organizationId);

      if (!mounted) return;

      if (result.isSuccess) {
        setState(() {
          _followers = result.data ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage =
              result.error ?? 'Failed to load organization followers';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'An error occurred while loading followers: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final followerCount = _followers?.length ?? 0;
    final titleText = _isLoading
        ? '${widget.organizationName} Followers'
        : '${widget.organizationName}\n($followerCount followers)';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          titleText,
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.clip,
          softWrap: true,
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadFollowers,
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadFollowers,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_followers == null || _followers!.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFollowers,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Icon(Icons.people_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Center(
              child: Text(
                'No followers yet',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
            ),
            SizedBox(height: 8),
            Center(
              child: Text(
                'Followers will appear here once users follow this organization.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black45),
              ),
            ),
            SizedBox(height: 120),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFollowers,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _followers!.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final follower = _followers![index];
          return _buildFollowerTile(follower);
        },
      ),
    );
  }

  Widget _buildFollowerTile(UserProfile follower) {
    final displayName = follower.fullName?.isNotEmpty == true
        ? follower.fullName!.trim()
        : follower.email;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
        leading: _buildAvatar(follower),
        title: Text(
          displayName,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          follower.email,
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
      ),
    );
  }

  Widget _buildAvatar(UserProfile follower) {
    final photoUrl = follower.profilePictureUrl;

    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: NetworkImage(photoUrl),
      );
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: Colors.blueGrey.shade300,
      child: Text(
        _getInitials(
          follower.fullName ?? follower.username ?? follower.email,
        ),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getInitials(String value) {
    if (value.isEmpty) {
      return '?';
    }

    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    final first = parts.first.substring(0, 1).toUpperCase();
    final last = parts.last.substring(0, 1).toUpperCase();
    return '$first$last';
  }
}

