// lib/modules/chat/widgets/pinned_posts_section.dart
import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/chat/models/chat_message.dart';
import 'package:mvc_app/modules/chat/models/post_reactions_model.dart';
import 'package:mvc_app/services/api_repository.dart';

import 'message_item.dart';

class PinnedPostsSection extends StatefulWidget {
  final List<ChatMessage> pinnedMessages;
  final String currentUserId;
  final AppThemeMode theme;
  final UserRole currentUserRole;
  final String currentOrganizationId;
  final List<String> currentUserManagedOrganizations;
  final Function(String messageId, bool shouldPin)? onPinToggle;
  final Map<String, List<PostReaction>> messageReactions;
  final Function(String messageId, List<String> emojis)? onReactionUpdate;

  const PinnedPostsSection({
    super.key,
    required this.pinnedMessages,
    required this.currentUserId,
    required this.theme,
    required this.currentUserRole,
    required this.currentOrganizationId,
    required this.currentUserManagedOrganizations,
    required this.messageReactions,
    this.onPinToggle,
    this.onReactionUpdate,
  });

  @override
  State<PinnedPostsSection> createState() => _PinnedPostsSectionState();
}

class _PinnedPostsSectionState extends State<PinnedPostsSection>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;
  late Animation<double> _iconRotationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    _iconRotationAnimation = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.theme == AppThemeMode.dark;

    if (widget.pinnedMessages.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: isDark
                ? AppTheme.darkBackground.withOpacity(0.95)
                : AppTheme.pinnedPostsBackground,
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? AppTheme.darkBorder
                    : AppTheme.pinnedPostsBorder,
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.black : Colors.grey).withOpacity(0.1),
                offset: const Offset(0, 2),
                blurRadius: 4,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _toggleExpanded,
                  splashColor: Color(0xFFF58868).withOpacity(0.5),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.push_pin,
                          size: 20,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.pinnedIconColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _getPinnedPostsHeaderText(),
                            style: isDark
                                ? AppTheme.darkPinnedPostsHeaderText
                                : AppTheme.pinnedPostsHeaderText,
                          ),
                        ),
                        AnimatedBuilder(
                          animation: _iconRotationAnimation,
                          builder: (context, child) {
                            return Transform.rotate(
                              angle: _iconRotationAnimation.value * 3.14159,
                              child: Icon(
                                Icons.keyboard_arrow_down,
                                color: isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.pinnedIconColor,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Animated divider
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: _isExpanded ? 1 : 0,
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: isDark
                      ? AppTheme.darkBorder
                      : AppTheme.pinnedPostsBorder,
                  indent: 0,
                  endIndent: 0,
                ),
              ),

              // Animated pinned messages content
              ClipRect(
                child: AnimatedAlign(
                  alignment: Alignment.topCenter,
                  heightFactor: _expandAnimation.value,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: AnimatedOpacity(
                    opacity: _expandAnimation.value,
                    duration: const Duration(milliseconds: 250),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ...widget.pinnedMessages.map(
                              (message) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: MessageItem(
                                  message: message,
                                  currentUserId: widget.currentUserId,
                                  theme: widget.theme,
                                  isPinned: true,
                                  isAdmin:
                                      false, // Default to false for pinned posts
                                  currentUserRole: widget.currentUserRole,
                                  messageAuthorRole:
                                      message.author?.role ?? UserRole.regular,
                                  currentOrganizationId:
                                      widget.currentOrganizationId,
                                  currentUserManagedOrganizations:
                                      widget.currentUserManagedOrganizations,
                                  reactions:
                                      widget.messageReactions[message.id] ?? [],
                                  onPinToggle: widget.onPinToggle,
                                  onEditMessage:
                                      null, // No edit functionality for pinned posts
                                  onDeleteMessage:
                                      null, // No delete functionality for pinned posts
                                  onReactionUpdate: widget.onReactionUpdate,
                                  apiRepository:
                                      null, // No API access for pinned posts
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Collapsed preview (only shown when not expanded)
              if (!_isExpanded && widget.pinnedMessages.isNotEmpty)
                AnimatedOpacity(
                  opacity: _isExpanded ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: _isExpanded
                      ? Container(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Text(
                            _getPreviewText(),
                            style: isDark
                                ? AppTheme.chatTimestamp.copyWith(
                                    color: AppTheme.darkTextTertiary,
                                  )
                                : AppTheme.chatMessage.copyWith(
                                    color: AppTheme.secondaryHeadingColor,
                                  ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : Container(),
                ),
            ],
          ),
        );
      },
    );
  }

  String _getPinnedPostsHeaderText() {
    if (widget.pinnedMessages.isEmpty) {
      return 'Pinned Posts';
    }

    if (widget.pinnedMessages.length == 1) {
      final message = widget.pinnedMessages.first;
      final previewText = _getMessagePreviewText(message);
      return previewText.length > 50
          ? '${previewText.substring(0, 47)}...'
          : previewText;
    }

    // For multiple pinned posts, show first few
    final previewTexts = widget.pinnedMessages
        .take(3)
        .map(_getMessagePreviewText)
        .toList();
    final remainingCount = widget.pinnedMessages.length - 3;

    if (previewTexts.length == 1) {
      return previewTexts.first.length > 50
          ? '${previewTexts.first.substring(0, 47)}...'
          : previewTexts.first;
    }

    // Show multiple previews, truncating if too long
    String combined = previewTexts.join(' • ');
    if (remainingCount > 0) {
      combined += ' • +$remainingCount more';
    }

    return combined.length > 80 ? '${combined.substring(0, 77)}...' : combined;
  }

  String _getMessagePreviewText(ChatMessage message) {
    if (message.title != null && message.title!.isNotEmpty) {
      return message.title!;
    } else if (message.content != null && message.content!.isNotEmpty) {
      // Get first line of content
      final firstLine = message.content!.split('\n').first.trim();
      return firstLine;
    } else {
      return 'Pinned ${message.postType} post';
    }
  }

  String _getPreviewText() {
    final firstMessage = widget.pinnedMessages.first;
    return _getMessagePreviewText(firstMessage);
  }
}
