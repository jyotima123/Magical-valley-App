// lib/modules/chat/widgets/fullscreen_reaction_overlay.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/chat/widgets/message_snapshot.dart';
import 'package:mvc_app/modules/chat/widgets/spring_reaction_bar.dart';
import 'package:mvc_app/modules/chat/widgets/spring_action_menu.dart';
import 'package:mvc_app/services/api_repository.dart';

/// Data class containing all information needed to display the fullscreen overlay
class FullscreenReactionData {
  final Rect messageRect;
  final Widget messageContent;
  final bool isPinned;
  final bool isOwnMessage;
  final UserRole currentUserRole;
  final UserRole messageAuthorRole;
  final String messageOrganizationId;
  final List<String> currentUserManagedOrganizations;
  final String currentUserId;
  final List<String> currentUserReactions;
  final bool allowPin;

  const FullscreenReactionData({
    required this.messageRect,
    required this.messageContent,
    required this.isPinned,
    required this.isOwnMessage,
    required this.currentUserRole,
    required this.messageAuthorRole,
    required this.messageOrganizationId,
    required this.currentUserManagedOrganizations,
    required this.currentUserId,
    this.currentUserReactions = const [],
    this.allowPin = true,
  });
}

/// Enum for overlay actions
enum OverlayAction { edit, pin, unpin, delete }

/// Main fullscreen overlay widget with iMessage-style animations
class FullscreenReactionOverlay extends StatefulWidget {
  final FullscreenReactionData data;
  final AppThemeMode theme;
  final Function(String emoji)? onEmojiSelected;
  final Function(OverlayAction action)? onActionSelected;
  final VoidCallback onDismiss;

  const FullscreenReactionOverlay({
    super.key,
    required this.data,
    required this.theme,
    this.onEmojiSelected,
    this.onActionSelected,
    required this.onDismiss,
  });

  @override
  State<FullscreenReactionOverlay> createState() =>
      _FullscreenReactionOverlayState();
}

