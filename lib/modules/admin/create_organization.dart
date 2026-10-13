// lib/modules/admin/create_organization.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/chat/widgets/image_converter_service.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/api_service.dart';
import 'package:mvc_app/services/first_run_service.dart';

class CreateOrganizationScreen extends StatefulWidget {
  const CreateOrganizationScreen({super.key});

  @override
  State<CreateOrganizationScreen> createState() =>
      _CreateOrganizationScreenState();
}

class _CreateOrganizationScreenState extends State<CreateOrganizationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _logoUrlController = TextEditingController();

  List<Map<String, dynamic>> _categories = [];
  final Set<String> _selectedCategoryIds = {};
  bool _isLoading = false;
  bool _isLoadingCategories = false;
  bool _isUploadingLogo = false;
  String? _currentUserId;
  String? _logoUrl;
  Uint8List? _logoBytes;

  final ApiService _apiService = SupabaseApiService.instance;

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
    _loadCategories();
    // Show first-time hint dialog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowFirstTimeHint();
    });
  }

  Future<void> _maybeShowFirstTimeHint() async {
    await FirstRunService.instance.maybeShowHint(
      context,
      key: FirstRunHintKeys.createOrganization,
      icon: Icons.business,
    );
  }

  Future<void> _getCurrentUser() async {
    try {
      final result = await _apiService.getCurrentUser();
      if (result != null) {
        setState(() {
          _currentUserId = result.userId;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error getting current user: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _logoUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoadingCategories = true;
    });

    try {
      final result = await _apiService.getAll<Map<String, dynamic>>(
        'categories',
        orderBy: 'name',
        ascending: true,
      );

      if (result.isSuccess) {
        setState(() {
          _categories = result.data!;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load categories: ${result.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading categories: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoadingCategories = false;
      });
    }
  }

  Future<void> _createOrganization() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedCategoryIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one category'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // First, create the organization
      final organizationData = {
        'name': _nameController.text.trim(),
        'logo_url':
            _logoUrl ??
            (_logoUrlController.text.trim().isEmpty
                ? null
                : _logoUrlController.text.trim()),
        'follower_count': 0,
      };

      final orgResult = await _apiService.create(
        'organizations',
        organizationData,
      );

      if (orgResult.isSuccess) {
        final organizationId = orgResult.data!['id'];

        // Then, assign categories to the organization
        bool allCategoriesAssigned = true;
        for (String categoryId in _selectedCategoryIds) {
          final categoryAssignmentData = {
            'organization_id': organizationId,
            'category_id': categoryId,
          };

          final categoryResult = await _apiService.create(
            'organization_categories',
            categoryAssignmentData,
          );

          if (!categoryResult.isSuccess) {
            allCategoriesAssigned = false;
            print(
              'Failed to assign category $categoryId: ${categoryResult.error}',
            );
          }
        }

        if (allCategoriesAssigned) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Channel created successfully!'),
              backgroundColor: Colors.green,
            ),
          );

          // Clear form
          _nameController.clear();
          _logoUrlController.clear();
          setState(() {
            _selectedCategoryIds.clear();
            _logoUrl = null;
            _logoBytes = null;
          });

          // Navigate back
          Navigator.pop(context, organizationId);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Channel created but some categories failed to assign',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create channel: ${orgResult.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating channel: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildCategorySelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Categories',
              style: AppTheme.managementSubtitleText.copyWith(fontSize: 18),
            ),
            const SizedBox(width: 8),
            Text(
              '(${_selectedCategoryIds.length} selected)',
              style: AppTheme.managementTitleText.copyWith(
                fontSize: 14,
                color: AppTheme.primaryHeadingColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Select at least one category for this Channel',
          style: AppTheme.managementTitleText.copyWith(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 16),

        if (_isLoadingCategories)
          const Center(child: CircularProgressIndicator())
        else if (_categories.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardGreyBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.managementCardBorder),
            ),
            child: const Text('No categories available'),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppTheme.cardGreyBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.managementCardBorder),
            ),
            child: Column(
              children: _categories.asMap().entries.map((entry) {
                final index = entry.key;
                final category = entry.value;
                final categoryId = category['id'].toString();
                final categoryName = category['name'].toString();
                final isSelected = _selectedCategoryIds.contains(categoryId);

                return Column(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _toggleCategory(categoryId),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primaryHeadingColor
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primaryHeadingColor
                                        : Colors.grey[400]!,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 16,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      categoryName,
                                      style: AppTheme.chatTitle.copyWith(
                                        fontSize: 16,
                                        color: AppTheme.primaryHeadingColor,
                                      ),
                                    ),
                                    if (category['description'] != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        category['description'].toString(),
                                        style: AppTheme.managementTitleText
                                            .copyWith(
                                              fontSize: 14,
                                              color: Colors.grey[600],
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (index < _categories.length - 1)
                      const Divider(
                        height: 1,
                        thickness: 0.5,
                        color: AppTheme.managementCardBorder,
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  void _toggleCategory(String categoryId) {
    setState(() {
      if (_selectedCategoryIds.contains(categoryId)) {
        _selectedCategoryIds.remove(categoryId);
      } else {
        _selectedCategoryIds.add(categoryId);
      }
    });
  }

  Future<void> _uploadLogoImage(ImageSource source) async {
    setState(() {
      _isUploadingLogo = true;
    });

    try {
      final pickedImage = await ImagePicker().pickImage(source: source);
      if (pickedImage != null) {
        Uint8List imageBytes = await pickedImage.readAsBytes();

        // Check if it's HEIC and convert to PNG
        if (ImageConverterService.isHeicFormat(imageBytes)) {
          final convertedBytes = await ImageConverterService.convertHeicToPng(
            imageBytes,
          );
          if (convertedBytes != null) {
            imageBytes = convertedBytes;
          }
        }

        final result = await (_apiService as SupabaseApiService)
            .uploadGenericFile(
              fileBytes: imageBytes,
              fileName: "org_logo_${DateTime.now().millisecondsSinceEpoch}.png",
              userId: _currentUserId ?? '',
            );

        if (result.isSuccess && result.data != null) {
          final imageUrl = result.data as String;
          setState(() {
            _logoUrl = imageUrl;
            _logoBytes = imageBytes;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Logo uploaded successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to upload logo: ${result.error}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error uploading logo: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isUploadingLogo = false;
      });
    }
  }

  void _showLogoAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppTheme.cardGreyBackground,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            _buildLogoAttachmentOption(
              Icons.photo_library,
              'Choose from Gallery',
              () {
                Navigator.pop(context);
                _uploadLogoImage(ImageSource.gallery);
              },
            ),
            _buildLogoAttachmentOption(Icons.camera_alt, 'Take Photo', () {
              Navigator.pop(context);
              _uploadLogoImage(ImageSource.camera);
            }),
            _buildLogoAttachmentOption(Icons.link, 'Enter URL', () {
              Navigator.pop(context);
              _showUrlInputDialog();
            }),
            if (_logoUrl != null || _logoBytes != null)
              _buildLogoAttachmentOption(Icons.delete, 'Remove Logo', () {
                Navigator.pop(context);
                setState(() {
                  _logoUrl = null;
                  _logoBytes = null;
                });
              }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoAttachmentOption(
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryHeadingColor, size: 24),
            const SizedBox(width: 16),
            Text(title, style: AppTheme.managementTitleText),
          ],
        ),
      ),
    );
  }

  void _showUrlInputDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Logo URL'),
        content: TextField(
          controller: _logoUrlController,
          decoration: const InputDecoration(
            hintText: 'https://example.com/logo.png',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _logoUrl = _logoUrlController.text.trim();
                _logoBytes = null;
              });
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Channel'),
        elevation: 0,
        backgroundColor: AppTheme.headerBackground,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section
              Text(
                'Create New Channel',
                style: AppTheme.primaryHeading.copyWith(fontSize: 24),
              ),
              const SizedBox(height: 8),
              Text(
                'Fill in the details below to create a new Channel',
                style: AppTheme.secondaryHeading.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 32),

              // Organization Details Section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.cardGreyBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.managementCardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Channel Details',
                      style: AppTheme.managementSubtitleText.copyWith(
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Organization Name Field
                    Text(
                      'Channel Name',
                      style: AppTheme.managementTitleText.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        hintText: 'Enter Channel name',
                        filled: true,
                        fillColor: AppTheme.white,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter an Channel name';
                        }
                        if (value.trim().length < 2) {
                          return 'Channel name must be at least 2 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Logo Field
                    Text(
                      'Logo (Optional)',
                      style: AppTheme.managementTitleText.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Logo Preview
                    if (_logoUrl != null || _logoBytes != null) ...[
                      Container(
                        height: 120,
                        width: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.managementCardBorder,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _logoBytes != null
                              ? Image.memory(_logoBytes!, fit: BoxFit.cover)
                              : Image.network(
                                  _logoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey[300],
                                      child: const Icon(Icons.error, size: 40),
                                    );
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Logo Input Field with Attachment Button
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _logoUrlController,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              hintText: _logoUrl != null
                                  ? 'Logo uploaded successfully'
                                  : 'Enter logo URL or attach image',
                              filled: true,
                              fillColor: AppTheme.white,
                              enabled: _logoUrl == null,
                            ),
                            validator: (value) {
                              if (value != null && value.trim().isNotEmpty) {
                                final uri = Uri.tryParse(value.trim());
                                if (uri == null || !uri.hasScheme) {
                                  return 'Please enter a valid URL';
                                }
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: _showLogoAttachmentMenu,
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryHeadingColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: _isUploadingLogo
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.attach_file,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Category Selection Section
              _buildCategorySelection(),
              const SizedBox(height: 32),

              // Current User Info Section
              if (_currentUserId != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue[700],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'You will be automatically assigned as the admin of this Channel.',
                          style: AppTheme.managementTitleText.copyWith(
                            color: Colors.blue[700],
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              // Create Organization Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _createOrganization,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryHeadingColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Create Channel',
                          style: AppTheme.chatTitle.copyWith(
                            color: Colors.white,
                            fontSize: 16,
                          ),
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
