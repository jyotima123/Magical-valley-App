// lib/modules/chat/select_organization_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';
import 'package:mvc_app/services/api_repository.dart';

class SelectOrganizationScreen extends StatefulWidget {
  final List<String>? allowedOrganizationIds;
  
  const SelectOrganizationScreen({
    super.key,
    this.allowedOrganizationIds,
  });

  @override
  State<SelectOrganizationScreen> createState() =>
      _SelectOrganizationScreenState();
}

class _SelectOrganizationScreenState extends State<SelectOrganizationScreen> {
  List<Organization>? _organizations;
  List<Organization>? _filteredOrganizations;
  bool _isLoading = true;
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadOrganizations();
    _searchController.addListener(_filterOrganizations);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterOrganizations);
    _searchController.dispose();
    super.dispose();
  }

  void _filterOrganizations() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredOrganizations = _organizations;
      });
    } else {
      setState(() {
        _filteredOrganizations = _organizations
            ?.where((org) => org.name.toLowerCase().contains(query))
            .toList();
      });
    }
  }

  Future<void> _loadOrganizations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiRepository = context.read<ApiRepository>();
      final result = await apiRepository.getAllOrganizations(
        orderBy: 'name',
        ascending: true,
      );

      if (result.isSuccess) {
        var organizations = result.data ?? [];
        
        // Filter by allowed organization IDs if provided
        if (widget.allowedOrganizationIds != null && 
            widget.allowedOrganizationIds!.isNotEmpty) {
          organizations = organizations
              .where((org) => widget.allowedOrganizationIds!.contains(org.id))
              .toList();
        }
        
        setState(() {
          _organizations = organizations;
          _filteredOrganizations = organizations;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = result.error ?? 'Failed to load organizations';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred: $e';
        _isLoading = false;
      });
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

  void _selectOrganization(Organization organization) {
    Navigator.pop(context, organization);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cardGreyBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Select Organization'),
        backgroundColor: AppTheme.headerBackground,
        foregroundColor: AppTheme.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              style: AppTheme.searchInput,
              decoration: InputDecoration(
                hintText: 'Search channels...',
                hintStyle: AppTheme.searchInput.copyWith(
                  color: AppTheme.secondaryHeadingColor,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: AppTheme.secondaryHeadingColor,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: AppTheme.secondaryHeadingColor,
                        ),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppTheme.searchBarBackground,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          // Organizations list
          Expanded(child: _buildBody()),
        ],
      ),
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
              onPressed: _loadOrganizations,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentPrimary,
              ),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (_filteredOrganizations == null || _filteredOrganizations!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.business_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? 'No channels available'
                  : 'No channels found',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrganizations,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredOrganizations!.length,
        itemBuilder: (context, index) {
          final organization = _filteredOrganizations![index];
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
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: AppTheme.accentPrimary.withOpacity(0.15),
          backgroundImage:
              organization.logoUrl != null && organization.logoUrl!.isNotEmpty
              ? NetworkImage(organization.logoUrl!)
              : null,
          child: organization.logoUrl == null || organization.logoUrl!.isEmpty
              ? Text(
                  _getOrganizationInitials(organization.name),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accentPrimary,
                  ),
                )
              : null,
        ),
        title: Text(
          organization.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: AppTheme.secondaryHeadingColor,
        ),
        onTap: () => _selectOrganization(organization),
      ),
    );
  }
}
