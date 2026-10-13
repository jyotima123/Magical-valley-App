// lib/screens/create_post_screen.dart

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/posts/create_post_screen.dart';
import 'package:mvc_app/modules/posts/models/attachment_data.dart';
import 'package:http/http.dart' as http;

class AttachmentFloatingCard extends StatefulWidget {
  final String attachmentType;
  final VoidCallback onDismiss;
  final Function(AttachmentData) onAttachmentSelected;

  const AttachmentFloatingCard({
    super.key,
    required this.attachmentType,
    required this.onDismiss,
    required this.onAttachmentSelected,
  });

  @override
  State<AttachmentFloatingCard> createState() => _AttachmentFloatingCardState();
}

class _AttachmentFloatingCardState extends State<AttachmentFloatingCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _linkTitleController = TextEditingController();
  final TextEditingController _linkUrlController = TextEditingController();
  bool _isLoading = false;
  AttachmentData? _pendingAttachment;
  bool _showPreview = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _urlController.dispose();
    _linkTitleController.dispose();
    _linkUrlController.dispose();
    super.dispose();
  }

  bool _isImageUrl(String url) {
    final lowerUrl = url.toLowerCase();
    return lowerUrl.endsWith('.png') ||
        lowerUrl.endsWith('.jpg') ||
        lowerUrl.endsWith('.jpeg') ||
        lowerUrl.endsWith('.webp');
  }

  void _showPreviewDialog(AttachmentData attachment) {
    setState(() {
      _pendingAttachment = attachment;
      _showPreview = true;
    });
  }

  void _confirmAttachment() {
    if (_pendingAttachment != null) {
      widget.onAttachmentSelected(_pendingAttachment!);
      widget.onDismiss();
    }
  }

  void _cancelPreview() {
    setState(() {
      _pendingAttachment = null;
      _showPreview = false;
    });
  }

  Future<void> _pasteToController(TextEditingController controller) async {
    ClipboardData? data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null) {
      controller.text = data.text!;
    }
  }

  Future<void> _handleImageFromGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      final attachment = AttachmentData(
        type: 'image',
        filePath: image.path,
        fileName: image.name,
        fileBytes: bytes,
      );
      _showPreviewDialog(attachment);
    }
  }

  Future<void> _handleImageFromCamera() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      final bytes = await image.readAsBytes();
      final attachment = AttachmentData(
        type: 'image',
        filePath: image.path,
        fileName: image.name,
        fileBytes: bytes,
      );
      _showPreviewDialog(attachment);
    }
  }

  Future<void> _handleImageFromUrl() async {
    if (_urlController.text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final response = await http.get(Uri.parse(_urlController.text));
      if (response.statusCode == 200) {
        final attachment = AttachmentData(
          type: 'image',
          url: _urlController.text,
          fileName: 'image_from_url',
          fileBytes: response.bodyBytes,
        );
        _showPreviewDialog(attachment);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load image: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePdfPicker() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      final file = result.files.first;
      final attachment = AttachmentData(
        type: 'pdf',
        filePath: file.path,
        fileName: file.name,
        fileBytes: file.bytes,
      );
      _showPreviewDialog(attachment);
    }
  }

  Future<void> _handlePaste() async {
    ClipboardData? data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null) {
      final attachment = AttachmentData(type: 'paste', textContent: data.text);
      _showPreviewDialog(attachment);
    }
  }

  void _handleAddLink() {
    if (_linkTitleController.text.isNotEmpty &&
        _linkUrlController.text.isNotEmpty) {
      final attachment = AttachmentData(
        type: 'link',
        textContent: '${_linkTitleController.text}|${_linkUrlController.text}',
      );
      _showPreviewDialog(attachment);
    }
  }

  Widget _buildTextFieldWithPaste({
    required TextEditingController controller,
    required String hintText,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        suffixIcon: IconButton(
          icon: const Icon(Icons.content_paste, size: 18),
          onPressed: () => _pasteToController(controller),
          tooltip: 'Paste',
        ),
      ),
    );
  }

  Widget _buildImageOptions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildOptionButton(
          Icons.photo_library,
          'Upload from Gallery',
          _handleImageFromGallery,
        ),
        const SizedBox(height: 12),
        const Text('OR', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 12),
        TextField(
          controller: _urlController,
          decoration: InputDecoration(
            hintText: 'Enter image URL',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          onChanged: (value) => setState(() {}), // Rebuild to show/hide preview
        ),
        const SizedBox(height: 12),
        if (_urlController.text.isNotEmpty && _isImageUrl(_urlController.text))
          Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                _urlController.text,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey),
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
              ),
            ),
          ),
        if (_urlController.text.isNotEmpty && _isImageUrl(_urlController.text))
          const SizedBox(height: 12),
        _buildOptionButton(
          Icons.link,
          'Load from URL',
          _isLoading ? null : _handleImageFromUrl,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  Widget _buildCameraOption() {
    return _buildOptionButton(
      Icons.camera_alt,
      'Take Photo Now',
      _handleImageFromCamera,
    );
  }

  Widget _buildPdfOption() {
    return _buildOptionButton(
      Icons.picture_as_pdf,
      'Select PDF File',
      _handlePdfPicker,
    );
  }

  Widget _buildLinkOption() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTextFieldWithPaste(
          controller: _linkTitleController,
          hintText: 'Link title',
        ),
        const SizedBox(height: 12),
        _buildTextFieldWithPaste(
          controller: _linkUrlController,
          hintText: 'https://example.com',
        ),
        const SizedBox(height: 12),
        if (_linkUrlController.text.isNotEmpty &&
            _isImageUrl(_linkUrlController.text))
          Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                _linkUrlController.text,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey),
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
              ),
            ),
          ),
        if (_linkUrlController.text.isNotEmpty &&
            _isImageUrl(_linkUrlController.text))
          const SizedBox(height: 12),
        _buildOptionButton(Icons.add_link, 'Add Link', _handleAddLink),
      ],
    );
  }

  Widget _buildPasteOption() {
    return _buildOptionButton(
      Icons.content_paste,
      'Paste from Clipboard',
      _handlePaste,
    );
  }

  Widget _buildPreviewDialog() {
    if (_pendingAttachment == null) return const SizedBox();

    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.darkBottomBarBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Does this look right?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.white,
                ),
              ),
              const SizedBox(height: 16),
              _buildPreviewContent(),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    onPressed: _cancelPreview,
                    icon: const Icon(Icons.close, color: Colors.red),
                    iconSize: 32,
                    tooltip: 'Cancel',
                  ),
                  IconButton(
                    onPressed: _confirmAttachment,
                    icon: const Icon(Icons.check, color: Colors.green),
                    iconSize: 32,
                    tooltip: 'Confirm',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewContent() {
    final attachment = _pendingAttachment!;

    switch (attachment.type) {
      case 'image':
        if (attachment.fileBytes != null) {
          return Container(
            constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(attachment.fileBytes!, fit: BoxFit.contain),
            ),
          );
        } else if (attachment.url != null) {
          return Container(
            constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                attachment.url!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.broken_image, size: 50);
                },
              ),
            ),
          );
        }
        break;
      case 'pdf':
        return Column(
          children: [
            const Icon(Icons.picture_as_pdf, size: 50, color: Colors.red),
            const SizedBox(height: 8),
            Text(attachment.fileName ?? 'PDF File'),
          ],
        );
      case 'link':
        final parts = attachment.textContent?.split('|') ?? [];
        final title = parts.isNotEmpty ? parts[0] : 'Link';
        final url = parts.length > 1 ? parts[1] : '';
        return Column(
          children: [
            const Icon(Icons.link, size: 50, color: Colors.blue),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            if (url.isNotEmpty)
              Text(url, style: const TextStyle(color: Colors.grey)),
          ],
        );
      case 'paste':
        return Column(
          children: [
            const Icon(Icons.content_paste, size: 50, color: Colors.orange),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 150, maxWidth: 300),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  attachment.textContent ?? '',
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        );
      default:
        return const Icon(Icons.attachment, size: 50);
    }
    return const SizedBox();
  }

  Widget _buildOptionButton(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showPreview) {
      return _buildPreviewDialog();
    }

    return GestureDetector(
      onTap: widget.onDismiss,
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Prevent dismissing when tapping the card
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Opacity(
                    opacity: _opacityAnimation.value,
                    child: Container(
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                _getCardTitle(),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: widget.onDismiss,
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _getCardContent(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _getCardTitle() {
    switch (widget.attachmentType) {
      case 'image':
        return 'Insert Photo';
      case 'camera':
        return 'Take Photo';
      case 'pdf':
        return 'Attach PDF';
      case 'link':
        return 'Add Link';
      case 'paste':
        return 'Paste Content';
      default:
        return 'Attachment';
    }
  }

  Widget _getCardContent() {
    switch (widget.attachmentType) {
      case 'image':
        return _buildImageOptions();
      case 'camera':
        return _buildCameraOption();
      case 'pdf':
        return _buildPdfOption();
      case 'link':
        return _buildLinkOption();
      case 'paste':
        return _buildPasteOption();
      default:
        return const SizedBox();
    }
  }
}
