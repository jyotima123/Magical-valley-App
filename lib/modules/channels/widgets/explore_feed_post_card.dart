// lib/modules/channels/widgets/explore_feed_post_card.dart

import 'dart:convert' show jsonDecode;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/main_scaffold.dart';
import 'package:mvc_app/modules/channels/explore_feed_bloc.dart';
import 'package:mvc_app/modules/channels/models/explore_feed_item.dart';
import 'package:mvc_app/modules/channels/organization_profile_screen.dart';
import 'package:mvc_app/modules/chat/models/post_reactions_model.dart';
import 'package:mvc_app/modules/chat/widgets/emoji_picker_screen.dart';
import 'package:mvc_app/modules/chat/widgets/fullscreen_reaction_overlay.dart';
import 'package:mvc_app/modules/chat/widgets/image_carousel_screen.dart';
import 'package:mvc_app/modules/chat/widgets/message_reactions_widget.dart';
import 'package:mvc_app/modules/chat/widgets/message_snapshot.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/notification_preferences_service.dart';
import 'package:mvc_app/utils/profile_utils.dart';

class ExploreFeedPostCard extends StatefulWidget {
  final ExploreFeedItem feedItem;
  final VoidCallback? onFollowChanged;
  final String currentUserId;
  final UserRole currentUserRole;
  final List<String> currentUserManagedOrganizations;
  final List<PostReaction> reactions;

  const ExploreFeedPostCard({
    super.key,
    required this.feedItem,
    this.onFollowChanged,
    required this.currentUserId,
    required this.currentUserRole,
    required this.currentUserManagedOrganizations,
    this.reactions = const [],
  });

  @override
  State<ExploreFeedPostCard> createState() => _ExploreFeedPostCardState();
}

class _ExploreFeedPostCardState extends State<ExploreFeedPostCard> {
  final GlobalKey _cardKey = GlobalKey();

  // Edit state
  bool _isEditing = false;
  bool _isUpdating = false;
  late TextEditingController _editTitleController;
  late TextEditingController _editContentController;

  // Permission checks (same rules as chat screen)
  bool get _canEdit {
    if (widget.currentUserRole.isSuperAdmin) return true;
    if (widget.currentUserRole.isAdmin) {
      return widget.currentUserManagedOrganizations
          .contains(widget.feedItem.post.organizationId);
    }
    return false;
  }

  bool get _canDelete {
    if (widget.currentUserRole.isSuperAdmin) return true;
    if (widget.currentUserRole.isAdmin) {
      return widget.currentUserManagedOrganizations
          .contains(widget.feedItem.post.organizationId);
    }
    return false;
  }

  bool get _isAdmin =>
      widget.currentUserRole.isAdmin || widget.currentUserRole.isSuperAdmin;

  Map<String, int> get _emojiCounts {
    final counts = <String, int>{};
    for (final r in widget.reactions) {
      for (final e in r.emojiReactions) {
        counts[e] = (counts[e] ?? 0) + 1;
      }
    }
    return counts;
  }

