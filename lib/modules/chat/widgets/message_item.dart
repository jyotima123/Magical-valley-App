// lib/modules/chat/widgets/message_item.dart
import 'dart:convert' show jsonDecode;
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/chat/models/chat_message.dart';
import 'package:mvc_app/modules/chat/models/post_reactions_model.dart';
import 'package:mvc_app/modules/chat/widgets/image_carousel_screen.dart';
import 'package:mvc_app/modules/chat/widgets/message_context_menu.dart';
import 'package:mvc_app/modules/chat/widgets/message_reactions_widget.dart';
import 'package:mvc_app/modules/chat/widgets/emoji_picker_screen.dart';
import 'package:mvc_app/modules/chat/widgets/fullscreen_reaction_overlay.dart';
import 'package:mvc_app/modules/chat/widgets/message_snapshot.dart';
import 'package:mvc_app/modules/chat/chat_bloc.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class MessageItem extends StatefulWidget {
  final ChatMessage message;
  final String currentUserId;
  final AppThemeMode theme;
  final bool isPinned;
  final bool isAdmin;
  final UserRole currentUserRole;
  final UserRole messageAuthorRole;
  final String currentOrganizationId;
  final List<String> currentUserManagedOrganizations;
  final List<PostReaction> reactions;
  final Function(String messageId, bool shouldPin)? onPinToggle;
  final Function(String messageId)? onDeleteMessage;
  final Function(String messageId, String newContent)? onEditMessage;
  final Function(String messageId, List<String> emojis)? onReactionUpdate;
  final ApiRepository? apiRepository;

  const MessageItem({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.theme,
    this.isPinned = false,
    this.isAdmin = false,
    required this.currentUserRole,
    required this.messageAuthorRole,
    required this.currentOrganizationId,
    required this.currentUserManagedOrganizations,
    this.reactions = const [],
    this.onPinToggle,
    this.onDeleteMessage,
    this.onEditMessage,
    this.onReactionUpdate,
    this.apiRepository,
  });

  @override
  State<MessageItem> createState() => _MessageItemState();
}

class _MessageItemState extends State<MessageItem> {
  // GlobalKey for capturing message position for fullscreen overlay
  final GlobalKey _messageKey = GlobalKey();

  // Add a map to cache PDF file paths
  final Map<String, String> _pdfFilePaths = <String, String>{};

  // Cache parsed file URLs to avoid re-parsing on every build
  List<String>? _cachedFileUrls;

  // Cache emoji counts to avoid recalculating on every build
  Map<String, int>? _cachedEmojiCounts;

  // Maximum memory cache width for images (reduced for better performance)
  static const int _maxImageCacheWidth = 400;

  // Pre-computed flags to avoid expensive conditionals in build
  bool _showTitle = false;
  bool _showContent = false;
  bool _showFileCarousel = false;
  bool _showFilePlaceholder = false;
  String? _filePlaceholderText;

  // Edit functionality state
  bool _isEditing = false;
  final TextEditingController _editTitleController = TextEditingController();
  final TextEditingController _editContentController = TextEditingController();
  final FocusNode _editTitleFocusNode = FocusNode();
  final FocusNode _editContentFocusNode = FocusNode();
  bool _isUpdating = false;

  bool get _isDarkTheme => widget.theme == AppThemeMode.dark;
  bool get _isOwnMessage => widget.message.createdBy == widget.currentUserId;

  // Helper methods for permission checking
  bool get _canEdit => _canEditMessage();
  bool get _canDelete => _canDeleteMessage();
  bool get _canSeeAuthorName => _canSeeAuthorNameCheck();

  bool _canEditMessage() {
    // Superadmins can edit any message
    if (widget.currentUserRole.isSuperAdmin) return true;

    // Admins can edit posts in organizations they manage
    if (widget.currentUserRole.isAdmin) {
      return widget.currentUserManagedOrganizations.contains(
        widget.message.organizationId,
      );
    }

    // Regular users cannot edit any messages
    return false;
  }

  bool _canDeleteMessage() {
    // Superadmins can delete any message
    if (widget.currentUserRole.isSuperAdmin) return true;

    // Admins can delete posts in organizations they manage
    if (widget.currentUserRole.isAdmin) {
      return widget.currentUserManagedOrganizations.contains(
        widget.message.organizationId,
      );
    }

    // Regular users cannot delete any messages
    return false;
  }

