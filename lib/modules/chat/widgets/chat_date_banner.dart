import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/chat/models/direct_message_item.dart';

/// Formats a UTC [DateTime] as a human-readable date label for chat separators.
String formatChatDateLabel(DateTime utcDate) {
  final local = utcDate.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final msgDay = DateTime(local.year, local.month, local.day);
  final diff = today.difference(msgDay).inDays;

  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) {
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return weekdays[local.weekday - 1];
  }
  return '${local.month}/${local.day}/${local.year}';
}

/// Builds a flat list of chat items interspersed with date-separator [DateTime]s.
/// Each [DateTime] entry represents the local calendar day of the messages that follow.
List<Object> buildChatItems(List<DirectMessageItem> messages) {
  final items = <Object>[];
  DateTime? lastDay;
  for (final message in messages) {
    final local = message.createdAt.toLocal();
    final msgDay = DateTime(local.year, local.month, local.day);
    if (lastDay == null || msgDay != lastDay) {
      items.add(msgDay);
      lastDay = msgDay;
    }
    items.add(message);
  }
  return items;
}

/// Compact date-pill separator shown between messages on different calendar days.
class ChatDateBanner extends StatelessWidget {
  final DateTime date;

  const ChatDateBanner({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.secondaryHeadingColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            formatChatDateLabel(date),
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.secondaryHeadingColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
