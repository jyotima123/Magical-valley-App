// lib/modules/chat/widgets/message_context_menu.dart
//
// DEPRECATED: This widget has been replaced by the fullscreen_reaction_overlay.dart
// which provides an iMessage-style fullscreen experience with:
// - Blurred background overlay
// - Message "lift" animation with scale and shadow
// - Spring-animated emoji reaction bar
// - Spring-animated action menu
// - Smooth dismiss transitions
//
// This file is kept for backwards compatibility. Use FullscreenReactionOverlay instead.
// See: lib/modules/chat/widgets/fullscreen_reaction_overlay.dart

import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/services/api_repository.dart';

enum MessageAction { react, edit, pin, unpin, delete }

@Deprecated('Use FullscreenReactionOverlay from fullscreen_reaction_overlay.dart instead')
class MessageContextMenu extends StatefulWidget {
  final Offset position;
  final bool isPinned;
  final bool isOwnMessage;
  final UserRole currentUserRole;
  final UserRole messageAuthorRole;
  final String messageOrganizationId;
  final List<String> currentUserManagedOrganizations;
  final Function(MessageAction) onActionSelected;
  final Function(String emoji)? onEmojiSelected;
  final VoidCallback onDismiss;

  const MessageContextMenu({
    super.key,
    required this.position,
    required this.isPinned,
    required this.isOwnMessage,
    required this.currentUserRole,
    required this.messageAuthorRole,
    required this.messageOrganizationId,
    required this.currentUserManagedOrganizations,
    required this.onActionSelected,
    this.onEmojiSelected,
    required this.onDismiss,
  });

  @override
  State<MessageContextMenu> createState() => _MessageContextMenuState();
}