  bool _canSeeAuthorNameCheck() {
    // Superadmins can see all author names
    if (widget.currentUserRole.isSuperAdmin) return true;

    // Admins can see author names only for messages in organizations they manage
    if (widget.currentUserRole.isAdmin) {
      return widget.currentUserManagedOrganizations.contains(
        widget.currentOrganizationId,
      );
    }

    // Regular users cannot see author names
    return false;
  }

  // Overlay for long press options
  OverlayEntry? _overlayEntry;

  // Helper method to calculate emoji counts (memoized)
  Map<String, int> _calculateEmojiCounts() {
    if (_cachedEmojiCounts != null) {
      return _cachedEmojiCounts!;
    }
    final Map<String, int> counts = {};
    for (final reaction in widget.reactions) {
      for (final emoji in reaction.emojiReactions) {
        counts[emoji] = (counts[emoji] ?? 0) + 1;
      }
    }
    _cachedEmojiCounts = counts;
    return counts;
  }

  @override
  void initState() {
    super.initState();
    _updateCachedData();
  }

  // Update all cached data and pre-computed flags
  void _updateCachedData() {
    // Pre-cache file URLs and emoji counts
    _cachedFileUrls = _parseFileUrls(widget.message.fileUrl);
    _cachedEmojiCounts = _calculateEmojiCounts();

    // Pre-compute all conditional flags
    _showTitle = widget.message.title?.isNotEmpty ?? false;
    _showContent = widget.message.content?.isNotEmpty ?? false;
    _showFileCarousel = _cachedFileUrls!.isNotEmpty;

    // Pre-compute file placeholder logic (the expensive conditional)
    _showFilePlaceholder =
        _cachedFileUrls!.isEmpty &&
        !_showTitle &&
        !_showContent &&
        ((widget.message.fileUrl != null &&
                widget.message.fileUrl!.isNotEmpty) ||
            widget.message.postType == 'image' ||
            widget.message.postType == 'pdf');

    _filePlaceholderText = _showFilePlaceholder
        ? (widget.message.postType == 'pdf' ? '[PDF]' : '[image]')
        : null;
  }

