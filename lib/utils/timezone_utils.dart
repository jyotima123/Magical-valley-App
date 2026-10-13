// lib/utils/timezone_utils.dart

/// Utility class for handling timezone conversions in the app
class TimezoneUtils {
  /// Converts a UTC DateTime to the user's local timezone
  static DateTime toLocalTime(DateTime utcDateTime) {
    // If the DateTime is already in local time, return it as is
    if (!utcDateTime.isUtc) {
      return utcDateTime;
    }

    // Convert UTC to local timezone
    return utcDateTime.toLocal();
  }

  /// Formats a relative time display (e.g., "2h ago", "3d ago") using local timezone
  static String formatRelativeTime(DateTime utcDateTime) {
    final localDateTime = toLocalTime(utcDateTime);
    final now = DateTime.now();
    final difference = now.difference(localDateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  /// Formats a date for dividers (Today, Yesterday, weekday, or MM/DD/YY) using local timezone
  static String formatDateDivider(DateTime utcDateTime) {
    final localDateTime = toLocalTime(utcDateTime);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(
      localDateTime.year,
      localDateTime.month,
      localDateTime.day,
    );

    if (messageDate == today) {
      return 'Today';
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else if (now.difference(localDateTime).inDays < 7) {
      // Within a week, show day name
      const weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      return weekdays[localDateTime.weekday - 1];
    } else {
      // Older than a week, show date in MM/DD/YY format
      final month = localDateTime.month.toString();
      final day = localDateTime.day.toString();
      final year = (localDateTime.year % 100)
          .toString(); // Get last 2 digits of year
      return '$month/$day/$year';
    }
  }

  /// Formats a full timestamp for detailed display (e.g., "Dec 15, 2023 at 2:30 PM")
  static String formatFullTimestamp(DateTime utcDateTime) {
    final localDateTime = toLocalTime(utcDateTime);

    const months = [
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

    final month = months[localDateTime.month - 1];
    final day = localDateTime.day;
    final year = localDateTime.year;

    // Format time in 12-hour format
    final hour = localDateTime.hour == 0
        ? 12
        : localDateTime.hour > 12
        ? localDateTime.hour - 12
        : localDateTime.hour;
    final minute = localDateTime.minute.toString().padLeft(2, '0');
    final period = localDateTime.hour >= 12 ? 'PM' : 'AM';

    return '$month $day, $year at $hour:$minute $period';
  }

  /// Gets the local timezone name/offset for display purposes
  static String getLocalTimezoneInfo() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;

    final hours = offset.inHours;
    final minutes = (offset.inMinutes % 60).abs();

    final sign = hours >= 0 ? '+' : '-';
    final hoursAbs = hours.abs();

    if (minutes == 0) {
      return 'UTC$sign$hoursAbs';
    } else {
      return 'UTC$sign$hoursAbs:${minutes.toString().padLeft(2, '0')}';
    }
  }
}