  @override
  void initState() {
    super.initState();
    _editTitleController =
        TextEditingController(text: widget.feedItem.post.title ?? '');
    _editContentController =
        TextEditingController(text: widget.feedItem.post.content ?? '');

    // Load reactions for this post lazily
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ExploreFeedBloc>().add(
          LoadExploreFeedPostReactionsEvent(
            messageId: widget.feedItem.post.id,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _editTitleController.dispose();
    _editContentController.dispose();
    super.dispose();
  }

  // ── Reaction helpers ──────────────────────────────────────────────────────

  List<String> get _currentUserReactionEmojis {
    final match = widget.reactions.firstWhere(
      (r) => r.userId == widget.currentUserId,
      orElse: () => PostReaction(
        id: '',
        postId: widget.feedItem.post.id,
        userId: widget.currentUserId,
        emojiReactions: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    return match.emojiReactions;
  }

  void _handleEmojiReaction(String emoji) {
    // Map overlay emoji symbols to stored names (same mapping as chat screen)
    const emojiMap = {
      '❤️': 'heart',
      '👍': 'thumbsup',
      '😂': 'laugh',
      '👏': 'claps',
    };
    final emojiName = emojiMap[emoji] ?? emoji;

    final bloc = context.read<ExploreFeedBloc>();
    if (_currentUserReactionEmojis.contains(emojiName)) {
      bloc.add(RemoveExploreFeedReactionEvent(
        messageId: widget.feedItem.post.id,
        userId: widget.currentUserId,
      ));
    } else {
      bloc.add(AddExploreFeedReactionEvent(
        messageId: widget.feedItem.post.id,
        emojis: [emojiName],
        userId: widget.currentUserId,
      ));
    }
  }

  void _handleReaction() {
    // Open the full emoji picker (same as "more" in chat screen)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmojiPickerScreen(
          theme: AppThemeMode.light,
          initialSelectedEmojis: _currentUserReactionEmojis,
          onEmojisSelected: (selectedEmojis) {
            final bloc = context.read<ExploreFeedBloc>();
            if (selectedEmojis.isEmpty) {
              bloc.add(RemoveExploreFeedReactionEvent(
                messageId: widget.feedItem.post.id,
                userId: widget.currentUserId,
              ));
            } else {
              bloc.add(AddExploreFeedReactionEvent(
                messageId: widget.feedItem.post.id,
                emojis: selectedEmojis,
                userId: widget.currentUserId,
              ));
            }
          },
        ),
        fullscreenDialog: true,
      ),
    );
  }

  // ── Long-press overlay ────────────────────────────────────────────────────

  void _showReactionOverlay() {
    final cardRect = _cardKey.globalPaintBounds;
    if (cardRect == null) return;

    HapticFeedback.mediumImpact();

    // Build a compact balloon: 50% screen width, 20% screen height,
    // centred horizontally and aligned near the card vertically.
    final screenSize = MediaQuery.of(context).size;
    final compactWidth = screenSize.width * 0.5;
    final compactHeight = screenSize.height * 0.12;
    final left = (screenSize.width - compactWidth) / 2;
    final top = (cardRect.center.dy - compactHeight / 2).clamp(
      80.0,                                       // below status bar / app bar
      screenSize.height - compactHeight - 80.0,   // room for reaction bar
    );
    final compactRect = Rect.fromLTWH(left, top, compactWidth, compactHeight);

    showFullscreenReactionOverlay(
      context: context,
      data: FullscreenReactionData(
        messageRect: compactRect,
        messageContent: _buildCardSnapshot(),
        isPinned: false,
        isOwnMessage:
            widget.feedItem.post.createdBy == widget.currentUserId,
        currentUserRole: widget.currentUserRole,
        messageAuthorRole:
            widget.feedItem.post.author?.role ?? UserRole.regular,
        messageOrganizationId: widget.feedItem.post.organizationId,
        currentUserManagedOrganizations:
            widget.currentUserManagedOrganizations,
        currentUserId: widget.currentUserId,
        currentUserReactions: _currentUserReactionEmojis,
        allowPin: false, // Pin not supported in explore feed
      ),
      theme: AppThemeMode.light,
      onEmojiSelected: (emoji) {
        if (emoji == 'more') {
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
          case OverlayAction.delete:
            _handleDelete();
            break;
          case OverlayAction.pin:
          case OverlayAction.unpin:
            break; // Not reachable — allowPin: false
        }
      },
      onDismiss: () {},
    );
  }

  // ── Edit ─────────────────────────────────────────────────────────────────

  void _startEditing() {
    if (!_canEdit) return;
    setState(() {
      _isEditing = true;
      _editTitleController.text = widget.feedItem.post.title ?? '';
      _editContentController.text = widget.feedItem.post.content ?? '';
    });
  }

  void _cancelEditing() {
    setState(() => _isEditing = false);
  }

  Future<void> _saveEdit() async {
    final newTitle = _editTitleController.text.trim();
    final newContent = _editContentController.text.trim();

    if (newTitle.isEmpty && newContent.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post cannot be empty'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final originalTitle = widget.feedItem.post.title ?? '';
    final originalContent = widget.feedItem.post.content ?? '';

    if (newTitle == originalTitle && newContent == originalContent) {
      _cancelEditing();
      return;
    }

    setState(() => _isUpdating = true);

    try {
      final apiRepository = context.read<ApiRepository>();
      final updateData = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (newTitle != originalTitle) {
        updateData['title'] = newTitle.isEmpty ? null : newTitle;
      }
      if (newContent != originalContent) {
        updateData['content'] = newContent.isEmpty ? null : newContent;
      }

      final result = await apiRepository.update(
        'posts',
        widget.feedItem.post.id,
        updateData,
      );
      if (!result.isSuccess) {
        throw Exception(result.error ?? 'Failed to update post');
      }

      if (mounted) {
        context.read<ExploreFeedBloc>().add(
          UpdateExploreFeedPostEvent(
            messageId: widget.feedItem.post.id,
            title: newTitle.isEmpty ? null : newTitle,
            content: newContent.isEmpty ? null : newContent,
          ),
        );
        setState(() {
          _isEditing = false;
          _isUpdating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update post: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  void _handleDelete() {
    if (!_canDelete) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text(
          'Are you sure you want to delete this post? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _confirmDelete();
            },
            child: Text(
              'Delete',
              style: TextStyle(color: Colors.red.shade400),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    try {
      final apiRepository = context.read<ApiRepository>();
      final result =
          await apiRepository.delete('posts', widget.feedItem.post.id);
      if (!result.isSuccess) {
        throw Exception(result.error ?? 'Failed to delete post');
      }

      if (mounted) {
        context.read<ExploreFeedBloc>().add(
          RemoveExploreFeedPostEvent(messageId: widget.feedItem.post.id),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete post: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: _showReactionOverlay,
      child: Container(
        key: _cardKey,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _isEditing
            ? _buildEditForm()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOrganizationHeader(),
                  _buildPostContent(),
                  _buildReactionsAndTimestamp(),
                ],
              ),
      ),
    );
  }

  // ── Snapshot for overlay ──────────────────────────────────────────────────

  /// Compact mini-card shown in the reaction overlay balloon.
  /// Designed for ~50% screen width × ~20% screen height.
  Widget _buildCardSnapshot() {
    final logoUrl = widget.feedItem.organization.logoUrl;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Compact org row: small 24×24 logo + org name
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.headerBackground,
                ),
                child: logoUrl != null && logoUrl.isNotEmpty
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: logoUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 48,
                          memCacheHeight: 48,
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Colors.blue[300]!, Colors.blue[600]!],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            widget.feedItem.organization.name.isNotEmpty
                                ? widget.feedItem.organization.name[0]
                                    .toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.feedItem.organization.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          // Title (1 line)
          if (widget.feedItem.post.title != null &&
              widget.feedItem.post.title!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.feedItem.post.title!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          // Content preview (2 lines)
          if (widget.feedItem.post.content != null &&
              widget.feedItem.post.content!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              widget.feedItem.post.content!,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  // ── Existing sub-widgets (migrated from StatelessWidget) ──────────────────

  Widget _buildOrganizationHeader() {
    return InkWell(
      onTap: () => _navigateToOrganizationProfile(),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _navigateToOrganizationProfile(),
              child: _buildOrganizationLogo(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.feedItem.organization.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.feedItem.isFollowedOrganization)
                    Text(
                      'Following',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
            _buildFollowButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildOrganizationLogo() {
    final logoUrl = widget.feedItem.organization.logoUrl;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: AppTheme.headerBackground,
      ),
      child: logoUrl != null && logoUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: CachedNetworkImage(
                imageUrl: logoUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => _buildDefaultLogo(),
                errorWidget: (context, url, error) => _buildDefaultLogo(),
                memCacheWidth: 96,
                memCacheHeight: 96,
              ),
            )
          : _buildDefaultLogo(),
    );
  }

  Widget _buildDefaultLogo() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [Colors.blue[300]!, Colors.blue[600]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          widget.feedItem.organization.name.isNotEmpty
              ? widget.feedItem.organization.name[0].toUpperCase()
              : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildFollowButton() {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: () => _handleFollowToggle(),
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.feedItem.isFollowedOrganization
              ? AppTheme.accentSecondary.withOpacity(0.1)
              : AppTheme.accentPrimary,
          foregroundColor: widget.feedItem.isFollowedOrganization
              ? AppTheme.accentSecondary
              : AppTheme.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          elevation: widget.feedItem.isFollowedOrganization ? 0 : 2,
        ),
        child: Text(
          widget.feedItem.isFollowedOrganization ? 'Following' : 'Follow',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildPostContent() {
    return InkWell(
      onTap: () => _navigateToChannel(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.feedItem.post.title != null &&
                widget.feedItem.post.title!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  widget.feedItem.post.title!,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (widget.feedItem.post.content != null &&
                widget.feedItem.post.content!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  widget.feedItem.post.content!,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[800],
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (widget.feedItem.post.fileUrl != null &&
                widget.feedItem.post.fileUrl!.isNotEmpty)
              _buildMediaPreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPreview() {
    final fileUrls = _parseFileUrls(widget.feedItem.post.fileUrl);
    if (fileUrls.isEmpty) return const SizedBox.shrink();

    final firstUrl = fileUrls.first;
    final isPdf = firstUrl.toLowerCase().endsWith('.pdf');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          if (!isPdf) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ImageCarouselScreen(
                  imageUrls: fileUrls
                      .where((url) => !url.toLowerCase().endsWith('.pdf'))
                      .toList(),
                  initialIndex: 0,
                  theme: AppThemeMode.light,
                ),
              ),
            );
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: isPdf
              ? _buildPdfPlaceholder()
              : CachedNetworkImage(
                  imageUrl: firstUrl,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    height: 200,
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 200,
                    color: Colors.grey[200],
                    child: const Center(
                      child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
                    ),
                  ),
                  memCacheWidth: 400,
                ),
        ),
      ),
    );
  }

  Widget _buildPdfPlaceholder() {
    return Container(
      height: 100,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.picture_as_pdf, size: 32, color: Colors.red[400]),
          const SizedBox(width: 8),
          Text(
            'PDF Document',
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionsAndTimestamp() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.reactions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: MessageReactionsWidget(
                messageId: widget.feedItem.post.id,
                theme: AppThemeMode.light,
                isAdmin: _isAdmin,
                reactions: widget.reactions,
                emojiCounts: _emojiCounts,
                currentUserId: widget.currentUserId,
                onReactionTap: (messageId, emojis) {
                  final bloc = context.read<ExploreFeedBloc>();
                  if (emojis.isEmpty) {
                    bloc.add(RemoveExploreFeedReactionEvent(
                      messageId: messageId,
                      userId: widget.currentUserId,
                    ));
                  } else {
                    bloc.add(AddExploreFeedReactionEvent(
                      messageId: messageId,
                      emojis: emojis,
                      userId: widget.currentUserId,
                    ));
                  }
                },
              ),
            ),
          Text(
            widget.feedItem.post.timeDisplay,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildEditForm() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.feedItem.post.title != null &&
              widget.feedItem.post.title!.isNotEmpty) ...[
            Text(
              'TITLE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _editTitleController,
              maxLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Enter title...',
                filled: true,
                fillColor: AppTheme.cardGreyBackground,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: AppTheme.accentPrimary, width: 1),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'CONTENT',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _editContentController,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Enter content...',
              filled: true,
              fillColor: AppTheme.cardGreyBackground,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: AppTheme.accentPrimary, width: 1),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isUpdating ? null : _cancelEditing,
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
              const SizedBox(width: 8),
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
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Navigation / follow (same logic as before) ────────────────────────────

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
        return [fileUrl];
      }
    }
    if (fileUrl is List) {
      return fileUrl.map((url) => url.toString()).toList();
    }
    return [];
  }

  Future<void> _handleFollowToggle() async {
    final canContinue = await ProfileUtils.showProfileCompletionBottomSheet(
      context,
      message: 'Please complete your profile to follow channels.',
    );
    if (!canContinue || !context.mounted) return;

    final apiService = SupabaseApiService.instance;
    final currentUser = await apiService.getCurrentUser();
    if (currentUser?.userId == null) return;

    final userId = currentUser!.userId!;
    final orgId = widget.feedItem.organization.id;

    try {
      if (widget.feedItem.isFollowedOrganization) {
        await apiService.unfollowOrganization(userId, orgId);
      } else {
        await apiService.followOrganization(userId, orgId);
        await NotificationPreferencesService.instance
            .enableChannelNotification(orgId);
      }

      if (context.mounted) {
        context.read<ExploreFeedBloc>().add(
          UpdateOrganizationFollowStatus(
            organizationId: orgId,
            isFollowing: !widget.feedItem.isFollowedOrganization,
          ),
        );
      }

      widget.onFollowChanged?.call();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to ${widget.feedItem.isFollowedOrganization ? "unfollow" : "follow"}: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navigateToOrganizationProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrganizationProfileScreen(
          organizationId: widget.feedItem.organization.id,
        ),
      ),
    ).then((result) {
      if (result == true) {
        widget.onFollowChanged?.call();
      }
    });
  }

  Future<void> _navigateToChannel() async {
    final canContinue = await ProfileUtils.showProfileCompletionBottomSheet(
      context,
      message: 'Please complete your profile to access channels.',
    );

    if (canContinue && context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      mainScaffoldKey.currentState?.switchToChannelsTab(
        organizationId: widget.feedItem.organization.id,
      );
    }
  }
}