class _MessageContextMenuState extends State<MessageContextMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  int? _hoveredEmojiIndex;
  final List<String> _emojis = ['❤️', '👍', '😂', '👏'];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Helper methods for permission checking
  bool get _canEdit => _canEditMessage();
  bool get _canDelete => _canDeleteMessage();
  bool get _canPin => _canPinMessage();

  bool _canEditMessage() {
    // Superadmins can edit any message
    if (widget.currentUserRole.isSuperAdmin) return true;

    // Admins can edit posts in organizations they manage
    if (widget.currentUserRole.isAdmin) {
      return widget.currentUserManagedOrganizations.contains(
        widget.messageOrganizationId,
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
        widget.messageOrganizationId,
      );
    }

    // Regular users cannot delete any messages
    return false;
  }

  bool _canPinMessage() {
    // Superadmins can pin/unpin any message
    if (widget.currentUserRole.isSuperAdmin) return true;

    // Admins can pin/unpin any message (including other admins' messages)
    if (widget.currentUserRole.isAdmin) return true;

    // Regular users cannot pin/unpin messages
    return false;
  }

  void _handleActionTap(MessageAction action) async {
    await _animationController.reverse();
    widget.onActionSelected(action);
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final menuWidth = 200.0;
    final menuHeight = _calculateMenuHeight();

    // Adjust position to keep menu within screen bounds
    double left = widget.position.dx;
    double top = widget.position.dy;

    if (left + menuWidth > screenSize.width) {
      left = screenSize.width - menuWidth - 16;
    }
    if (left < 16) {
      left = 16;
    }

    if (top + menuHeight > screenSize.height) {
      top = widget.position.dy - menuHeight - 16;
    }
    if (top < 100) {
      top = 100;
    }

    // Move Positioned to be the parent of animations
    return Positioned(
      left: left,
      top: top,
      child: Listener(
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: _buildContextMenuContent(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContextMenuContent() {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 200.0,
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: AppTheme.darkBorder, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildQuickEmojiRow(),
            if (_canEdit) ...[
              _buildDivider(),
              _buildMenuItem(
                icon: Icons.edit_outlined,
                label: 'Edit',
                action: MessageAction.edit,
              ),
            ],
            if (_canPin) ...[
              _buildDivider(),
              _buildMenuItem(
                icon: widget.isPinned
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
                label: widget.isPinned ? 'Unpin' : 'Pin',
                action: widget.isPinned
                    ? MessageAction.unpin
                    : MessageAction.pin,
              ),
            ],
            if (_canDelete) ...[
              _buildDivider(),
              _buildMenuItem(
                icon: Icons.delete_outline,
                label: 'Delete',
                action: MessageAction.delete,
                isDestructive: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required MessageAction action,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: () => _handleActionTap(action),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isDestructive
                  ? AppTheme.error
                  : AppTheme.darkTextSecondary,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: isDestructive ? AppTheme.error : AppTheme.darkText,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _getEmojiAtPosition(Offset globalPosition) {
    final RenderBox? menuBox = context.findRenderObject() as RenderBox?;
    if (menuBox == null) return null;

    final localPosition = menuBox.globalToLocal(globalPosition);

    // Calculate emoji positions
    const emojiSize = 40.0;
    const padding = 8.0;
    const totalWidth = 200.0; // menu width
    final emojiRowTop = 8.0;
    final emojiRowBottom = emojiRowTop + emojiSize;

    // Check if pointer is within emoji row bounds
    if (localPosition.dy < emojiRowTop || localPosition.dy > emojiRowBottom) {
      return null;
    }
    if (localPosition.dx < padding || localPosition.dx > totalWidth - padding) {
      return null;
    }

    // Calculate which emoji
    final relativeX = localPosition.dx - padding;
    final emojiSpacing =
        (totalWidth - (padding * 2) - (emojiSize * _emojis.length)) /
        (_emojis.length - 1);

    for (int i = 0; i < _emojis.length; i++) {
      final emojiLeft = i * (emojiSize + emojiSpacing);
      final emojiRight = emojiLeft + emojiSize;

      if (relativeX >= emojiLeft && relativeX <= emojiRight) {
        return _emojis[i];
      }
    }

    return null;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final emoji = _getEmojiAtPosition(event.position);
    final index = emoji != null ? _emojis.indexOf(emoji) : null;

    if (index != null && index != _hoveredEmojiIndex) {
      setState(() {
        _hoveredEmojiIndex = index;
      });
    } else if (emoji == null && _hoveredEmojiIndex != null) {
      setState(() {
        _hoveredEmojiIndex = null;
      });
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    final emoji = _getEmojiAtPosition(event.position);
    if (emoji != null) {
      widget.onEmojiSelected?.call(emoji);
      widget.onDismiss();
    }
  }

  Widget _buildQuickEmojiRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(_emojis.length, (index) {
          final emoji = _emojis[index];
          final isHovered = _hoveredEmojiIndex == index;
          final scale = isHovered ? 1.3 : 1.0;

          return GestureDetector(
            onTap: () {
              widget.onEmojiSelected?.call(emoji);
              widget.onDismiss();
            },
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 1.0, end: scale),
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    child: Text(emoji, style: TextStyle(fontSize: 24 * value)),
                  ),
                );
              },
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: AppTheme.darkBorder,
      indent: 16,
      endIndent: 16,
    );
  }

  double _calculateMenuHeight() {
    int itemCount = 1; // Quick emoji row (always available)
    if (_canEdit) itemCount += 1; // Edit
    if (_canPin) itemCount += 1; // Pin/Unpin
    if (_canDelete) itemCount += 1; // Delete

    // Each item is ~48px + dividers, emoji row is ~56px
    return 56.0 + ((itemCount - 1) * 48.0) + ((itemCount - 1) * 1.0);
  }
}

// Extension to add context menu colors
extension MessageContextColors on BuildContext {
  Color get darkSurface => AppTheme.darkBackground.withOpacity(0.95);
  Color get darkBorder => AppTheme.darkBorder;
  Color get darkText => AppTheme.darkText;
  Color get darkTextSecondary => AppTheme.darkTextSecondary;
  Color get error => Colors.red.shade400;
}
