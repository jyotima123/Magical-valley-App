// lib/screens/create_post_screen.dart
import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/api/api_service_factory.dart';

class CreatePostScreenNoAnimation extends StatefulWidget {
  final String organizationId;
  final String userId;

  const CreatePostScreenNoAnimation({
    super.key,
    required this.organizationId,
    required this.userId,
  });

  @override
  State<CreatePostScreenNoAnimation> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreenNoAnimation> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _contentFocusNode = FocusNode();

  String _selectedPostType = 'text';
  String? _attachedFileUrl;
  bool _isLoading = false;

  // Initialize API repository
  late final ApiRepository _apiRepository;

  @override
  void initState() {
    super.initState();
    final apiService = ApiServiceFactory.createApiService(ApiProvider.supabase);
    _apiRepository = ApiRepository(apiService);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _titleFocusNode.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _createPost() async {
    // Validate that we have either title or content
    if (_titleController.text.trim().isEmpty &&
        _contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please add a title or content to your post'),
          backgroundColor: context.accentPrimary,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final postData = {
        'organization_id': widget.organizationId,
        'created_by': widget.userId,
        'title': _titleController.text.trim().isEmpty
            ? null
            : _titleController.text.trim(),
        'content': _contentController.text.trim().isEmpty
            ? null
            : _contentController.text.trim(),
        'post_type': _selectedPostType,
        'file_url': _attachedFileUrl,
        'status': 'active',
      };

      final result = await _apiRepository.create('posts', postData);

      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Post sent successfully!'),
            backgroundColor: context.success,
          ),
        );

        // Clear form
        _titleController.clear();
        _contentController.clear();
        setState(() {
          _selectedPostType = 'text';
          _attachedFileUrl = null;
        });

        // Navigate back
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send post: ${result.error}'),
            backgroundColor: context.error,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending post: ${e.toString()}'),
          backgroundColor: context.error,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.darkSurface,
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
                color: context.darkTextTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            _buildAttachmentOption(Icons.photo_library, 'Insert Photo', () {
              Navigator.pop(context);
              // TODO: Implement photo picker
              setState(() {
                _selectedPostType = 'image';
              });
            }),
            _buildAttachmentOption(Icons.camera_alt, 'Take Photo now', () {
              Navigator.pop(context);
              // TODO: Implement camera
              setState(() {
                _selectedPostType = 'image';
              });
            }),
            _buildAttachmentOption(Icons.picture_as_pdf, 'Attach PDF', () {
              Navigator.pop(context);
              // TODO: Implement PDF picker
              setState(() {
                _selectedPostType = 'pdf';
              });
            }),
            _buildAttachmentOption(Icons.link, 'Add Link', () {
              Navigator.pop(context);
              // TODO: Implement link dialog
            }),
            _buildAttachmentOption(Icons.content_paste, 'Paste', () {
              Navigator.pop(context);
              // TODO: Implement clipboard paste
            }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentOption(
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
            Icon(icon, color: context.darkTextSecondary, size: 24),
            const SizedBox(width: 16),
            Text(title, style: context.darkAttachmentOption),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomTextField(
    String label,
    String hint,
    FocusNode focusNode,
    TextEditingController controller, {
    int? maxLines,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.darkFieldLabel),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          maxLines: maxLines ?? 1,
          keyboardType: keyboardType,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: context.darkFieldHint,
            filled: true,
            fillColor: context.darkInputBackground,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 20,
              vertical: maxLines != null && maxLines > 1 ? 20 : 15,
            ),
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
              borderSide: BorderSide(color: context.accentPrimary, width: 1),
            ),
          ),
          style: context.darkFieldText,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.darkBackground,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: context.darkBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.darkText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Create Post', style: context.darkAppBarTitle),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Form content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(30.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),

                    // Title Field
                    _buildCustomTextField(
                      'TITLE',
                      'What\'s this about?',
                      _titleFocusNode,
                      _titleController,
                    ),

                    const SizedBox(height: 24),

                    // Content Field (larger textarea)
                    _buildCustomTextField(
                      'CONTENT',
                      'Share your thoughts...',
                      _contentFocusNode,
                      _contentController,
                      maxLines: 8,
                      keyboardType: TextInputType.multiline,
                    ),

                    const SizedBox(height: 20),

                    // Show attachment info if something is attached
                    if (_selectedPostType != 'text') ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.accentPrimary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: context.accentPrimary.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _selectedPostType == 'image'
                                  ? Icons.image
                                  : Icons.picture_as_pdf,
                              color: context.accentPrimary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_selectedPostType.toUpperCase()} will be attached',
                              style: AppTheme.darkAttachmentOption,
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedPostType = 'text';
                                  _attachedFileUrl = null;
                                });
                              },
                              child: Icon(
                                Icons.close,
                                color: context.accentPrimary,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),

            // Bottom action bar
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.darkBottomBarBackground,
                border: Border(
                  top: BorderSide(color: context.darkBorder, width: 1),
                ),
              ),
              child: Row(
                children: [
                  // Attachment button
                  GestureDetector(
                    onTap: _showAttachmentMenu,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: context.darkInputBackground,
                        borderRadius: BorderRadius.circular(
                          AppTheme.actionButtonRadius,
                        ),
                      ),
                      child: Icon(
                        Icons.attach_file,
                        color: context.darkTextSecondary,
                        size: 24,
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Send button
                  GestureDetector(
                    onTap: _isLoading ? null : _createPost,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: _isLoading
                            ? context.darkDisabledButton
                            : context.accentPrimary,
                        borderRadius: BorderRadius.circular(
                          AppTheme.actionButtonRadius,
                        ),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  context.darkText,
                                ),
                              ),
                            )
                          : Icon(Icons.send, color: context.darkText, size: 24),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
