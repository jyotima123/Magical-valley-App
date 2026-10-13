import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/api_service.dart';

class UserSelectorScreen extends StatefulWidget {
  final List<UserProfile>? initialSelection;
  final String title;
  final bool allowMultipleSelection;
  final List<String>? excludeUserIds;

  const UserSelectorScreen({
    super.key,
    this.initialSelection,
    this.title = 'Select Users',
    this.allowMultipleSelection = true,
    this.excludeUserIds,
  });

  @override
  State<UserSelectorScreen> createState() => _UserSelectorScreenState();
}

class _UserSelectorScreenState extends State<UserSelectorScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ApiService _apiService =
      SupabaseApiService.instance; // Replace with your actual service instance

  List<UserProfile> _allUsers = [];
  List<UserProfile> _filteredUsers = [];
  Set<String> _selectedUserIds = <String>{};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeSelection();
    _fetchUsers();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _initializeSelection() {
    if (widget.initialSelection != null) {
      _selectedUserIds = widget.initialSelection!
          .map((user) => user.id)
          .toSet();
    }
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _apiService.getAll<Map<String, dynamic>>(
        'user_profiles',
        filters: {'role': 'regular'},
        orderBy: 'full_name',
        ascending: true,
      );

      if (result.isSuccess && result.data != null) {
        setState(() {
          final List<UserProfile> users = (result.data! as List)
              .map((item) => UserProfile.fromJson(item))
              .toList();

          _allUsers = users;

          // Filter out excluded users if provided
          if (widget.excludeUserIds != null &&
              widget.excludeUserIds!.isNotEmpty) {
            _allUsers = _allUsers
                .where((user) => !widget.excludeUserIds!.contains(user.id))
                .toList();
          }

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
          return name.contains(query) || email.contains(query);
        }).toList();
      }
    });
  }

  void _toggleUserSelection(UserProfile user) {
    setState(() {
      if (widget.allowMultipleSelection) {
        if (_selectedUserIds.contains(user.id)) {
          _selectedUserIds.remove(user.id);
        } else {
          _selectedUserIds.add(user.id);
        }
      } else {
        // Single selection mode
        if (_selectedUserIds.contains(user.id)) {
          _selectedUserIds.clear();
        } else {
          _selectedUserIds.clear();
          _selectedUserIds.add(user.id);
        }
      }
    });
  }

  void _confirmSelection() {
    final selectedUsers = _allUsers
        .where((user) => _selectedUserIds.contains(user.id))
        .toList();

    Navigator.of(context).pop(selectedUsers);
  }

  void _clearSelection() {
    setState(() {
      _selectedUserIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        elevation: 0,
        actions: [
          if (_selectedUserIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: _clearSelection,
              tooltip: 'Clear selection',
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
                hintText: 'Search users by name or email...',
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

          // Selection info
          if (_selectedUserIds.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                widget.allowMultipleSelection
                    ? '${_selectedUserIds.length} user${_selectedUserIds.length == 1 ? '' : 's'} selected'
                    : '1 user selected',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

          // User list
          Expanded(child: _buildUserList()),

          // Bottom action bar
          if (_selectedUserIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 0.5,
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _confirmSelection,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    widget.allowMultipleSelection
                        ? 'Confirm Selection (${_selectedUserIds.length})'
                        : 'Confirm Selection',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUserList() {
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

    return ListView.builder(
      itemCount: _filteredUsers.length,
      itemBuilder: (context, index) {
        final user = _filteredUsers[index];
        final isSelected = _selectedUserIds.contains(user.id);

        return ListTile(
          leading: CircleAvatar(
            backgroundImage: user.profilePictureUrl != null
                ? NetworkImage(user.profilePictureUrl!)
                : null,
            child: user.profilePictureUrl == null
                ? Text(
                    user.fullName?.isNotEmpty == true
                        ? user.fullName![0].toUpperCase()
                        : user.email[0].toUpperCase(),
                  )
                : null,
          ),
          title: Text(
            user.fullName ?? 'No name',
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: Text(user.email),
          trailing: widget.allowMultipleSelection
              ? Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleUserSelection(user),
                )
              : Radio<bool>(
                  value: true,
                  groupValue: isSelected,
                  onChanged: (_) => _toggleUserSelection(user),
                ),
          selected: isSelected,
          onTap: () => _toggleUserSelection(user),
        );
      },
    );
  }
}

// Extension to make it easier to use the selector
extension UserSelectorExtension on BuildContext {
  Future<List<UserProfile>?> showUserSelector({
    List<UserProfile>? initialSelection,
    String title = 'Select Users',
    bool allowMultipleSelection = true,
    List<String>? excludeUserIds,
  }) async {
    return await Navigator.of(this).push<List<UserProfile>>(
      MaterialPageRoute(
        builder: (context) => UserSelectorScreen(
          initialSelection: initialSelection,
          title: title,
          allowMultipleSelection: allowMultipleSelection,
          excludeUserIds: excludeUserIds,
        ),
      ),
    );
  }
}
