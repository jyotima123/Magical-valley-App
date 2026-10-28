// lib/modules/chat/widgets/message_snapshot.dart
import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';

/// Displays a "lifted" snapshot of a message with animated shadow
/// Used in the fullscreen reaction overlay to show the selected message
class MessageSnapshot extends StatelessWidget {
  /// The message content widget to display
  final Widget content;

  /// The elevation of the shadow (animated from 0 to ~20)
  final double shadowElevation;

  /// The current theme mode
  final AppThemeMode theme;

  const MessageSnapshot({
    super.key,
    required this.content,
    required this.shadowElevation,
    required this.theme,
  });

  bool get _isDarkTheme => theme == AppThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _isDarkTheme
                ? Colors.black.withOpacity(0.5)
                : Colors.black.withOpacity(0.2),
            blurRadius: shadowElevation,
            spreadRadius: shadowElevation * 0.1,
            offset: Offset(0, shadowElevation * 0.3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: content,
      ),
    );
  }
}

/// A builder widget that captures the message content for the overlay
/// This is used to wrap the message content in MessageItem
class MessageSnapshotBuilder extends StatelessWidget {
  /// The child widget to display normally and capture for the overlay
  final Widget child;

  /// The GlobalKey used to capture position and render the snapshot
  final GlobalKey messageKey;

  const MessageSnapshotBuilder({
    super.key,
    required this.child,
    required this.messageKey,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: messageKey,
      child: child,
    );
  }
}

/// Extension to get the Rect from a GlobalKey
extension GlobalKeyExtension on GlobalKey {
  Rect? get globalPaintBounds {
    final renderBox = currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      print('🔴 GlobalKey: RenderBox is null');
      return null;
    }

    if (!renderBox.hasSize) {
      print('🔴 GlobalKey: RenderBox has no size');
      return null;
    }

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    print('🟢 GlobalKey: Got position=$position, size=$size');

    return Rect.fromLTWH(
      position.dx,
      position.dy,
      size.width,
      size.height,
    );
  }
}
