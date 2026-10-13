// lib/modules/chat/widgets/message_input.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart' show AuthBloc;
import 'package:mvc_app/modules/auth/auth_event.dart'
    show LoadManagedOrganizationsEvent;
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/chat/chat_bloc.dart';
import 'package:mvc_app/modules/posts/create_post_screen.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:clipboad_image/clipboad_image.dart';
import 'dart:convert';

class MessageInput extends StatefulWidget {
  final TextEditingController controller;
  final ChatLoadedState chatState;
  final AuthState authState;
  final AppThemeMode theme;

  const MessageInput({
    super.key,
    required this.controller,
    required this.chatState,
    required this.authState,
    required this.theme,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput>
    with TickerProviderStateMixin {
  late AnimationController _expandController;
  final GlobalKey _containerKey = GlobalKey();
  final GlobalKey _textFieldKey = GlobalKey();

  // Add this flag to prevent multiple organization loads
  bool _hasLoadedOrganizations = false;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _loadOrganizationsIfNeeded() {
    if (widget.authState is AuthAuthenticatedState &&
        !_hasLoadedOrganizations) {
      final authState = widget.authState as AuthAuthenticatedState;
      if (authState.userProfile != null) {
        final profile = authState.userProfile!;

        print(
          "🌐 Loading the organizations the user ${profile.email} can manage...",
        );

        context.read<AuthBloc>().add(
          LoadManagedOrganizationsEvent(userId: authState.userId),
        );

        // Set flag to prevent multiple loads
        _hasLoadedOrganizations = true;
      }
    }
  }

  void _sendMessage(BuildContext context) {
    final messageText = widget.controller.text.trim();

    // Get current user ID
    String currentUserId = '';
    if (widget.authState is AuthAuthenticatedState) {
      currentUserId = (widget.authState as AuthAuthenticatedState).userId;
    }

    if (messageText.isEmpty ||
        widget.chatState.selectedChannel == null ||
        widget.chatState.isSendingMessage ||
        currentUserId.isEmpty) {
      return;
    }

    context.read<ChatBloc>().add(
      SendMessageEvent(
        organizationId: widget.chatState.selectedChannel!.id,
        userId: currentUserId,
        content: messageText,
      ),
    );

    widget.controller.clear();
  }

  void _expandToCreatePost(BuildContext context) {
    // Get current user ID
    String currentUserId = '';
    if (widget.authState is AuthAuthenticatedState) {
      currentUserId = (widget.authState as AuthAuthenticatedState).userId;
    }

    if (widget.chatState.selectedChannel == null || currentUserId.isEmpty) {
      return;
    }

    // Store the current text
    final currentText = widget.controller.text;

    Navigator.of(context)
        .push(
          HeroTransitionRoute(
            child: CreatePostScreen(
              organizationId: widget.chatState.selectedChannel!.id,
              userId: currentUserId,
              initialContent: currentText,
              theme: widget.theme,
            ),
            heroTag: 'message-input-hero',
            sourceRect: _getTextFieldRect(),
          ),
        )
        .then((result) {
          // Clear the text field when returning
          widget.controller.clear();

          // Note: No need to refresh messages since SendMessageEvent automatically
          // adds the message to the chat state. Only refresh channels for last message info.
          if (result == true) {
            print("🔄 Post created successfully via SendMessageEvent");
            context.read<ChatBloc>().add(RefreshChannelsOnlyEvent());
          }
        });
  }

  void _expandToCreatePostWithImage(
    BuildContext context,
    Uint8List imageBytes,
  ) {
    // Get current user ID
    String currentUserId = '';
    if (widget.authState is AuthAuthenticatedState) {
      currentUserId = (widget.authState as AuthAuthenticatedState).userId;
    }

    if (widget.chatState.selectedChannel == null || currentUserId.isEmpty) {
      return;
    }

    // Store the current text
    final currentText = widget.controller.text;

    Navigator.of(context)
        .push(
          HeroTransitionRoute(
            child: CreatePostScreen(
              organizationId: widget.chatState.selectedChannel!.id,
              userId: currentUserId,
              initialContent: currentText,
              theme: widget.theme,
              initialImageBytes: imageBytes,
            ),
            heroTag: 'message-input-hero',
            sourceRect: _getTextFieldRect(),
          ),
        )
        .then((result) {
          // Clear the text field when returning
          widget.controller.clear();

          // Note: No need to refresh messages since SendMessageEvent automatically
          // adds the message to the chat state. Only refresh channels for last message info.
          if (result == true) {
            print("🔄 Post created successfully via SendMessageEvent");
            context.read<ChatBloc>().add(RefreshChannelsOnlyEvent());
          }
        });
  }

  Rect? _getTextFieldRect() {
    final RenderBox? renderBox =
        _textFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final position = renderBox.localToGlobal(Offset.zero);
      return Rect.fromLTWH(
        position.dx,
        position.dy,
        renderBox.size.width,
        renderBox.size.height,
      );
    }
    return null;
  }

  String _getHintText() {
    if (widget.authState is AuthAuthenticatedState &&
        (widget.authState as AuthAuthenticatedState).userProfile != null) {
      final profile = (widget.authState as AuthAuthenticatedState).userProfile!;
      final name =
          profile.fullName?.split(" ").first ?? profile.username ?? 'User';
      return '$name, post something...';
    } else if (widget.authState is AuthAuthenticatedState) {
      return ''; // Normal user, not admin
    } else {
      return ''; // Unauthenticated
    }
  }

  Widget _buildNoPermissionBanner() {
    final isDark = widget.theme == AppThemeMode.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardBackground : AppTheme.searchBarBackground,
        border: Border(
          top: BorderSide(
            color: isDark ? AppTheme.darkInputBackground : AppTheme.dividerBackground,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 16,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.secondaryHeadingColor,
            ),
            const SizedBox(width: 8),
            Text(
              'Only admins can send messages',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.secondaryHeadingColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Don't show input if user is not authenticated
    if (widget.authState is! AuthAuthenticatedState) {
      return Container();
    }

    // Load organizations if needed (only once)
    _loadOrganizationsIfNeeded();

    final authState = widget.authState as AuthAuthenticatedState;

    if (authState.userProfile != null) {
      final profile = authState.userProfile!;

      if (profile.role == UserRole.regular) {
        print(
          "🌐 Will not allow the user to post, because it's a non-admin user",
        );
        return _buildNoPermissionBanner();
      }

      print("🌐 List of user managed organizations: ");
      List<String> userManagedProfiles = authState.managedOrganizations
          .map((org) => org.id)
          .toList();

      for (var id in userManagedProfiles) {
        print(" > $id");
      }

      if ((profile.role == UserRole.admin) &&
          !userManagedProfiles.contains(
            widget.chatState.selectedChannel?.organizationId ?? "",
          )) {
        print(
          "🌐 Will not allow posting, because user does not manage ${widget.chatState.selectedChannel?.organizationId}",
        );
        return _buildNoPermissionBanner();
      }
    }

    return Hero(
      tag: 'message-input-hero',
      child: Material(
        color: Colors.transparent,
        child: Container(
          key: _containerKey,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (widget.theme == AppThemeMode.dark)
                ? AppTheme.darkCardBackground
                : AppTheme.searchBarBackground,
            // border: Border(
            //   top: BorderSide(
            //     color: (widget.theme == AppThemeMode.dark)
            //         ? AppTheme.darkInputBackground
            //         : AppTheme.secondaryHeadingColor,
            //   ),
            // ),
          ),
          child: (_getHintText() != "")
              ? Row(
                  children: [
                    // PLUS button for creating posts
                    GestureDetector(
                      onTap: () => _expandToCreatePost(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: (widget.theme == AppThemeMode.dark)
                              ? AppTheme.darkInputBackground
                              : AppTheme.headerBackground,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.add,
                          color: (widget.theme == AppThemeMode.dark)
                              ? AppTheme.darkTextSecondary
                              : AppTheme.black,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Text input for regular messages
                    Expanded(
                      child: TextField(
                        key: _textFieldKey,
                        controller: widget.controller,
                        style: TextStyle(
                          color: (widget.theme == AppThemeMode.dark)
                              ? AppTheme.black
                              : AppTheme.black,
                        ),
                        contextMenuBuilder:
                            (
                              BuildContext context,
                              EditableTextState editableTextState,
                            ) {
                              return AdaptiveTextSelectionToolbar(
                                anchors: editableTextState.contextMenuAnchors,
                                children: [
                                  // Paste option - handles both images and text
                                  TextSelectionToolbarTextButton(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 16,
                                    ),
                                    child: const Text('Paste'),
                                    onPressed: () async {
                                      // Close context menu first
                                      if (Navigator.of(context).canPop()) {
                                        Navigator.of(context).pop();
                                      }

                                      // Use a small delay to ensure context menu is closed
                                      await Future.delayed(
                                        const Duration(milliseconds: 100),
                                      );

                                      if (!mounted) return;

                                      // Try to paste image first
                                      try {
                                        Uint8List? imageBytes =
                                            await ClipboadImage.getImage();
                                        if (imageBytes != null && mounted) {
                                          // Navigate to create post screen with image bytes
                                          _expandToCreatePostWithImage(
                                            context,
                                            imageBytes,
                                          );
                                          return;
                                        }
                                      } catch (e) {
                                        print(
                                          "📋 Error checking for image in clipboard: $e",
                                        );
                                        // Continue to text paste
                                      }

                                      if (!mounted) return;

                                      // Fall back to text paste
                                      try {
                                        final clipboardData =
                                            await Clipboard.getData(
                                              Clipboard.kTextPlain,
                                            );
                                        if (clipboardData?.text != null &&
                                            mounted) {
                                          final text = clipboardData!.text!;

                                          // Check if it's a base64 image
                                          if (text.startsWith('data:image/')) {
                                            // Decode base64 image
                                            try {
                                              final commaIndex = text.indexOf(
                                                ',',
                                              );
                                              if (commaIndex != -1) {
                                                final base64String = text
                                                    .substring(commaIndex + 1);
                                                final imageBytes = base64Decode(
                                                  base64String,
                                                );
                                                _expandToCreatePostWithImage(
                                                  context,
                                                  Uint8List.fromList(
                                                    imageBytes,
                                                  ),
                                                );
                                                return;
                                              }
                                            } catch (e) {
                                              print(
                                                "📋 Error decoding base64 image: $e",
                                              );
                                              // Fall through to regular text paste
                                            }
                                          }

                                          // Regular text paste
                                          final newValue = widget
                                              .controller
                                              .value
                                              .copyWith(
                                                text: widget.controller.text
                                                    .replaceRange(
                                                      widget
                                                          .controller
                                                          .selection
                                                          .start,
                                                      widget
                                                          .controller
                                                          .selection
                                                          .end,
                                                      text,
                                                    ),
                                                selection:
                                                    TextSelection.collapsed(
                                                      offset:
                                                          widget
                                                              .controller
                                                              .selection
                                                              .start +
                                                          text.length,
                                                    ),
                                              );
                                          widget.controller.value = newValue;
                                        }
                                      } catch (e) {
                                        print("📋 Error pasting text: $e");
                                        if (mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Failed to paste: ${e.toString()}',
                                              ),
                                              backgroundColor: AppTheme.error,
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                  // Copy option
                                  if (widget.controller.selection.isValid &&
                                      !widget.controller.selection.isCollapsed)
                                    TextSelectionToolbarTextButton(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 16,
                                      ),
                                      child: const Text('Copy'),
                                      onPressed: () {
                                        final selectedText = widget
                                            .controller
                                            .text
                                            .substring(
                                              widget.controller.selection.start,
                                              widget.controller.selection.end,
                                            );
                                        Clipboard.setData(
                                          ClipboardData(text: selectedText),
                                        );
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                  // Cut option
                                  if (widget.controller.selection.isValid &&
                                      !widget.controller.selection.isCollapsed)
                                    TextSelectionToolbarTextButton(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 16,
                                      ),
                                      child: const Text('Cut'),
                                      onPressed: () {
                                        final selectedText = widget
                                            .controller
                                            .text
                                            .substring(
                                              widget.controller.selection.start,
                                              widget.controller.selection.end,
                                            );
                                        Clipboard.setData(
                                          ClipboardData(text: selectedText),
                                        );
                                        final newValue = widget.controller.value
                                            .copyWith(
                                              text: widget.controller.text
                                                  .replaceRange(
                                                    widget
                                                        .controller
                                                        .selection
                                                        .start,
                                                    widget
                                                        .controller
                                                        .selection
                                                        .end,
                                                    '',
                                                  ),
                                              selection:
                                                  TextSelection.collapsed(
                                                    offset: widget
                                                        .controller
                                                        .selection
                                                        .start,
                                                  ),
                                            );
                                        widget.controller.value = newValue;
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                  // Select All option
                                  if (widget.controller.text.isNotEmpty)
                                    TextSelectionToolbarTextButton(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 16,
                                      ),
                                      child: const Text('Select All'),
                                      onPressed: () {
                                        widget.controller.selection =
                                            TextSelection(
                                              baseOffset: 0,
                                              extentOffset:
                                                  widget.controller.text.length,
                                            );
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                ],
                              );
                            },
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          fillColor: (widget.theme == AppThemeMode.dark)
                              ? AppTheme.darkInputBackground
                              : AppTheme.headerBackground,
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        maxLines: null,
                        onSubmitted: (_) => _sendMessage(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Send button for regular messages
                    CircleAvatar(
                      backgroundColor: widget.chatState.isSendingMessage
                          ? Colors.grey
                          : AppTheme.accentPrimary,
                      child: widget.chatState.isSendingMessage
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.accentPrimary,
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(
                                Icons.send,
                                color: AppTheme.white,
                                size: 20,
                              ),
                              onPressed: () => _sendMessage(context),
                            ),
                    ),
                  ],
                )
              : Container(),
        ),
      ),
    );
  }
}

// Custom page route for hero transition
class HeroTransitionRoute<T> extends PageRoute<T> {
  final Widget child;
  final String heroTag;
  final Rect? sourceRect;

  HeroTransitionRoute({
    required this.child,
    required this.heroTag,
    this.sourceRect,
    super.settings,
  });

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return child;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.0, 1.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
      child: FadeTransition(opacity: animation, child: child),
    );
  }

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 400);
}
