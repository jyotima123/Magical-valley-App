// lib/utils/chat_menu_actions.dart
//
// Shared helper functions for handling actions triggered from the global
// application header (logo/menu) so they can be reused across tabs.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/modules/admin/create_organization.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/chat/chat_bloc.dart';
import 'package:mvc_app/modules/chat/models/chat_channel.dart';
import 'package:mvc_app/modules/chat/chat_selector.dart';
import 'package:mvc_app/modules/posts/create_post_screen.dart';

Future<void> handleCreateOrganization(BuildContext context) async {
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => CreateOrganizationScreen()),
  );

  if (!context.mounted) return;

  context.read<ChatBloc>().add(LoadChannelsEvent());
}

Future<void> handleCreatePost(
  BuildContext context,
  ChatChannel? selectedChannel,
  String currentUserId,
) async {
  final userId = _resolveUserId(context, currentUserId);

  if (userId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Unable to get user ID. Please try again.'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  final selectedChannels = await context.showChannelSelector(
    title: 'Select Channel for Post',
    allowMultipleSelection: false,
    initialSelection: selectedChannel != null ? [selectedChannel] : null,
  );

  if (selectedChannels == null || selectedChannels.isEmpty) {
    return;
  }

  await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => CreatePostScreen(
        organizationId: selectedChannels.first.id,
        userId: userId,
      ),
    ),
  ).then((result) {
    if (!(context.mounted)) return;

    if (result == true) {
      context.read<ChatBloc>().add(RefreshChannelsOnlyEvent());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post created successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  });
}

Future<void> handleLogout(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();

              // NOTE: We no longer clear read status on logout
              // Read status is now device-based, not user-based
              // This ensures unread messages persist across logins
              // await ChatService.clearReadStatusOnLogout();

              if (!context.mounted) return;

              context.read<AuthBloc>().add(LogoutEvent());
              Navigator.of(context).pushReplacementNamed('/welcome');
            },
            child: const Text('Logout'),
          ),
        ],
      );
    },
  );
}

String _resolveUserId(BuildContext context, String currentUserId) {
  if (currentUserId.isNotEmpty) {
    return currentUserId;
  }

  final authState = context.read<AuthBloc>().state;
  if (authState is AuthAuthenticatedState && authState.userProfile != null) {
    return authState.userProfile!.id;
  }

  return '';
}

