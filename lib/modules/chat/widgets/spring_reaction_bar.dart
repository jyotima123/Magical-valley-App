// lib/modules/chat/widgets/spring_reaction_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mvc_app/app_theme.dart';

/// Animated emoji reaction bar with staggered spring entrance
/// Appears above or below the message in the fullscreen overlay
class SpringReactionBar extends StatefulWidget {
  final AppThemeMode theme;
  final List<String> currentUserReactions;
  final Function(String emoji)? onEmojiSelected;
  final double animationProgress;

  const SpringReactionBar({
    super.key,
    required this.theme,
    this.currentUserReactions = const [],
    this.onEmojiSelected,
    this.animationProgress = 1.0,
  });

  @override
  State<SpringReactionBar> createState() => _SpringReactionBarState();
}

class _SpringReactionBarState extends State<SpringReactionBar> {
  // Quick reaction emojis
  static const List<String> _emojis = ['❤️', '👍', '😂', '👏', '➕'];

  // Emoji to name mapping for API
  static const Map<String, String> _emojiToName = {
    '❤️': 'heart',
    '👍': 'thumbsup',
    '😂': 'laugh',
    '👏': 'claps',
  };

  // Track which emoji is being pressed
  int? _pressedIndex;

  bool get _isDarkTheme => widget.theme == AppThemeMode.dark;

  bool _isEmojiSelected(String emoji) {
    final emojiName = _emojiToName[emoji];
    if (emojiName == null) return false;
    return widget.currentUserReactions.contains(emojiName);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: _isDarkTheme ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: _isDarkTheme
              ? AppTheme.darkBorder
              : Colors.grey.withOpacity(0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(_emojis.length, (index) {
          final emoji = _emojis[index];
          final isSelected = _isEmojiSelected(emoji);
          final isPlus = emoji == '➕';

          // Staggered animation delay: 40ms per emoji
          final staggerDelay = index * 0.1; // 0.1 = 40ms of the 400ms total
          final adjustedProgress =
              ((widget.animationProgress - staggerDelay) / (1 - staggerDelay))
                  .clamp(0.0, 1.0);

          return _buildEmojiButton(
            emoji: emoji,
            index: index,
            isSelected: isSelected,
            isPlus: isPlus,
            progress: adjustedProgress,
          );
        }),
      ),
    );
  }

  Widget _buildEmojiButton({
    required String emoji,
    required int index,
    required bool isSelected,
    required bool isPlus,
    required double progress,
  }) {
    final isPressed = _pressedIndex == index;
    // Scale: 1.0 when normal, 1.4 when pressed/hovered
    final targetScale = isPressed ? 1.4 : 1.0;

    return GestureDetector(
      onTapDown: (_) {
        setState(() => _pressedIndex = index);
        HapticFeedback.selectionClick();
      },
      onTapUp: (_) {
        setState(() => _pressedIndex = null);
        if (isPlus) {
          // Handle more emojis action - emit special signal
          widget.onEmojiSelected?.call('more');
        } else {
          widget.onEmojiSelected?.call(emoji);
        }
      },
      onTapCancel: () {
        setState(() => _pressedIndex = null);
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 1.0, end: targetScale),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale * progress,
            child: Container(
              width: 44,
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.accentPrimary.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(22),
              ),
              alignment: Alignment.center,
              child: isPlus
                  ? Icon(
                      Icons.add_circle_outline,
                      size: 26,
                      color: _isDarkTheme
                          ? AppTheme.darkTextSecondary
                          : AppTheme.secondaryHeadingColor,
                    )
                  : Text(
                      emoji,
                      style: TextStyle(
                        fontSize: 26 * scale,
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// A standalone quick reaction button that can be used elsewhere
class QuickReactionButton extends StatefulWidget {
  final String emoji;
  final bool isSelected;
  final VoidCallback? onTap;
  final double size;

  const QuickReactionButton({
    super.key,
    required this.emoji,
    this.isSelected = false,
    this.onTap,
    this.size = 44,
  });

  @override
  State<QuickReactionButton> createState() => _QuickReactionButtonState();
}

class _QuickReactionButtonState extends State<QuickReactionButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 1.0, end: _isPressed ? 1.4 : 1.0),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? AppTheme.accentPrimary.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(widget.size / 2),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.emoji,
                style: TextStyle(fontSize: widget.size * 0.6),
              ),
            ),
          );
        },
      ),
    );
  }
}
