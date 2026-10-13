// lib/modules/chat/widgets/spring_action_menu.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/chat/widgets/fullscreen_reaction_overlay.dart';

/// Animated action menu with staggered spring entrance
/// Appears below the message in the fullscreen overlay
class SpringActionMenu extends StatefulWidget {
  final AppThemeMode theme;
  final bool isPinned;
  final bool canEdit;
  final bool canPin;
  final bool canDelete;
  final Function(OverlayAction action)? onActionSelected;
  final double animationProgress;

  const SpringActionMenu({
    super.key,
    required this.theme,
    required this.isPinned,
    required this.canEdit,
    required this.canPin,
    required this.canDelete,
    this.onActionSelected,
    this.animationProgress = 1.0,
  });

  @override
  State<SpringActionMenu> createState() => _SpringActionMenuState();
}

class _SpringActionMenuState extends State<SpringActionMenu> {
  int? _pressedIndex;

  bool get _isDarkTheme => widget.theme == AppThemeMode.dark;

  List<_ActionItem> get _actionItems {
    final items = <_ActionItem>[];

    if (widget.canEdit) {
      items.add(_ActionItem(
        icon: Icons.edit_outlined,
        label: 'Edit',
        action: OverlayAction.edit,
        isDestructive: false,
      ));
    }

    if (widget.canPin) {
      items.add(_ActionItem(
        icon: widget.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
        label: widget.isPinned ? 'Unpin' : 'Pin',
        action: widget.isPinned ? OverlayAction.unpin : OverlayAction.pin,
        isDestructive: false,
      ));
    }

    if (widget.canDelete) {
      items.add(_ActionItem(
        icon: Icons.delete_outline,
        label: 'Delete',
        action: OverlayAction.delete,
        isDestructive: true,
      ));
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _actionItems;
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: _isDarkTheme ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(items.length * 2 - 1, (index) {
            // Odd indices are dividers
            if (index.isOdd) {
              return _buildDivider();
            }

            final itemIndex = index ~/ 2;
            final item = items[itemIndex];

            // Staggered animation delay: 30ms per item
            final staggerDelay = itemIndex * 0.08; // Approx 30ms of 375ms
            final adjustedProgress =
                ((widget.animationProgress - staggerDelay) / (1 - staggerDelay))
                    .clamp(0.0, 1.0);

            return _buildActionItem(
              item: item,
              index: itemIndex,
              progress: adjustedProgress,
            );
          }),
        ),
      ),
    );
  }

  Widget _buildActionItem({
    required _ActionItem item,
    required int index,
    required double progress,
  }) {
    final isPressed = _pressedIndex == index;

    return GestureDetector(
      onTapDown: (_) {
        setState(() => _pressedIndex = index);
        HapticFeedback.selectionClick();
      },
      onTapUp: (_) {
        setState(() => _pressedIndex = null);
        widget.onActionSelected?.call(item.action);
      },
      onTapCancel: () {
        setState(() => _pressedIndex = null);
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 1.0, end: isPressed ? 0.95 : 1.0),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: progress,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                color: isPressed
                    ? (_isDarkTheme
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.05))
                    : Colors.transparent,
                child: Row(
                  children: [
                    Icon(
                      item.icon,
                      size: 20,
                      color: item.isDestructive
                          ? AppTheme.error
                          : (_isDarkTheme
                              ? AppTheme.darkTextSecondary
                              : AppTheme.secondaryHeadingColor),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: item.isDestructive
                            ? AppTheme.error
                            : (_isDarkTheme
                                ? AppTheme.darkText
                                : AppTheme.black),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 0.5,
      color: _isDarkTheme ? AppTheme.darkBorder : Colors.grey.withOpacity(0.2),
      indent: 16,
      endIndent: 16,
    );
  }
}

/// Internal data class for action items
class _ActionItem {
  final IconData icon;
  final String label;
  final OverlayAction action;
  final bool isDestructive;

  const _ActionItem({
    required this.icon,
    required this.label,
    required this.action,
    required this.isDestructive,
  });
}
