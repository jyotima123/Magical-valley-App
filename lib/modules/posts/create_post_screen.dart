// lib/screens/create_post_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mvc_app/modules/chat/widgets/image_converter_service.dart';
import 'package:mvc_app/modules/posts/attachment_floating_card.dart';
import 'package:mvc_app/modules/posts/models/attachment_data.dart';
import 'dart:io';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/modules/chat/chat_bloc.dart';
import 'package:mvc_app/services/first_run_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:convert';
import 'package:clipboad_image/clipboad_image.dart';

class AttachmentPreview extends StatelessWidget {
  final AttachmentData attachment;
  final VoidCallback onRemove;

  const AttachmentPreview({
    super.key,
    required this.attachment,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.accentPrimary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.accentPrimary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_getIcon(), color: context.accentPrimary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_getTitle(), style: AppTheme.darkAttachmentOption),
              ),
              GestureDetector(
                onTap: onRemove,
                child: Icon(
                  Icons.close,
                  color: context.accentPrimary,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildPreviewContent(context),
        ],
      ),
    );
  }

  IconData _getIcon() {
    switch (attachment.type) {
      case 'image':
        return Icons.image;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'link':
        return Icons.link;
      case 'paste':
        return Icons.content_paste;
      default:
        return Icons.attach_file;
    }
  }

  String _getTitle() {
    switch (attachment.type) {
      case 'image':
        return 'Image: ${attachment.fileName ?? 'Unknown'}';
      case 'pdf':
        return 'PDF: ${attachment.fileName ?? 'Unknown'}';
      case 'link':
        final parts = attachment.textContent?.split('|') ?? [];
        return 'Link: ${parts.isNotEmpty ? parts[0] : 'Unknown'}';
      case 'paste':
        return 'Pasted Content';
      default:
        return 'Attachment';
    }
  }

  Widget _buildPreviewContent(BuildContext context) {
    switch (attachment.type) {
      case 'image':
        return _buildImagePreview();
      case 'pdf':
        return _buildPdfPreview();
      case 'link':
        return _buildLinkPreview();
      case 'paste':
        return _buildPastePreview();
      default:
        return const SizedBox();
    }
  }

  Widget _buildImagePreview() {
    if (attachment.fileBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          attachment.fileBytes!,
          height: 120,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    } else if (attachment.filePath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(attachment.filePath!),
          height: 120,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    } else if (attachment.url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          attachment.url!,
          height: 120,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              height: 120,
              width: double.infinity,
              color: Colors.grey[300],
              child: const Icon(Icons.error, size: 40),
            );
          },
        ),
      );
    }
    return const SizedBox();
  }

  Widget _buildPdfPreview() {
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.picture_as_pdf, size: 40, color: Colors.red),
          SizedBox(height: 8),
          Text('PDF Preview'),
          Text(
            '(preview not available for this type of file)',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkPreview() {
    final parts = attachment.textContent?.split('|') ?? [];
    final title = parts.isNotEmpty ? parts[0] : 'Link';
    final url = parts.length > 1 ? parts[1] : '';

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          if (url.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(url, style: const TextStyle(color: Colors.blue, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _buildPastePreview() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Text(
        attachment.textContent ?? '',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

class CreatePostScreen extends StatefulWidget {
  final String organizationId;
  final String userId;
  final String? initialContent;
  final AppThemeMode? theme;
  final VoidCallback?
  onPostCreated; // Can execute something after post creation
  final Uint8List? initialImageBytes; // For pasted images from message input

  const CreatePostScreen({
    super.key,
    required this.organizationId,
    required this.userId,
    this.initialContent,
    this.theme,
    this.onPostCreated,
    this.initialImageBytes,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _contentFocusNode = FocusNode();

  final List<AttachmentData> _attachments = [];
  bool _isLoading = false;
  bool _isUploadingImage = false;
  OverlayEntry? _overlayEntry;
  String? _errorMessage;

  List<String> _attachedFileUrls = [];

  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  late final SupabaseApiService _apiService;

  @override
  void initState() {
    super.initState();
    _apiService = SupabaseApiService.instance;

    if (widget.initialContent != null && widget.initialContent!.isNotEmpty) {
      _contentController.text = widget.initialContent!;
    }

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _slideController.forward();
      _fadeController.forward();

      if (widget.initialContent != null && widget.initialContent!.isNotEmpty) {
        _contentFocusNode.requestFocus();
      }

      // Process initial image if provided (from paste in message input)
      if (widget.initialImageBytes != null) {
        setState(() {
          _isUploadingImage = true;
          _errorMessage = null;
        });
        try {
          await _processImageBytes(widget.initialImageBytes!);
        } catch (e) {
          print("📋 Error processing initial image: $e");
          if (mounted) {
            setState(() {
              _errorMessage = 'Failed to process pasted image: ${e.toString()}';
              _isUploadingImage = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_errorMessage!),
                backgroundColor: context.error,
              ),
            );
          }
        }
      }

      // Show first-time hint dialog
      _maybeShowFirstTimeHint();
    });
  }

  Future<void> _maybeShowFirstTimeHint() async {
    await FirstRunService.instance.maybeShowHint(
      context,
      key: FirstRunHintKeys.createPost,
      icon: Icons.create,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _titleFocusNode.dispose();
    _contentFocusNode.dispose();
    _slideController.dispose();
    _fadeController.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showAttachmentCard(String attachmentType) {
    _removeOverlay();

    if (attachmentType == 'image') {
      _uploadImage(ImageSource.gallery, allowMultiple: true);
      return;
    }

    if (attachmentType == 'pdf') {
      _uploadPdf();
      return;
    }

    // Handle other attachment types (link, paste)
    _overlayEntry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.transparent,
        child: AttachmentFloatingCard(
          attachmentType: attachmentType,
          onDismiss: _removeOverlay,
          onAttachmentSelected: (attachment) {
            setState(() {
              _attachments.add(attachment);
              if (attachment.type == 'paste' &&
                  attachment.textContent != null) {
                _contentController.text += '\n\n${attachment.textContent!}';
              } else if (attachment.type == 'link' &&
                  attachment.textContent != null) {
                final parts = attachment.textContent!.split('|');
                final title = parts.isNotEmpty ? parts[0] : 'Link';
                final url = parts.length > 1 ? parts[1] : '';
                _contentController.text += '\n\n[$title]($url)';
              }
            });
          },
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  Future<void> _uploadImage(
    ImageSource source, {
    bool allowMultiple = false,
  }) async {
    setState(() {
      _isUploadingImage = true;
      _errorMessage = null;
    });

    try {
      List<XFile>? pickedImages;
      if (allowMultiple) {
        pickedImages = await ImagePicker().pickMultiImage();
      } else {
        final pickedImage = await ImagePicker().pickImage(source: source);
        if (pickedImage != null) {
          pickedImages = [pickedImage];
        }
      }

      if (pickedImages != null && pickedImages.isNotEmpty) {
        List<AttachmentData> newAttachments = [];
        List<String> imageUrls = [];

        for (var image in pickedImages) {
          Uint8List imageBytes = await image.readAsBytes();

          // Check if it's HEIC and convert to PNG
          if (ImageConverterService.isHeicFormat(imageBytes)) {
            final convertedBytes = await ImageConverterService.convertHeicToPng(
              imageBytes,
            );
            if (convertedBytes != null) {
              imageBytes = convertedBytes;
            }
          }

          final result = await _apiService.uploadGenericFile(
            fileBytes: imageBytes,
            fileName: "post_image_${DateTime.now().millisecondsSinceEpoch}.png",
            userId: widget.userId,
          );

          if (result.isSuccess && result.data != null) {
            final imageUrl = result.data as String;
            imageUrls.add(imageUrl);

            final attachment = AttachmentData(
              type: 'image',
              fileName: 'image.png',
              fileBytes: imageBytes,
              url: imageUrl,
            );
            newAttachments.add(attachment);
          } else {
            setState(() {
              _errorMessage = result.error ?? 'Failed to upload image';
            });
            break;
          }
        }

        if (imageUrls.isNotEmpty) {
          setState(() {
            _attachments.addAll(newAttachments);
            _attachedFileUrls = imageUrls;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Images uploaded successfully!'),
              backgroundColor: context.success,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to upload image. Please try again.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage!), backgroundColor: context.error),
      );
    } finally {
      setState(() {
        _isUploadingImage = false;
      });
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
      _attachedFileUrls.removeAt(index);
    });
  }

  Future<void> _createPost() async {
    if (_titleController.text.trim().isEmpty &&
        _contentController.text.trim().isEmpty &&
        _attachments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please add a title, content, or attachment to your post',
          ),
          backgroundColor: context.accentPrimary,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Determine post type based on content
      String postType = 'text';
      final mediaAttachment = _attachments.where(
        (a) => a.type == 'image' || a.type == 'pdf',
      );
      if (mediaAttachment.isNotEmpty) {
        // Only image/pdf attachments map to a DB post_type (they have a file_url);
        // link/paste attachments are folded into content as text instead.
        postType = mediaAttachment.first.type;
      } else if (_titleController.text.trim().isNotEmpty) {
        // If there's a title, it's a text post
        postType = 'text';
      } else if (_contentController.text.trim().isNotEmpty) {
        // If there's only content, it's a message
        postType = 'message';
      }

      // Prepare file URL - convert list to single string if needed
      String? fileUrl;
      if (_attachedFileUrls.isNotEmpty) {
        fileUrl = _attachedFileUrls.length == 1
            ? _attachedFileUrls.first
            : _attachedFileUrls.join(',');
      }

      // Use the same SendMessageEvent that works for chat bubble
      context.read<ChatBloc>().add(
        SendMessageEvent(
          organizationId: widget.organizationId,
          userId: widget.userId,
          title: _titleController.text.trim().isEmpty
              ? null
              : _titleController.text.trim(),
          content: _contentController.text.trim().isEmpty
              ? ''
              : _contentController.text.trim(),
          postType: postType,
          fileUrl: fileUrl,
        ),
      );

      // Show success message
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
        _attachments.clear();
        _attachedFileUrls.clear();
      });

      await _animateOut();

      // Call the callback if provided
      if (widget.onPostCreated != null) {
        widget.onPostCreated!();
      }

      // Return true to indicate successful creation
      Navigator.pop(context, true);
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

  Future<void> _animateOut() async {
    await Future.wait([_slideController.reverse(), _fadeController.reverse()]);
  }

  Future<bool> _onWillPop() async {
    _removeOverlay();
    await _animateOut();
    return true;
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
            _buildAttachmentOption(Icons.photo_library, 'Insert Photos', () {
              Navigator.pop(context);
              _showAttachmentCard('image');
            }),
            _buildAttachmentOption(Icons.picture_as_pdf, 'Attach PDF', () {
              Navigator.pop(context);
              _showAttachmentCard('pdf');
            }),
            _buildAttachmentOption(Icons.link, 'Add Link', () {
              Navigator.pop(context);
              _showAttachmentCard('link');
            }),
            _buildAttachmentOption(Icons.content_paste, 'Paste', () {
              Navigator.pop(context);
              _showAttachmentCard('paste');
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
    bool isHero = false,
  }) {
    Widget textField = TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines ?? 1,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.sentences,
      onTap: () async {
        // Check for image in clipboard when field is tapped
        await _checkClipboardForImage();
      },
      contextMenuBuilder: (BuildContext menuContext, EditableTextState editableTextState) {
        return AdaptiveTextSelectionToolbar(
          anchors: editableTextState.contextMenuAnchors,
          children: [
            // Paste option - handles both images and text
            TextSelectionToolbarTextButton(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: const Text('Paste'),
              onPressed: () async {
                // Close context menu first - use menu context only for closing
                try {
                  if (Navigator.of(
                    menuContext,
                    rootNavigator: false,
                  ).canPop()) {
                    Navigator.of(menuContext, rootNavigator: false).pop();
                  }
                } catch (e) {
                  // If pop fails, just continue - menu might already be closed
                  print("📋 Note: Could not close context menu: $e");
                }

                // Use a small delay to ensure context menu is closed
                await Future.delayed(const Duration(milliseconds: 150));

                if (!mounted) return;

                // Set loading state
                if (mounted) {
                  setState(() {
                    _isUploadingImage = true;
                    _errorMessage = null;
                  });
                }

                try {
                  // Check for image first
                  Uint8List? imageBytes = await ClipboadImage.getImage();
                  if (imageBytes != null && mounted) {
                    print(
                      "📋 Found image in clipboard via context menu (${imageBytes.length} bytes)",
                    );
                    await _processImageBytes(imageBytes);
                    return;
                  }

                  if (!mounted) return;

                  // Check for base64 image in text clipboard
                  final clipboardData = await Clipboard.getData(
                    Clipboard.kTextPlain,
                  );
                  if (clipboardData?.text != null && mounted) {
                    final text = clipboardData!.text!;

                    // Check if it's a base64 image
                    if (text.startsWith('data:image/')) {
                      print(
                        "📋 Found base64 image in clipboard via context menu",
                      );
                      await _processBase64Image(text);
                      return;
                    }

                    // Regular text paste - paste directly into the field
                    if (mounted) {
                      final newValue = controller.value.copyWith(
                        text: controller.text.replaceRange(
                          controller.selection.start,
                          controller.selection.end,
                          text,
                        ),
                        selection: TextSelection.collapsed(
                          offset: controller.selection.start + text.length,
                        ),
                      );
                      controller.value = newValue;
                    }
                  } else if (mounted) {
                    // No content found - use widget's context
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: const Text('No content found in clipboard'),
                        backgroundColor: this.context.accentPrimary,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                } catch (e) {
                  print("📋 Error pasting from context menu: $e");
                  if (mounted) {
                    setState(() {
                      _isUploadingImage = false;
                      _errorMessage = 'Failed to paste: ${e.toString()}';
                    });
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to paste: ${e.toString()}'),
                        backgroundColor: this.context.error,
                      ),
                    );
                  }
                } finally {
                  if (mounted) {
                    setState(() {
                      _isUploadingImage = false;
                    });
                  }
                }
              },
            ),
            // Copy option
            if (controller.selection.isValid &&
                !controller.selection.isCollapsed)
              TextSelectionToolbarTextButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: const Text('Copy'),
                onPressed: () {
                  final selectedText = controller.text.substring(
                    controller.selection.start,
                    controller.selection.end,
                  );
                  Clipboard.setData(ClipboardData(text: selectedText));
                  try {
                    if (Navigator.of(
                      menuContext,
                      rootNavigator: false,
                    ).canPop()) {
                      Navigator.of(menuContext, rootNavigator: false).pop();
                    }
                  } catch (e) {
                    // Menu might already be closed
                  }
                },
              ),
            // Cut option
            if (controller.selection.isValid &&
                !controller.selection.isCollapsed)
              TextSelectionToolbarTextButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: const Text('Cut'),
                onPressed: () {
                  final selectedText = controller.text.substring(
                    controller.selection.start,
                    controller.selection.end,
                  );
                  Clipboard.setData(ClipboardData(text: selectedText));
                  final newValue = controller.value.copyWith(
                    text: controller.text.replaceRange(
                      controller.selection.start,
                      controller.selection.end,
                      '',
                    ),
                    selection: TextSelection.collapsed(
                      offset: controller.selection.start,
                    ),
                  );
                  controller.value = newValue;
                  try {
                    if (Navigator.of(
                      menuContext,
                      rootNavigator: false,
                    ).canPop()) {
                      Navigator.of(menuContext, rootNavigator: false).pop();
                    }
                  } catch (e) {
                    // Menu might already be closed
                  }
                },
              ),
            // Select All option
            if (controller.text.isNotEmpty)
              TextSelectionToolbarTextButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: const Text('Select All'),
                onPressed: () {
                  controller.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: controller.text.length,
                  );
                  try {
                    if (Navigator.of(
                      menuContext,
                      rootNavigator: false,
                    ).canPop()) {
                      Navigator.of(menuContext, rootNavigator: false).pop();
                    }
                  } catch (e) {
                    // Menu might already be closed
                  }
                },
              ),
          ],
        );
      },
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
          borderRadius: BorderRadius.circular(isHero ? 24 : 10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(isHero ? 24 : 10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(isHero ? 24 : 10),
          borderSide: BorderSide(color: context.accentPrimary, width: 1),
        ),
        suffixIcon: maxLines != null && maxLines > 1
            ? IconButton(
                icon: Icon(
                  Icons.content_paste,
                  color: context.darkTextSecondary,
                  size: 20,
                ),
                onPressed: _handleImagePaste,
                tooltip: 'Paste image',
              )
            : null,
      ),
      style: context.darkFieldText,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isHero) ...[
          Text(label, style: context.darkFieldLabel),
          const SizedBox(height: 8),
        ],
        if (isHero)
          Hero(
            tag: 'message-input-hero',
            child: Material(color: Colors.transparent, child: textField),
          )
        else
          textField,
      ],
    );
  }

  Future<void> _checkClipboardForImage() async {
    try {
      // Check if clipboard has image data (iOS/Android)
      Uint8List? imageBytes = await ClipboadImage.getImage();
      if (imageBytes != null) {
        // Show a subtle hint that an image can be pasted
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Tap the paste icon to paste the image'),
              backgroundColor: context.accentPrimary,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Also check for base64 images in text clipboard
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text != null) {
        final text = clipboardData!.text!;

        // Check if it's an image (base64 or URL)
        if (text.startsWith('data:image/')) {
          // Show a subtle hint that an image can be pasted
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Tap the paste icon to paste the image'),
                backgroundColor: context.accentPrimary,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      // Silently handle errors when checking clipboard
    }
  }

  Future<void> _handleImagePaste() async {
    print("📋 _handleImagePaste called");

    setState(() {
      _isUploadingImage = true;
      _errorMessage = null;
    });

    try {
      // First, try to get image from clipboard using clipboad_image (iOS/Android)
      Uint8List? imageBytes = await ClipboadImage.getImage();
      if (imageBytes != null) {
        print(
          "📋 Found image in clipboard via pasteboard (${imageBytes.length} bytes)",
        );
        await _processImageBytes(imageBytes);
        return;
      }

      // Try to get text from clipboard (for base64 images)
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text != null) {
        final preview = clipboardData!.text!.length > 50
            ? clipboardData.text!.substring(0, 50)
            : clipboardData.text!;
        print("📋 Clipboard text data: $preview...");
      }

      if (clipboardData?.text != null) {
        final text = clipboardData!.text!;

        // Check if it's a base64 image
        if (text.startsWith('data:image/')) {
          print("📋 Found base64 image in clipboard");
          await _processBase64Image(text);
          return;
        }
      }

      // No image found
      print("📋 No image found in clipboard");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No image found in clipboard. Try copying an image first.',
            ),
            backgroundColor: context.accentPrimary,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print("📋 Error in _handleImagePaste: $e");
      setState(() {
        _errorMessage = 'Failed to paste image. Please try again.';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage!),
            backgroundColor: context.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  Future<void> _processImageBytes(Uint8List imageBytes) async {
    try {
      print("📋 Processing image bytes (${imageBytes.length} bytes)");

      // Check if it's HEIC and convert to PNG
      Uint8List processedBytes = imageBytes;
      if (ImageConverterService.isHeicFormat(imageBytes)) {
        final convertedBytes = await ImageConverterService.convertHeicToPng(
          imageBytes,
        );
        if (convertedBytes != null) {
          processedBytes = convertedBytes;
          print("📋 Converted HEIC to PNG");
        }
      }

      // Upload the image
      final result = await _apiService.uploadGenericFile(
        fileBytes: processedBytes,
        fileName:
            "post_image_pasted_${DateTime.now().millisecondsSinceEpoch}.png",
        userId: widget.userId,
      );

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        final imageUrl = result.data as String;
        print("📋 Image uploaded successfully: $imageUrl");

        final attachment = AttachmentData(
          type: 'image',
          fileName: 'pasted_image.png',
          fileBytes: processedBytes,
          url: imageUrl,
        );

        if (mounted) {
          setState(() {
            _attachments.add(attachment);
            _attachedFileUrls.add(imageUrl);
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Image pasted successfully!'),
              backgroundColor: context.success,
            ),
          );
        }
      } else {
        throw Exception(result.error ?? 'Failed to upload image');
      }
    } catch (e) {
      print("📋 Error processing image bytes: $e");
      if (mounted) {
        rethrow;
      }
    }
  }

  Future<void> _processBase64Image(String base64Data) async {
    try {
      print("📋 Processing base64 image");

      // Extract the base64 data
      final commaIndex = base64Data.indexOf(',');
      if (commaIndex == -1) {
        throw Exception('Invalid base64 image format');
      }

      final base64String = base64Data.substring(commaIndex + 1);
      final imageBytes = base64Decode(base64String);

      print("📋 Decoded ${imageBytes.length} bytes");

      // Use the shared image processing method
      await _processImageBytes(Uint8List.fromList(imageBytes));
    } catch (e) {
      print("📋 Error processing base64 image: $e");
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        // Detect Ctrl+V (Windows/Linux) or Cmd+V (macOS)
        if (event is KeyDownEvent) {
          final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
          final isCmdPressed = HardwareKeyboard.instance.isMetaPressed;
          final isVPressed = event.logicalKey == LogicalKeyboardKey.keyV;

          if ((isCtrlPressed || isCmdPressed) && isVPressed) {
            print(
              "📋 Keyboard shortcut detected: ${isCmdPressed ? 'Cmd' : 'Ctrl'}+V",
            );
            _handleImagePaste();
          }
        }
      },
      child: PopScope(
        onPopInvoked: (bool didPop) async {
          if (!didPop) {
            await _onWillPop();
          }
        },
        child: Scaffold(
          backgroundColor: context.darkBackground,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            backgroundColor: context.darkBackground,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: context.darkText),
              onPressed: () async {
                await _animateOut();
                Navigator.pop(context);
              },
            ),
            title: FadeTransition(
              opacity: _fadeAnimation,
              child: Text('Create Post', style: context.darkAppBarTitle),
            ),
          ),
          body: Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(30.0),
                    child: AnimatedBuilder(
                      animation: _slideAnimation,
                      builder: (context, child) {
                        return SlideTransition(
                          position: _slideAnimation,
                          child: ScaleTransition(
                            scale: _scaleAnimation,
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 20),
                                  _buildCustomTextField(
                                    'TITLE',
                                    'What\'s this about?',
                                    _titleFocusNode,
                                    _titleController,
                                  ),
                                  const SizedBox(height: 24),
                                  _buildCustomTextField(
                                    'CONTENT',
                                    'Share your thoughts...',
                                    _contentFocusNode,
                                    _contentController,
                                    maxLines: 8,
                                    keyboardType: TextInputType.multiline,
                                    isHero: false,
                                  ),
                                  const SizedBox(height: 20),
                                  if (_attachments.isNotEmpty) ...[
                                    Column(
                                      children: _attachments
                                          .asMap()
                                          .entries
                                          .map((entry) {
                                            final index = entry.key;
                                            final attachment = entry.value;
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 8.0,
                                              ),
                                              child: AttachmentPreview(
                                                attachment: attachment,
                                                onRemove: () =>
                                                    _removeAttachment(index),
                                              ),
                                            );
                                          })
                                          .toList(),
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                  if (_isUploadingImage) ...[
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: context.accentPrimary
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: context.accentPrimary
                                              .withOpacity(0.3),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            'Loading...',
                                            style: context.darkAttachmentOption,
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
                        );
                      },
                    ),
                  ),
                ),
                SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: const Offset(0, 1),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: _slideController,
                          curve: const Interval(
                            0.3,
                            1.0,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                      ),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: context.darkBottomBarBackground,
                      border: Border(
                        top: BorderSide(color: context.darkBorder, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
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
                                : Icon(
                                    Icons.send,
                                    color: context.darkText,
                                    size: 24,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _uploadPdf() async {
    print("📁 Starting PDF upload...");
    setState(() {
      _isUploadingImage = true; // Reuse the loading state
      _errorMessage = null;
    });

    try {
      print("📁 Opening file picker...");
      // Use file_picker to select PDF
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
        withData: true,
      );

      print("📁 File chosen: ${result?.files}");

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final fileBytes = file.bytes;
        final fileName = file.name;

        print("📁 bytes: ${file.bytes}");

        if (fileBytes != null) {
          print("📁 File not empty, uploading...");
          // Upload the PDF file
          final uploadResult = await _apiService.uploadGenericFile(
            fileBytes: fileBytes,
            fileName:
                "post_pdf_${DateTime.now().millisecondsSinceEpoch}_$fileName",
            userId: widget.userId,
          );
          print("📁 Upload completed");

          if (uploadResult.isSuccess && uploadResult.data != null) {
            final pdfUrl = uploadResult.data as String;
            print("📁 Upload success!");

            // Create attachment data
            final attachment = AttachmentData(
              type: 'pdf',
              fileName: fileName,
              fileBytes: fileBytes,
              url: pdfUrl,
            );

            setState(() {
              _attachments.add(attachment);
              _attachedFileUrls.add(pdfUrl);
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('PDF uploaded successfully!'),
                backgroundColor: context.success,
              ),
            );
          } else {
            print("📁 Upload fail due to ${uploadResult.error}");
            setState(() {
              _errorMessage = uploadResult.error ?? 'Failed to upload PDF';
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_errorMessage!),
                backgroundColor: context.error,
              ),
            );
          }
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to upload PDF. Please try again.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage!), backgroundColor: context.error),
      );
    } finally {
      setState(() {
        _isUploadingImage = false; // Reset loading state
      });
    }
  }
}