class _FullscreenReactionOverlayState extends State<FullscreenReactionOverlay>
    with TickerProviderStateMixin {
  // Animation controllers
  late AnimationController _backdropController;
  late AnimationController _messageController;
  late AnimationController _reactionBarController;
  late AnimationController _actionMenuController;
  late AnimationController _celebrationController;

  // Backdrop animations
  late Animation<double> _blurAnimation;
  late Animation<double> _overlayOpacityAnimation;

  // Message lift animations
  late Animation<double> _messageScaleAnimation;
  late Animation<double> _messageShadowAnimation;

  // Reaction bar animation
  late Animation<double> _reactionBarAnimation;

  // Action menu animation
  late Animation<double> _actionMenuAnimation;

  // Celebration animation
  late Animation<double> _celebrationScaleAnimation;
  late Animation<double> _celebrationOpacityAnimation;
  late Animation<double> _celebrationSlideAnimation;

  // Selected emoji for celebration
  String? _selectedEmoji;
  bool _isCelebrating = false;

  // Permission helpers
  bool get _canEdit => _canEditMessage();
  bool get _canDelete => _canDeleteMessage();
  bool get _canPin => _canPinMessage();

  bool _canEditMessage() {
    if (widget.data.currentUserRole.isSuperAdmin) return true;
    if (widget.data.currentUserRole.isAdmin) {
      return widget.data.currentUserManagedOrganizations
          .contains(widget.data.messageOrganizationId);
    }
    return false;
  }

  bool _canDeleteMessage() {
    if (widget.data.currentUserRole.isSuperAdmin) return true;
    if (widget.data.currentUserRole.isAdmin) {
      return widget.data.currentUserManagedOrganizations
          .contains(widget.data.messageOrganizationId);
    }
    return false;
  }

  bool _canPinMessage() {
    if (!widget.data.allowPin) return false;
    if (widget.data.currentUserRole.isSuperAdmin) return true;
    if (widget.data.currentUserRole.isAdmin) return true;
    return false;
  }

  @override
  void initState() {
    super.initState();
    print('🎬 FullscreenReactionOverlay initState');
    _setupAnimations();
    _startEntryAnimations();
  }

  void _setupAnimations() {
    // Backdrop: 0-200ms
    _backdropController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _blurAnimation = Tween<double>(begin: 0, end: 15).animate(
      CurvedAnimation(parent: _backdropController, curve: Curves.easeOut),
    );

    _overlayOpacityAnimation = Tween<double>(begin: 0, end: 0.3).animate(
      CurvedAnimation(parent: _backdropController, curve: Curves.easeOut),
    );

    // Message lift: 50-250ms (200ms duration)
    _messageController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _messageScaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _messageController, curve: Curves.easeOutCubic),
    );

    _messageShadowAnimation = Tween<double>(begin: 0, end: 20).animate(
      CurvedAnimation(parent: _messageController, curve: Curves.easeOutCubic),
    );

    // Reaction bar: 150-400ms (250ms duration with spring)
    _reactionBarController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _reactionBarAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _reactionBarController, curve: Curves.elasticOut),
    );

    // Action menu: 200-450ms (250ms duration with easeOutBack)
    _actionMenuController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _actionMenuAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _actionMenuController, curve: Curves.easeOutBack),
    );

    // Celebration animation: 600ms total
    _celebrationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Scale: starts small, bounces up to large, then settles
    _celebrationScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.4)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.4, end: 1.2)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
    ]).animate(_celebrationController);

    // Opacity: fade in quickly, hold, then fade out
    _celebrationOpacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
    ]).animate(_celebrationController);

    // Slide: rises up from below
    _celebrationSlideAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 100.0, end: -20.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -20.0, end: -60.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
    ]).animate(_celebrationController);
  }

  void _startEntryAnimations() {
    // Haptic feedback on overlay show
    HapticFeedback.mediumImpact();

    // Staggered entry animations according to spec
    _backdropController.forward();

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _messageController.forward();
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _reactionBarController.forward();
    });

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _actionMenuController.forward();
    });
  }

  Future<void> _dismiss() async {
    // Exit animations (total ~300ms)
    // 0-150ms: Reaction bar & action menu fade out
    _reactionBarController.reverse();
    _actionMenuController.reverse();

    // 50-200ms: Message returns
    await Future.delayed(const Duration(milliseconds: 50));
    if (mounted) _messageController.reverse();

    // 100-300ms: Backdrop fades out
    await Future.delayed(const Duration(milliseconds: 50));
    if (mounted) await _backdropController.reverse();

    widget.onDismiss();
  }

  void _handleEmojiSelected(String emoji) {
    HapticFeedback.mediumImpact();
    widget.onEmojiSelected?.call(emoji);
    _playCelebration(emoji);
  }

  Future<void> _playCelebration(String emoji) async {
    setState(() {
      _selectedEmoji = emoji;
      _isCelebrating = true;
    });

    // Hide the reaction bar and action menu while celebrating
    _reactionBarController.reverse();
    _actionMenuController.reverse();

    // Play the celebration animation
    await _celebrationController.forward();

    // Small delay before dismissing
    await Future.delayed(const Duration(milliseconds: 50));

    if (mounted) {
      _dismiss();
    }
  }

  void _handleActionSelected(OverlayAction action) {
    HapticFeedback.lightImpact();
    widget.onActionSelected?.call(action);
    _dismiss();
  }

  @override
  void dispose() {
    _backdropController.dispose();
    _messageController.dispose();
    _reactionBarController.dispose();
    _actionMenuController.dispose();
    _celebrationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('🎬 FullscreenReactionOverlay build called');

    final screenSize = MediaQuery.of(context).size;
    final messageRect = widget.data.messageRect;

    print('🎬 Screen size: $screenSize, messageRect: $messageRect');

    // Calculate positions for reaction bar and action menu
    final reactionBarHeight = 56.0;
    final actionMenuHeight = _calculateActionMenuHeight();
    final spacing = 12.0;
    final actionSpacing = 8.0;

    // Determine if reaction bar should be above or below message
    final spaceAbove = messageRect.top;
    final showReactionBarAbove =
        spaceAbove > (reactionBarHeight + spacing + 50);

    // Calculate vertical positions
    double reactionBarTop;
    double actionMenuTop;

    if (showReactionBarAbove) {
      reactionBarTop = messageRect.top - reactionBarHeight - spacing;
      actionMenuTop = messageRect.bottom + actionSpacing;
    } else {
      reactionBarTop = messageRect.bottom + spacing;
      actionMenuTop = reactionBarTop + reactionBarHeight + actionSpacing;
    }

    // Ensure action menu doesn't go off screen
    if (actionMenuTop + actionMenuHeight > screenSize.height - 20) {
      actionMenuTop = screenSize.height - actionMenuHeight - 20;
    }

    print('🎬 reactionBarTop: $reactionBarTop, actionMenuTop: $actionMenuTop');

    return Material(
      type: MaterialType.transparency,
      child: SizedBox.expand(
        child: GestureDetector(
          onTap: _dismiss,
          behavior: HitTestBehavior.opaque,
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _backdropController,
              _messageController,
              _reactionBarController,
              _actionMenuController,
              _celebrationController,
            ]),
            builder: (context, child) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Blurred backdrop
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: _blurAnimation.value,
                        sigmaY: _blurAnimation.value,
                      ),
                      child: Container(
                        color: Colors.black
                            .withOpacity(_overlayOpacityAnimation.value),
                      ),
                    ),
                  ),

                  // Message snapshot with lift animation
                  Positioned(
                    left: messageRect.left,
                    top: messageRect.top,
                    width: messageRect.width,
                    height: messageRect.height,
                    child: Transform.scale(
                      scale: _messageScaleAnimation.value,
                      child: MessageSnapshot(
                        content: widget.data.messageContent,
                        shadowElevation: _messageShadowAnimation.value,
                        theme: widget.theme,
                      ),
                    ),
                  ),

                  // Reaction bar
                  Positioned(
                    left: messageRect.left,
                    top: reactionBarTop,
                    child: Transform.scale(
                      scale: _reactionBarAnimation.value,
                      alignment: Alignment.bottomCenter,
                      child: Opacity(
                        opacity: _reactionBarAnimation.value.clamp(0.0, 1.0),
                        child: SpringReactionBar(
                          theme: widget.theme,
                          currentUserReactions: widget.data.currentUserReactions,
                          onEmojiSelected: _handleEmojiSelected,
                          animationProgress: _reactionBarAnimation.value,
                        ),
                      ),
                    ),
                  ),

                  // Action menu
                  if (_canEdit || _canPin || _canDelete)
                    Positioned(
                      left: messageRect.left,
                      top: actionMenuTop,
                      child: Transform.scale(
                        scale: _actionMenuAnimation.value,
                        alignment: Alignment.topCenter,
                        child: Opacity(
                          opacity: _actionMenuAnimation.value.clamp(0.0, 1.0),
                          child: SpringActionMenu(
                            theme: widget.theme,
                            isPinned: widget.data.isPinned,
                            canEdit: _canEdit,
                            canPin: _canPin,
                            canDelete: _canDelete,
                            onActionSelected: _handleActionSelected,
                            animationProgress: _actionMenuAnimation.value,
                          ),
                        ),
                      ),
                    ),

                  // Celebration emoji - big emoji burst animation
                  if (_isCelebrating && _selectedEmoji != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: Transform.translate(
                            offset: Offset(0, _celebrationSlideAnimation.value),
                            child: Transform.scale(
                              scale: _celebrationScaleAnimation.value,
                              child: Opacity(
                                opacity: _celebrationOpacityAnimation.value,
                                child: Text(
                                  _getEmojiForReaction(_selectedEmoji!),
                                  style: const TextStyle(
                                    fontSize: 120,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  double _calculateActionMenuHeight() {
    int itemCount = 0;
    if (_canEdit) itemCount++;
    if (_canPin) itemCount++;
    if (_canDelete) itemCount++;
    // Each item is ~48px
    return (itemCount * 48.0) + 16.0; // Add padding
  }

  String _getEmojiForReaction(String reaction) {
    switch (reaction.toLowerCase()) {
      case 'laugh':
        return '😂';
      case 'heart':
      case 'love':
        return '❤️';
      case 'thumbsup':
      case 'like':
        return '👍';
      case 'thumbsdown':
      case 'dislike':
        return '👎';
      case 'sad':
        return '😢';
      case 'angry':
        return '😡';
      case 'wow':
      case 'surprised':
        return '😮';
      case 'fire':
        return '🔥';
      case 'clap':
        return '👏';
      case 'pray':
        return '🙏';
      default:
        // If it's already an emoji, return it
        return reaction;
    }
  }
}

/// Helper function to show the fullscreen reaction overlay
void showFullscreenReactionOverlay({
  required BuildContext context,
  required FullscreenReactionData data,
  required AppThemeMode theme,
  Function(String emoji)? onEmojiSelected,
  Function(OverlayAction action)? onActionSelected,
  required VoidCallback onDismiss,
}) {
  print('🎬 showFullscreenReactionOverlay called');
  print('🎬 messageRect: ${data.messageRect}');

  final overlayState = Overlay.of(context);
  late OverlayEntry overlayEntry;

  overlayEntry = OverlayEntry(
    builder: (context) {
      print('🎬 Building OverlayEntry');
      return FullscreenReactionOverlay(
        data: data,
        theme: theme,
        onEmojiSelected: onEmojiSelected,
        onActionSelected: onActionSelected,
        onDismiss: () {
          print('🎬 Overlay dismissed');
          overlayEntry.remove();
          onDismiss();
        },
      );
    },
  );

  overlayState.insert(overlayEntry);
  print('🎬 OverlayEntry inserted');
}
