// lib/modules/chat/widgets/channels_list.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/chat/models/chat_channel.dart';
import 'package:mvc_app/modules/chat/chat_bloc.dart';
import 'package:mvc_app/modules/chat/chat_service.dart';
import 'package:mvc_app/services/notification_preferences_service.dart';
import 'package:mvc_app/services/read_status_service.dart';
import 'package:mvc_app/utils/profile_utils.dart';

class ChannelsList extends StatelessWidget {
  final TextEditingController searchController;
  final double breakpoint;
  final AppThemeMode theme;
  final VoidCallback? onExplorePressed; // Add this callback

  const ChannelsList({
    super.key,
    required this.searchController,
    required this.breakpoint,
    required this.theme,
    this.onExplorePressed, // Add this parameter
  });

  bool get _hasActiveFilter => searchController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      builder: (context, state) {
        if (state is ChatLoadedState) {
          final channels = state
              .channels; // Use channels directly from state (already filtered and sorted)

          return Column(
            children: [
              // Filter info bar
              if (_hasActiveFilter)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: Colors.orange.shade100,
                  child: Row(
                    children: [
                      Icon(
                        Icons.filter_alt,
                        size: 16,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Filtering channels by "${searchController.text}" - ${channels.length} result${channels.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.clear,
                          size: 16,
                          color: Colors.orange.shade700,
                        ),
                        onPressed: () {
                          searchController.clear();
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                      ),
                    ],
                  ),
                ),

              // Channels list
              Expanded(child: _buildChannelsListView(channels, state, context)),
            ],
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildChannelsListView(
    List<ChatChannel> channels,
    ChatLoadedState state,
    BuildContext context,
  ) {
    if (channels.isEmpty && _hasActiveFilter) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No channels match your search',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    if (channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 24),
            Text(
              "You haven't followed any channel yet",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Explore channels to start following',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 180,
              child: FloatingActionButton.extended(
                onPressed: onExplorePressed, // Use the callback here
                label: const Text('Let\'s explore'),
                icon: const Icon(Icons.arrow_circle_down_rounded),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        context.read<ChatBloc>().add(LoadChannelsEvent());
      },
      child: ListView.separated(
        itemCount: channels.length,
        separatorBuilder: (context, index) =>
            const Divider(height: 1, color: AppTheme.dividerBackground),
        itemBuilder: (context, index) {
          final channel = channels[index];
          return ChannelListItem(
            channel: channel,
            state: state,
            breakpoint: breakpoint,
            theme: theme,
          );
        },
      ),
    );
  }
}

class ChannelListItem extends StatefulWidget {
  final ChatChannel channel;
  final ChatLoadedState state;
  final double breakpoint;
  final AppThemeMode theme;

  const ChannelListItem({
    super.key,
    required this.channel,
    required this.state,
    required this.breakpoint,
    required this.theme,
  });

  @override
  State<ChannelListItem> createState() => _ChannelListItemState();
}

class _ChannelListItemState extends State<ChannelListItem> {
  final _notificationService = NotificationPreferencesService.instance;
  bool _isNotificationEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationState();
  }

  Future<void> _loadNotificationState() async {
    final enabled = await _notificationService.isChannelNotificationEnabled(
      widget.channel.id,
    );
    if (mounted) {
      setState(() {
        _isNotificationEnabled = enabled;
      });
    }
  }

  Future<void> _toggleNotification() async {
    await _notificationService.toggleChannelNotification(widget.channel.id);
    await _loadNotificationState();

    if (mounted) {
      // Show feedback snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                _isNotificationEnabled
                    ? Icons.notifications_active
                    : Icons.notifications_off,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _isNotificationEnabled
                      ? 'Notifications enabled for ${widget.channel.name}'
                      : 'Notifications muted for ${widget.channel.name}',
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _isNotificationEnabled
              ? Colors.green
              : Colors.orange,
        ),
      );
    }
  }

