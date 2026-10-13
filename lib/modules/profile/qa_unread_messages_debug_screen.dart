// lib/modules/profile/qa_unread_messages_debug_screen.dart
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/chat/chat_bloc.dart';
import 'package:mvc_app/modules/chat/models/chat_channel.dart';
import 'package:mvc_app/services/read_status_service.dart';
import 'package:mvc_app/services/fcm_service.dart';
import 'dart:io';

class QAUnreadMessagesDebugScreen extends StatefulWidget {
  const QAUnreadMessagesDebugScreen({super.key});

  @override
  State<QAUnreadMessagesDebugScreen> createState() =>
      _QAUnreadMessagesDebugScreenState();
}

class _QAUnreadMessagesDebugScreenState
    extends State<QAUnreadMessagesDebugScreen> {
  Map<String, DateTime?> _readStatuses = {};

  @override
  void initState() {
    super.initState();
    _loadReadStatuses();
    // Load channels if not already loaded
    context.read<ChatBloc>().add(LoadChannelsEvent());
  }

  Future<void> _loadReadStatuses() async {
    try {
      final readStatusService = ReadStatusService.instance;
      final statuses = await readStatusService.getAllReadStatuses();
      setState(() {
        _readStatuses = statuses;
      });
    } catch (e) {
      // Error loading read statuses - continue with empty map
    }
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Never';
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      // Format: "Jan 15, 2024 14:30"
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final month = months[dateTime.month - 1];
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$month ${dateTime.day}, ${dateTime.year} $hour:$minute';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Future<void> _updateBadgeCount(int count) async {
    try {
      AppBadgePlus.updateBadge(count);
      // final fcmService = FCMService.instance;
      // await fcmService.updateNotificationBadge(count: count);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Badge updated to $count'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update badge: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildBadgeUpdateCard(int totalUnreadCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.headerBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.notifications_active,
                  color: Colors.orange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'iOS Badge Count',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      totalUnreadCount.toString(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _updateBadgeCount(totalUnreadCount),
                  icon: const Icon(Icons.update, size: 18),
                  label: const Text('Update Badge'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _updateBadgeCount(0),
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('Clear Badge'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Colors.orange),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('QA: Unread Messages Debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<ChatBloc>().add(LoadChannelsEvent());
              _loadReadStatuses();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: BlocBuilder<ChatBloc, ChatState>(
        builder: (context, state) {
          if (state is ChatLoadingState) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is ChatErrorState) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: ${state.error}'),
                  ElevatedButton(
                    onPressed: () {
                      context.read<ChatBloc>().add(LoadChannelsEvent());
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (state is ChatLoadedState) {
            final channels = state.allChannels;
            final unreadChannels = channels
                .where((c) => c.hasUnreadMessages)
                .toList();
            final readChannels = channels
                .where((c) => !c.hasUnreadMessages)
                .toList();

            // Calculate total unread messages count
            // final totalUnreadCount = channels.fold<int>(
            //   0,
            //   (sum, channel) => sum + channel.unreadCount,
            // );

            final totalUnreadCount = unreadChannels
                .where((c) => c.isFollowed)
                .length
                .toInt();

            return RefreshIndicator(
              onRefresh: () async {
                context.read<ChatBloc>().add(LoadChannelsEvent());
                await _loadReadStatuses();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Badge Update Card (iOS only)
                    if (Platform.isIOS) ...[
                      _buildBadgeUpdateCard(totalUnreadCount),
                      const SizedBox(height: 12),
                    ],
                    // Summary Cards
                    _buildSummaryCard(
                      'Total Channels',
                      channels.length.toString(),
                      Icons.chat_bubble_outline,
                      Colors.blueGrey,
                    ),
                    _buildSummaryCard(
                      'Total Followed Channels',
                      channels.where((c) => c.isFollowed).length.toString(),
                      Icons.chat_bubble_outline,
                      Colors.blue,
                    ),
                    const SizedBox(height: 12),
                    _buildSummaryCard(
                      'Unread and followed Channels',
                      unreadChannels
                          .where((c) => c.isFollowed)
                          .length
                          .toString(),
                      Icons.mark_chat_unread,
                      Colors.red,
                    ),
                    const SizedBox(height: 12),
                    _buildSummaryCard(
                      'Read and followed Channels',
                      readChannels.where((c) => c.isFollowed).length.toString(),
                      Icons.mark_chat_read,
                      Colors.green,
                    ),
                    const SizedBox(height: 24),

                    // Unread Channels Section
                    if (unreadChannels.isNotEmpty) ...[
                      _buildSectionHeader('Unread Channels', Colors.red),
                      const SizedBox(height: 12),
                      ...unreadChannels.map(
                        (channel) => _buildChannelCard(channel, true),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Read Channels Section
                    if (readChannels.isNotEmpty) ...[
                      _buildSectionHeader('Read Channels', Colors.green),
                      const SizedBox(height: 12),
                      ...readChannels.map(
                        (channel) => _buildChannelCard(channel, false),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return const Center(child: Text('No data available'));
        },
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.headerBackground,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildChannelCard(ChatChannel channel, bool isUnread) {
    final lastReadTime = _readStatuses[channel.organizationId];
    final lastMessageTime = channel.lastMessage?.createdAt;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.headerBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUnread
              ? Colors.red.withOpacity(0.3)
              : Colors.green.withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Channel Logo or Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (isUnread ? Colors.red : Colors.green).withOpacity(
                    0.1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: channel.logoUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          channel.logoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.business,
                              color: isUnread ? Colors.red : Colors.green,
                            );
                          },
                        ),
                      )
                    : Icon(
                        Icons.business,
                        color: isUnread ? Colors.red : Colors.green,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            channel.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: (isUnread ? Colors.red : Colors.green)
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isUnread ? 'UNREAD' : 'READ',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isUnread ? Colors.red : Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${channel.organizationId}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Last Message Info
          if (lastMessageTime != null) ...[
            _buildInfoRow(
              Icons.message,
              'Last Message',
              _formatDateTime(lastMessageTime),
              Colors.blue,
            ),
            const SizedBox(height: 8),
          ],
          // Last Read Info
          _buildInfoRow(
            Icons.check_circle,
            'Last Read',
            _formatDateTime(lastReadTime),
            isUnread ? Colors.orange : Colors.green,
          ),
          // Unread Count
          if (channel.unreadCount > 0) ...[
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.numbers,
              'Unread Count',
              channel.unreadCount.toString(),
              Colors.red,
            ),
          ],
          // Followed Status
          const SizedBox(height: 8),
          _buildInfoRow(
            channel.isFollowed ? Icons.favorite : Icons.favorite_border,
            'Followed',
            channel.isFollowed ? 'Yes' : 'No',
            channel.isFollowed ? Colors.pink : Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