  @override
  void didUpdateWidget(MessageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only recalculate if message changed
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.fileUrl != widget.message.fileUrl ||
        oldWidget.message.title != widget.message.title ||
        oldWidget.message.content != widget.message.content ||
        oldWidget.message.postType != widget.message.postType) {
      _updateCachedData();
    }
    // Only recalculate emoji counts if reactions changed
    if (oldWidget.reactions.length != widget.reactions.length ||
        oldWidget.reactions != widget.reactions) {
      _cachedEmojiCounts = _calculateEmojiCounts();
    }
  }

  @override
  void dispose() {
    _editTitleController.dispose();
    _editContentController.dispose();
    _editTitleFocusNode.dispose();
    _editContentFocusNode.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  bool _isUrl(String text) {
    try {
      final uri = Uri.parse(text);
      return uri.isAbsolute && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  List<String> _extractUrls(String text) {
    final words = text.split(RegExp(r'\s+'));
    return words.where((word) => _isUrl(word)).toList();
  }

  // Helper method to check if URL is a PDF
  bool _isPdfUrl(String url) {
    return url.toLowerCase().endsWith('.pdf');
  }

  // Helper method to download PDF and cache it locally
  Future<String?> _downloadPdf(String url) async {
    try {
      // Check if already cached
      if (_pdfFilePaths.containsKey(url)) {
        return _pdfFilePaths[url];
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final dir = await getTemporaryDirectory();
        final fileName = url
            .split('/')
            .last
            .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);

        _pdfFilePaths[url] = file.path;
        return file.path;
      }
    } catch (e) {
      print('Error downloading PDF: $e');
    }
    return null;
  }

  // Helper method to parse file URLs from fileUrl field
  List<String> _parseFileUrls(dynamic fileUrl) {
    if (fileUrl == null) return [];

    if (fileUrl is String) {
      try {
        if (fileUrl.trim().startsWith('[') && fileUrl.trim().endsWith(']')) {
          final List<dynamic> jsonArray = jsonDecode(fileUrl);
          return jsonArray.map((url) => url.toString()).toList();
        }
        return [fileUrl];
      } catch (e) {
        print('Error parsing fileUrl JSON: $e');
        return [fileUrl];
      }
    }

    if (fileUrl is List) {
      return fileUrl.map((url) => url.toString()).toList();
    }

    return [];
  }

  // Helper method to open URL
  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not open link: $url')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error opening link: $e')));
      }
    }
  }

  // Helper method to build text with clickable links
  List<TextSpan> _buildTextSpansWithLinks(String text, bool isOwnMessage) {
    final urlRegex = RegExp(r'https?://[^\s]+', caseSensitive: false);
    List<TextSpan> spans = [];
    int lastEnd = 0;

    for (final match in urlRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastEnd, match.start),
            style: _getMessageTextStyle(),
          ),
        );
      }

      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: TextStyle(
            color: AppTheme.accentPrimary,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()..onTap = () => _launchUrl(url),
        ),
      );

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(
        TextSpan(text: text.substring(lastEnd), style: _getMessageTextStyle()),
      );
    }

    return spans;
  }

  TextStyle _getMessageTextStyle() {
    return _isDarkTheme
        ? AppTheme.darkFieldText.copyWith(fontSize: 14)
        : AppTheme.chatMessage;
  }

  Color _getBackgroundColor(bool isOwnMessage) {
    return _isDarkTheme
        ? AppTheme.darkCardBackground
        : AppTheme.messageBackground;
  }

  Color _getTimestampColor() {
    return _isDarkTheme
        ? AppTheme.darkTextSecondary
        : AppTheme.secondaryHeadingColor;
  }

  Color _getAuthorNameColor() {
    return _isDarkTheme ? AppTheme.darkText : AppTheme.black;
  }

  Widget _buildMessageContent(String content, bool isOwnMessage) {
    final urls = _extractUrls(content);
    if (urls.isNotEmpty) {
      return RichText(
        text: TextSpan(
          children: _buildTextSpansWithLinks(content, isOwnMessage),
        ),
      );
    }
    return Text(content, style: _getMessageTextStyle());
  }

  Widget _buildPdfPreview(String pdfUrl, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: FutureBuilder<String?>(
        future: _downloadPdf(pdfUrl),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingPlaceholder();
          }

          if (snapshot.hasError || snapshot.data == null) {
            return _buildErrorPlaceholder(pdfUrl);
          }

          return _buildPdfView(snapshot.data!);
        },
      ),
    );
  }

  Widget _buildLoadingPlaceholder() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: _isDarkTheme
            ? AppTheme.darkSurface
            : AppTheme.cardGreyBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentPrimary),
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder(String pdfUrl) {
    return GestureDetector(
      onTap: () => setState(() => _pdfFilePaths.remove(pdfUrl)),
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: _isDarkTheme ? AppTheme.darkSurface : AppTheme.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.refresh,
              size: 48,
              color: _isDarkTheme
                  ? AppTheme.darkTextSecondary
                  : AppTheme.secondaryHeadingColor,
            ),
            Text(
              'Tap to retry',
              style: TextStyle(
                color: _isDarkTheme
                    ? AppTheme.darkTextSecondary
                    : AppTheme.secondaryHeadingColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Error widget specifically for images with proper error icon
  Widget _buildImageErrorWidget() {
    return Container(
      decoration: BoxDecoration(
        color: _isDarkTheme
            ? AppTheme.darkSurface
            : AppTheme.cardGreyBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 48,
              color: _isDarkTheme
                  ? AppTheme.darkTextSecondary
                  : AppTheme.secondaryHeadingColor,
            ),
            const SizedBox(height: 8),
            Text(
              'Image not available',
              style: TextStyle(
                fontSize: 12,
                color: _isDarkTheme
                    ? AppTheme.darkTextSecondary
                    : AppTheme.secondaryHeadingColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfView(String filePath) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 200,
            width: MediaQuery.of(context).size.width * 0.85,
            color: _isDarkTheme ? AppTheme.darkSurface : Colors.white,
            child: PDFView(
              filePath: filePath,
              enableSwipe: false,
              autoSpacing: false,
              onError: (error) => print('PDF Error: $error'),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.picture_as_pdf, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text(
                  'PDF',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSingleImage(String imageUrl, {VoidCallback? onTap}) {
    // Fill width and let image maintain aspect ratio, cropping on largest axis if needed
    // BoxFit.cover will crop instead of squishing, preserving image quality
    final maxWidth = MediaQuery.of(context).size.width * 0.85;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: maxWidth,
          height:
              maxWidth, // Use square container - BoxFit.cover crops largest axis
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover, // Crop on largest axis instead of squishing
            placeholder: (context, url) => _buildLoadingPlaceholder(),
            errorWidget: (context, url, error) => _buildImageErrorWidget(),
            // Only constrain width for cache - don't set height to preserve aspect ratio
            memCacheWidth: _maxImageCacheWidth,
            // Don't set memCacheHeight - allows image to maintain natural aspect ratio
            maxWidthDiskCache: _maxImageCacheWidth,
            cacheKey: imageUrl,
            // Disable animations during scroll for better performance
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholderFadeInDuration: Duration.zero,
          ),
        ),
      ),
    );
  }

  void _openPdfFullscreen(String pdfUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfFullscreenView(pdfUrl: pdfUrl, theme: widget.theme),
        fullscreenDialog: true,
      ),
    );
  }

  Widget _buildFilePreview(String fileUrl, {VoidCallback? onTap}) {
    if (_isPdfUrl(fileUrl)) {
      return _buildPdfPreview(fileUrl, onTap: onTap);
    } else {
      return _buildSingleImage(fileUrl, onTap: onTap);
    }
  }

  Widget _buildFileCarousel(List<String> fileUrls) {
    if (fileUrls.isEmpty) return SizedBox.shrink();

    if (fileUrls.length == 1) {
      return _buildFilePreview(
        fileUrls.first,
        onTap: () {
          if (_isPdfUrl(fileUrls.first)) {
            _openPdfFullscreen(fileUrls.first);
          } else {
            _openImageCarousel(fileUrls, 0);
          }
        },
      );
    }

    return SizedBox(
      height: 200,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: fileUrls.length,
            itemBuilder: (context, index) {
              return _buildFilePreview(
                fileUrls[index],
                onTap: () {
                  if (_isPdfUrl(fileUrls[index])) {
                    _openPdfFullscreen(fileUrls[index]);
                  } else {
                    _openImageCarousel(fileUrls, index);
                  }
                },
              );
            },
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${fileUrls.length} file${fileUrls.length > 1 ? 's' : ''}',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openImageCarousel(List<String> imageUrls, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageCarouselScreen(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
          theme: widget.theme,
        ),
      ),
    );
  }

  Widget _buildUserAvatar(ChatMessage message) {
    final profileImageUrl = message.author?.profilePictureUrl;
    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: AppTheme.secondaryHeadingColor,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: profileImageUrl,
            width: 32,
            height: 32,
            fit: BoxFit.cover,
            placeholder: (context, url) => CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentPrimary),
            ),
            errorWidget: (context, url, error) => Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.secondaryHeadingColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  message.author?.fullName?[0].toUpperCase() ?? 'U',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            cacheKey: profileImageUrl,
            // Optimize avatar loading - small images, use small cache
            memCacheWidth: 64, // 2x for retina, but still small
            memCacheHeight: 64,
            maxWidthDiskCache: 64,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppTheme.secondaryHeadingColor,
      child: Text(message.author?.fullName?[0].toUpperCase() ?? 'U'),
    );
  }

  // Edit functionality methods
  Widget _buildEditTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required FocusNode focusNode,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: _isDarkTheme
                ? AppTheme.darkTextSecondary
                : AppTheme.secondaryHeadingColor,
          ),
        ),
        SizedBox(height: 4),
        TextField(
          controller: controller,
          focusNode: focusNode,
          maxLines: maxLines,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: _isDarkTheme
                ? AppTheme.darkFieldHint
                : TextStyle(color: AppTheme.secondaryHeadingColor),
            filled: true,
            fillColor: _isDarkTheme
                ? AppTheme.darkInputBackground
                : AppTheme.cardGreyBackground,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppTheme.accentPrimary, width: 1),
            ),
          ),
          style: _getMessageTextStyle(),
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _getBackgroundColor(_isOwnMessage),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentPrimary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message.title?.isNotEmpty == true) ...[
            _buildEditTextField(
              label: 'TITLE',
              hint: 'Enter title...',
              controller: _editTitleController,
              focusNode: _editTitleFocusNode,
            ),
            SizedBox(height: 12),
          ],
          _buildEditTextField(
            label: 'CONTENT',
            hint: 'Enter content...',
            controller: _editContentController,
            focusNode: _editContentFocusNode,
            maxLines: 3,
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isUpdating ? null : _cancelEditing,
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: _isDarkTheme
                        ? AppTheme.darkTextSecondary
                        : AppTheme.secondaryHeadingColor,
                  ),
                ),
              ),
              SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isUpdating ? null : _saveEdit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isUpdating
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Context menu handlers
  void _handleContextAction(MessageAction action) {
    switch (action) {
      case MessageAction.react:
        _handleReaction();
        break;
      case MessageAction.edit:
        _startEditing();
        break;
      case MessageAction.pin:
        _handlePin(true);
        break;
      case MessageAction.unpin:
        _handlePin(false);
        break;
      case MessageAction.delete:
        _handleDelete();
        break;
    }
  }

  void _handleReaction() {
    // Get current user's reactions to pre-select them
    final currentUserReaction = widget.reactions.firstWhere(
      (reaction) => reaction.userId == widget.currentUserId,
      orElse: () => PostReaction(
        id: '',
        postId: widget.message.id,
        userId: widget.currentUserId,
        emojiReactions: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmojiPickerScreen(
          theme: widget.theme,
          initialSelectedEmojis: currentUserReaction.emojiReactions,
          onEmojisSelected: (selectedEmojis) {
            if (selectedEmojis.isEmpty) {
              // Remove reaction if no emojis selected
              final chatBloc = BlocProvider.of<ChatBloc>(context);
              chatBloc.add(
                RemoveReactionEvent(
                  messageId: widget.message.id,
                  userId: widget.currentUserId,
                ),
              );
            } else {
              // Add/update reaction
              final chatBloc = BlocProvider.of<ChatBloc>(context);
              chatBloc.add(
                AddReactionEvent(
                  messageId: widget.message.id,
                  emojis: selectedEmojis,
                  userId: widget.currentUserId,
                ),
              );
            }
          },
        ),
        fullscreenDialog: true,
      ),
    );
  }

  void _startEditing() {
    print("Starting editing");
    if (!_canEdit) return;
    print("User can edit message");

    setState(() {
      _isEditing = true;
      _editTitleController.text = widget.message.title ?? '';
      _editContentController.text = widget.message.content ?? '';
    });

    // Focus after a short delay to ensure the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.message.title?.isNotEmpty == true) {
        _editTitleFocusNode.requestFocus();
      } else {
        _editContentFocusNode.requestFocus();
      }
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
    });
    _editTitleFocusNode.unfocus();
    _editContentFocusNode.unfocus();
  }

  Future<void> _saveEdit() async {
    final newTitle = _editTitleController.text.trim();
    final newContent = _editContentController.text.trim();

    if (newContent.isEmpty && newTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message cannot be empty'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check if anything actually changed
    final originalTitle = widget.message.title ?? '';
    final originalContent = widget.message.content ?? '';

    if (newTitle == originalTitle && newContent == originalContent) {
      _cancelEditing();
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      // Update via API if repository is available
      if (widget.apiRepository != null) {
        // Prepare the update data
        final updateData = <String, dynamic>{};

        if (newTitle != originalTitle) {
          updateData['title'] = newTitle.isEmpty ? null : newTitle;
        }

        if (newContent != originalContent) {
          updateData['content'] = newContent.isEmpty ? null : newContent;
        }

        // Add updated timestamp
        updateData['updated_at'] = DateTime.now().toIso8601String();

        final result = await widget.apiRepository!.update(
          'posts',
          widget.message.id,
          updateData,
        );

        if (!result.isSuccess) {
          throw Exception(result.error ?? 'Failed to update message');
        }
      }

      // Notify parent widget with the combined content (for backward compatibility)
      final combinedContent = [
        if (newTitle.isNotEmpty) newTitle,
        if (newContent.isNotEmpty) newContent,
      ].join('\n\n');

      widget.onEditMessage?.call(widget.message.id, combinedContent);

      setState(() {
        _isEditing = false;
        _isUpdating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Message updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _isUpdating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handlePin(bool shouldPin) {
    print("UI: Attempting to pin/unpin message $shouldPin");
    widget.onPinToggle?.call(widget.message.id, shouldPin);
  }

  void _handleDelete() {
    if (!_canDelete) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDarkTheme ? AppTheme.darkSurface : Colors.white,
        title: Text(
          'Delete Message',
          style: TextStyle(
            color: _isDarkTheme ? AppTheme.darkText : Colors.black,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this message? This action cannot be undone.',
          style: TextStyle(
            color: _isDarkTheme
                ? AppTheme.darkTextSecondary
                : AppTheme.secondaryHeadingColor,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: _isDarkTheme
                    ? AppTheme.darkTextSecondary
                    : AppTheme.secondaryHeadingColor,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmDelete();
            },
            child: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    try {
      // Delete via API if repository is available
      if (widget.apiRepository != null) {
        final result = await widget.apiRepository!.delete(
          'posts',
          widget.message.id,
        );

        if (!result.isSuccess) {
          throw Exception(result.error ?? 'Failed to delete message');
        }
      }

      // Notify parent widget
      widget.onDeleteMessage?.call(widget.message.id);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message deleted'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwnMessage = widget.message.createdBy == widget.currentUserId;
    // Use cached file URLs - already computed in initState/didUpdateWidget
    final fileUrls = _cachedFileUrls!;

    return GestureDetector(
      // Use behavior: HitTestBehavior.opaque to prevent interference with scrolling
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (details) {
        _showContextMenu(details.globalPosition);
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: _isEditing
            ? _buildEditForm()
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isOwnMessage) ...[
                    _buildUserAvatar(widget.message),
                    SizedBox(width: 8),
                  ],
                  // Message balloon with GlobalKey for position capture
                  Expanded(
                    child: Stack(
                      clipBehavior: Clip.none, // Allow overflow for reactions
                      children: [
                        Container(
                          key: _messageKey,
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.9,
                          ),
                          decoration: BoxDecoration(
                            color: _getBackgroundColor(isOwnMessage),
                            borderRadius: BorderRadius.circular(12),
                            border: isOwnMessage
                                ? Border(
                                    left: BorderSide(
                                      color: AppTheme.accentPrimary,
                                      width: 2,
                                    ),
                                  )
                                : widget.isPinned
                                ? Border.all(
                                    color: AppTheme.secondaryHeadingColor,
                                    width: 0,
                                  )
                                : null,
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header row with author name and pin button
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (isOwnMessage) ...[
                                            Text(
                                              'You',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.accentPrimary,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                          ],
                                          if (!isOwnMessage &&
                                              widget.message.author != null &&
                                              _canSeeAuthorName) ...[
                                            Text(
                                              widget.message.author!.fullName ??
                                                  'Unknown User',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: _getAuthorNameColor(),
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                // Use pre-computed flags instead of conditionals
                                if (_showTitle) ...[
                                  Text(
                                    widget.message.title!,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _getAuthorNameColor(),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                ],
                                if (_showContent) ...[
                                  _buildMessageContent(
                                    widget.message.content!,
                                    isOwnMessage,
                                  ),
                                  SizedBox(height: 8),
                                ],
                                if (_showFileCarousel)
                                  _buildFileCarousel(fileUrls),

                                // Use pre-computed flag instead of expensive conditional
                                if (_showFilePlaceholder) ...[
                                  Text(
                                    _filePlaceholderText!,
                                    style: _getMessageTextStyle(),
                                  ),
                                  SizedBox(height: 8),
                                ],

                                SizedBox(height: 4),
                                Text(
                                  widget.message.timeDisplay,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: _getTimestampColor(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // WhatsApp-style reactions overlay
                        Positioned(
                          bottom: -8, // Position below the message bubble
                          right: 8, // Align to the right
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            // decoration: BoxDecoration(
                            //   color: Colors.white.withOpacity(
                            //     0.9,
                            //   ), // Semi-transparent white
                            //   borderRadius: BorderRadius.circular(12),
                            //   boxShadow: [
                            //     BoxShadow(
                            //       color: Colors.black.withOpacity(0.1),
                            //       blurRadius: 4,
                            //       offset: Offset(0, 2),
                            //     ),
                            //   ],
                            // ),
                            child: // Reactions widget
                            (widget.reactions.isNotEmpty)
                                ? MessageReactionsWidget(
                                    messageId: widget.message.id,
                                    theme: widget.theme,
                                    isAdmin: widget.isAdmin,
                                    reactions: widget.reactions,
                                    emojiCounts:
                                        _cachedEmojiCounts ??
                                        _calculateEmojiCounts(),
                                    currentUserId: widget.currentUserId,
                                    onReactionTap: widget.onReactionUpdate,
                                  )
                                : Container(),

                            // child: Row(
                            //   mainAxisSize: MainAxisSize.min,
                            //   children: [
                            //     Text("✅", style: TextStyle(fontSize: 14)),
                            //     // Add more emojis if needed
                            //     // Text(
                            //     //   "❤️",
                            //     //   style: TextStyle(fontSize: 14),
                            //     // ),
                            //     // SizedBox(width: 2),
                            //     // Text(
                            //     //   "😂",
                            //     //   style: TextStyle(fontSize: 14),
                            //     // ),
                            //   ],
                            // ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isOwnMessage) SizedBox(width: 8),
                ],
              ),
      ),
    );
  }

  void _handleEmojiReaction(String emoji) {
    // Convert emoji to emoji name for the API
    final emojiMap = {
      '❤️': 'heart',
      '👍': 'thumbsup',
      '😂': 'laugh',
      '👏': 'claps',
    };

    final emojiName = emojiMap[emoji] ?? emoji;

    // Check if user already has this reaction
    final currentUserReaction = widget.reactions.firstWhere(
      (reaction) => reaction.userId == widget.currentUserId,
      orElse: () => PostReaction(
        id: '',
        postId: widget.message.id,
        userId: widget.currentUserId,
        emojiReactions: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final chatBloc = BlocProvider.of<ChatBloc>(context);

    if (currentUserReaction.emojiReactions.contains(emojiName)) {
      // Remove reaction if already exists
      chatBloc.add(
        RemoveReactionEvent(
          messageId: widget.message.id,
          userId: widget.currentUserId,
        ),
      );
    } else {
      // Add/update reaction
      final newReactions = [emojiName];
      chatBloc.add(
        AddReactionEvent(
          messageId: widget.message.id,
          emojis: newReactions,
          userId: widget.currentUserId,
        ),
      );
    }
  }

  void _showContextMenu(Offset globalPosition) {
    // Deprecated: Use _showFullscreenReaction instead
    print('📱 _showContextMenu called at $globalPosition');
    _showFullscreenReaction();
  }

  void _showFullscreenReaction() {
    print('📱 _showFullscreenReaction called for message: ${widget.message.id}');

    // Get the message position using the GlobalKey
    final messageRect = _messageKey.globalPaintBounds;
    if (messageRect == null) {
      print('🔴 messageRect is null - GlobalKey not properly attached');
      return;
    }

    print('🟢 messageRect: $messageRect');

    // Get current user's reactions
    final currentUserReaction = widget.reactions.firstWhere(
      (reaction) => reaction.userId == widget.currentUserId,
      orElse: () => PostReaction(
        id: '',
        postId: widget.message.id,
        userId: widget.currentUserId,
        emojiReactions: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // Build the message content snapshot
    final messageContent = _buildMessageBalloonContent();

    // Create the overlay data
    final overlayData = FullscreenReactionData(
      messageRect: messageRect,
      messageContent: messageContent,
      isPinned: widget.isPinned,
      isOwnMessage: _isOwnMessage,
      currentUserRole: widget.currentUserRole,
      messageAuthorRole: widget.messageAuthorRole,
      messageOrganizationId: widget.message.organizationId,
      currentUserManagedOrganizations: widget.currentUserManagedOrganizations,
      currentUserId: widget.currentUserId,
      currentUserReactions: currentUserReaction.emojiReactions,
    );

    // Show the fullscreen overlay
    showFullscreenReactionOverlay(
      context: context,
      data: overlayData,
      theme: widget.theme,
      onEmojiSelected: (emoji) {
        if (emoji == 'more') {
          // Handle "more emojis" action - open full emoji picker
          _handleReaction();
        } else {
          _handleEmojiReaction(emoji);
        }
      },
      onActionSelected: (action) {
        switch (action) {
          case OverlayAction.edit:
            _startEditing();
            break;
          case OverlayAction.pin:
            _handlePin(true);
            break;
          case OverlayAction.unpin:
            _handlePin(false);
            break;
          case OverlayAction.delete:
            _handleDelete();
            break;
        }
      },
      onDismiss: () {
        // Overlay dismissed
      },
    );
  }

  /// Builds the message balloon content widget for the snapshot
  Widget _buildMessageBalloonContent() {
    final isOwnMessage = widget.message.createdBy == widget.currentUserId;
    final fileUrls = _cachedFileUrls!;

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.9,
      ),
      decoration: BoxDecoration(
        color: _getBackgroundColor(isOwnMessage),
        borderRadius: BorderRadius.circular(12),
        border: isOwnMessage
            ? Border(
                left: BorderSide(
                  color: AppTheme.accentPrimary,
                  width: 2,
                ),
              )
            : widget.isPinned
            ? Border.all(
                color: AppTheme.secondaryHeadingColor,
                width: 0,
              )
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row with author name
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isOwnMessage) ...[
                        Text(
                          'You',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accentPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                      ],
                      if (!isOwnMessage &&
                          widget.message.author != null &&
                          _canSeeAuthorName) ...[
                        Text(
                          widget.message.author!.fullName ?? 'Unknown User',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _getAuthorNameColor(),
                          ),
                        ),
                        SizedBox(height: 2),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (_showTitle) ...[
              Text(
                widget.message.title!,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _getAuthorNameColor(),
                ),
              ),
              SizedBox(height: 4),
            ],
            if (_showContent) ...[
              _buildMessageContent(
                widget.message.content!,
                isOwnMessage,
              ),
              SizedBox(height: 8),
            ],
            if (_showFileCarousel) _buildFileCarousel(fileUrls),
            if (_showFilePlaceholder) ...[
              Text(
                _filePlaceholderText!,
                style: _getMessageTextStyle(),
              ),
              SizedBox(height: 8),
            ],
            SizedBox(height: 4),
            Text(
              widget.message.timeDisplay,
              style: TextStyle(
                fontSize: 10,
                color: _getTimestampColor(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PdfFullscreenView extends StatefulWidget {
  final String pdfUrl;
  final AppThemeMode theme;

  const PdfFullscreenView({
    super.key,
    required this.pdfUrl,
    required this.theme,
  });

  @override
  _PdfFullscreenViewState createState() => _PdfFullscreenViewState();
}

class _PdfFullscreenViewState extends State<PdfFullscreenView> {
  String? _pdfPath;
  bool _isLoading = true;
  String? _error;

  bool get _isDarkTheme => widget.theme == AppThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final response = await http.get(Uri.parse(widget.pdfUrl));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${widget.pdfUrl.split('/').last}');
        await file.writeAsBytes(bytes);
        setState(() {
          _pdfPath = file.path;
          _isLoading = false;
        });
      } else {
        setState(() => _error = 'Failed to load PDF');
      }
    } catch (e) {
      setState(() => _error = 'Error loading PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _isDarkTheme
            ? AppTheme.darkCardBackground
            : Colors.white,
        leading: IconButton(
          icon: Icon(
            Icons.close,
            color: _isDarkTheme ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'PDF Details',
          style: TextStyle(color: _isDarkTheme ? Colors.white : Colors.black),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : PDFView(
              filePath: _pdfPath!,
              enableSwipe: true,
              swipeHorizontal: false,
              autoSpacing: false,
              onError: (error) => print('PDF Error: $error'),
            ),
    );
  }
}