  void _showNotificationMenu(BuildContext context) {
    final isCurrentlyUnread = widget.channel.hasUnreadMessages;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mute/Unmute option
            ListTile(
              leading: Icon(
                _isNotificationEnabled
                    ? Icons.notifications_off
                    : Icons.notifications_active,
                color: _isNotificationEnabled ? Colors.orange : Colors.green,
              ),
              title: Text(
                _isNotificationEnabled
                    ? 'Mute notifications'
                    : 'Unmute notifications',
              ),
              subtitle: Text(
                _isNotificationEnabled
                    ? 'Stop receiving notifications from this channel'
                    : 'Receive notifications from this channel',
              ),
              onTap: () {
                Navigator.pop(context);
                _toggleNotification();
              },
            ),
            const Divider(),
            // Mark as read/unread option
            ListTile(
              leading: Icon(
                isCurrentlyUnread ? Icons.done_all : Icons.markunread,
                color: isCurrentlyUnread ? Colors.green : Colors.blue,
              ),
              title: Text(
                isCurrentlyUnread ? 'Mark as read' : 'Mark as unread',
              ),
              subtitle: Text(
                isCurrentlyUnread
                    ? 'Mark all messages in this channel as read'
                    : 'Mark this channel as unread',
              ),
              onTap: () {
                Navigator.pop(context);
                _toggleReadStatus();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleReadStatus() async {
    final readStatusService = ReadStatusService.instance;
    final chatService = ChatService();
    final isCurrentlyUnread = widget.channel.hasUnreadMessages;

    if (isCurrentlyUnread) {
      // Mark as read
      await readStatusService.markChannelAsRead(widget.channel.organizationId);
    } else {
      // Mark as unread by clearing the read status
      await readStatusService.clearChannelReadStatus(widget.channel.organizationId);
    }

    // Update badge immediately with new count
    if (mounted) {
      final chatState = context.read<ChatBloc>().state;
      if (chatState is ChatLoadedState) {
        // Recalculate unread status for all channels immediately
        final updatedChannels = await chatService.refreshAllChannelsUnreadStatus(
          chatState.allChannels,
        );

        // Update badge with the new counts
        await ChatService.updateNotificationBadgeFromChannels(updatedChannels);
      }

      // Refresh channels to update UI
      context.read<ChatBloc>().add(LoadChannelsEvent());

      // Show feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isCurrentlyUnread ? Icons.done_all : Icons.markunread,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isCurrentlyUnread
                      ? 'Marked ${widget.channel.name} as read'
                      : 'Marked ${widget.channel.name} as unread',
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isCurrentlyUnread ? Colors.green : Colors.blue,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.state.selectedChannel?.id == widget.channel.id;
    final isCurrentlyUnread = widget.channel.hasUnreadMessages;

    return Dismissible(
      key: Key('channel_${widget.channel.id}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          // Swipe left: Toggle mute/unmute
          await _toggleNotification();
        } else if (direction == DismissDirection.startToEnd) {
          // Swipe right: Toggle read/unread status
          await _toggleReadStatus();
        }
        return false; // Return false to prevent dismissal
      },
      // Swipe right background (mark as read/unread)
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: isCurrentlyUnread ? Colors.green : Colors.blue,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isCurrentlyUnread ? Icons.done_all : Icons.markunread,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              isCurrentlyUnread ? 'Mark as read' : 'Mark as unread',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      // Swipe left background (mute/unmute)
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: _isNotificationEnabled ? Colors.orange : Colors.green,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isNotificationEnabled
                  ? Icons.notifications_off
                  : Icons.notifications_active,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              _isNotificationEnabled ? 'Mute' : 'Unmute',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      child: ListTile(
        leading: ChannelAvatar(channel: widget.channel),
        title: Text(
          widget.channel.name,
          style: AppTheme.chatTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // !important! Here is where the last message is shown in the chat list
        subtitle: widget.channel.lastMessage != null
            ? Text(
                widget.channel.lastMessage!.displayContent,
                style: AppTheme.chatMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : Text(
                'No messages yet',
                style: AppTheme.chatMessage.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.channel.lastMessage != null)
              Text(
                widget.channel.lastMessage!.timeDisplay,
                style: AppTheme.chatTimestamp,
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.channel.hasUnreadMessages) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppTheme.accentSecondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(
                  _isNotificationEnabled
                      ? Icons.notifications
                      : Icons.notifications_off,
                  size: 14,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ],
        ),
        selected: isSelected,
        selectedTileColor: AppTheme.cardGreyBackground,
        onTap: () async {
          // Check if profile needs completion before opening channel
          final canContinue = await ProfileUtils.showProfileCompletionBottomSheet(
            context,
            message: 'Please complete your profile to access channels and start chatting.',
          );

          if (canContinue) {
            // Only dispatch SelectChannelEvent if profile is complete
            // Navigation will be handled automatically by RealChatScreen
            if (context.mounted) {
              context.read<ChatBloc>().add(SelectChannelEvent(widget.channel));
            }
          }
        },
        onLongPress: () {
          _showNotificationMenu(context);
        },
      ),
    );
  }
}

class ChannelAvatar extends StatelessWidget {
  final ChatChannel channel;

  const ChannelAvatar({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    String? imageUrl;
    String fallbackText = channel.name.substring(0, 1).toUpperCase();
    print("TRYING to parse profile picture $imageUrl");

    if (channel.logoUrl != null) {
      imageUrl = channel.logoUrl;
    }

    if (imageUrl != null &&
        imageUrl.isNotEmpty &&
        Uri.tryParse(imageUrl) != null) {
      print("Parsed image OK");
      return CircleAvatar(
        backgroundColor: AppTheme.cardGreyBackground,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              width: 40,
              height: 40,
              color: AppTheme.accentSecondary,
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              width: 40,
              height: 40,
              color: AppTheme.accentSecondary,
              child: Text(
                fallbackText,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      );
    }

    print("Fail parsing image from ${channel.id}");
    return CircleAvatar(
      backgroundColor: AppTheme.accentSecondary,
      child: Text(fallbackText, style: const TextStyle(color: Colors.white)),
    );
  }
}
