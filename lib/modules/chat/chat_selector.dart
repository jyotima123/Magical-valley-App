// lib/modules/chat/channel_selector.dart

import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/chat/models/chat_channel.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/api_service.dart';

class ChannelSelectorScreen extends StatefulWidget {
  final List<ChatChannel>? initialSelection;
  final String title;
  final bool allowMultipleSelection;
  final List<String>? excludeChannelIds;

  const ChannelSelectorScreen({
    super.key,
    this.initialSelection,
    this.title = 'Select Channels',
    this.allowMultipleSelection = true,
    this.excludeChannelIds,
  });

  @override
  State<ChannelSelectorScreen> createState() => _ChannelSelectorScreenState();
}

class _ChannelSelectorScreenState extends State<ChannelSelectorScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ApiService _apiService = SupabaseApiService.instance;

  List<ChatChannel> _allChannels = [];
  List<ChatChannel> _filteredChannels = [];
  Set<String> _selectedChannelIds = <String>{};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeSelection();
    _fetchChannels();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _initializeSelection() {
    if (widget.initialSelection != null) {
      _selectedChannelIds = widget.initialSelection!
          .map((channel) => channel.id)
          .toSet();
    }
  }

  Future<void> _fetchChannels() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get current user and their role
      final currentUser = await _apiService.getCurrentUser();
      if (currentUser == null) {
        setState(() {
          _error = 'User not authenticated';
          _isLoading = false;
        });
        return;
      }

      final userRoleResult = await _apiService.getUserRole(
        currentUser.userId ?? "",
      );
      if (!userRoleResult.isSuccess) {
        setState(() {
          _error = 'Failed to get user role: ${userRoleResult.error}';
          _isLoading = false;
        });
        return;
      }

      final userRole = userRoleResult.data!;
      List<ChatChannel> channels = [];

      if (userRole.isSuperAdmin) {
        // Super admins can see all channels
        final result = await _apiService.getAll<Map<String, dynamic>>(
          'organizations',
          orderBy: 'name',
          ascending: true,
        );

        if (result.isSuccess && result.data != null) {
          channels = (result.data! as List)
              .map((item) => ChatChannel.fromOrganization(item))
              .toList();
        } else {
          setState(() {
            _error = result.error ?? 'Failed to load channels';
            _isLoading = false;
          });
          return;
        }
      } else {
        // Regular users and admins can only see channels they manage
        final managedOrgsResult = await _apiService.getUserManagedOrganizations(
          currentUser.userId ?? "",
        );

        if (managedOrgsResult.isSuccess && managedOrgsResult.data != null) {
          channels = managedOrgsResult.data!
              .map((org) => ChatChannel.fromOrganization(org.toJson()))
              .toList();
        } else {
          setState(() {
            _error =
                managedOrgsResult.error ?? 'Failed to load managed channels';
            _isLoading = false;
          });
          return;
        }
      }

      setState(() {
        _allChannels = channels;

        // Filter out excluded channels if provided
        if (widget.excludeChannelIds != null &&
            widget.excludeChannelIds!.isNotEmpty) {
          _allChannels = _allChannels
              .where(
                (channel) => !widget.excludeChannelIds!.contains(channel.id),
              )
              .toList();
        }

        _filteredChannels = List.from(_allChannels);
        _isLoading = false;
      });
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
        _filteredChannels = List.from(_allChannels);
      } else {
        _filteredChannels = _allChannels.where((channel) {
          final name = channel.name.toLowerCase();
          final description = channel.description?.toLowerCase() ?? '';
          return name.contains(query) || description.contains(query);
        }).toList();
      }
    });
  }

  void _toggleChannelSelection(ChatChannel channel) {
    setState(() {
      if (widget.allowMultipleSelection) {
        if (_selectedChannelIds.contains(channel.id)) {
          _selectedChannelIds.remove(channel.id);
        } else {
          _selectedChannelIds.add(channel.id);
        }
      } else {
        // Single selection mode
        if (_selectedChannelIds.contains(channel.id)) {
          _selectedChannelIds.clear();
        } else {
          _selectedChannelIds.clear();
          _selectedChannelIds.add(channel.id);
        }
      }
    });
  }

  void _confirmSelection() {
    final selectedChannels = _allChannels
        .where((channel) => _selectedChannelIds.contains(channel.id))
        .toList();

    Navigator.of(context).pop(selectedChannels);
  }

  void _clearSelection() {
    setState(() {
      _selectedChannelIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        elevation: 0,
        actions: [
          if (_selectedChannelIds.isNotEmpty)
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
                hintText: 'Search channels by name or description...',
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
          if (_selectedChannelIds.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                widget.allowMultipleSelection
                    ? '${_selectedChannelIds.length} channel${_selectedChannelIds.length == 1 ? '' : 's'} selected'
                    : '1 channel selected',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

          // Channel list
          Expanded(child: _buildChannelList()),

          // Bottom action bar
          if (_selectedChannelIds.isNotEmpty)
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
                        ? 'Confirm Selection (${_selectedChannelIds.length})'
                        : 'Confirm Selection',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChannelList() {
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
              'Error loading channels',
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
              onPressed: _fetchChannels,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_filteredChannels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? 'No channels found'
                  : 'No channels match your search',
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
      itemCount: _filteredChannels.length,
      itemBuilder: (context, index) {
        final channel = _filteredChannels[index];
        final isSelected = _selectedChannelIds.contains(channel.id);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.accentSecondary,
            child: Text(
              channel.name.isNotEmpty ? channel.name[0].toUpperCase() : '#',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(
            channel.name,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle:
              channel.description != null && channel.description!.isNotEmpty
              ? Text(
                  channel.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              : Text(
                  'No description',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade600,
                  ),
                ),
          trailing: widget.allowMultipleSelection
              ? Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleChannelSelection(channel),
                )
              : Radio<bool>(
                  value: true,
                  groupValue: isSelected,
                  onChanged: (_) => _toggleChannelSelection(channel),
                ),
          selected: isSelected,
          onTap: () => _toggleChannelSelection(channel),
        );
      },
    );
  }
}

// Extension to make it easier to use the selector
extension ChannelSelectorExtension on BuildContext {
  Future<List<ChatChannel>?> showChannelSelector({
    List<ChatChannel>? initialSelection,
    String title = 'Select Channels',
    bool allowMultipleSelection = true,
    List<String>? excludeChannelIds,
  }) async {
    return await Navigator.of(this).push<List<ChatChannel>>(
      MaterialPageRoute(
        builder: (context) => ChannelSelectorScreen(
          initialSelection: initialSelection,
          title: title,
          allowMultipleSelection: allowMultipleSelection,
          excludeChannelIds: excludeChannelIds,
        ),
      ),
    );
  }
}
