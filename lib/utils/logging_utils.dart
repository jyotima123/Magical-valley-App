// lib/utils/logging_utils.dart
// Comprehensive logging utility with colors and different log levels

import 'dart:developer' as developer;
import 'dart:io';

/// ANSI color codes for terminal output
class _AnsiColors {
  static const String reset = '\x1B[0m';
  static const String black = '\x1B[30m';
  static const String red = '\x1B[31m';
  static const String green = '\x1B[32m';
  static const String yellow = '\x1B[33m';
  static const String blue = '\x1B[34m';
  static const String magenta = '\x1B[35m';
  static const String cyan = '\x1B[36m';
  static const String white = '\x1B[37m';
  static const String orange = '\x1B[38;5;208m';
  static const String purple = '\x1B[38;5;129m';
  static const String pink = '\x1B[38;5;205m';
  static const String lime = '\x1B[38;5;154m';

  // Bright colors
  static const String brightRed = '\x1B[91m';
  static const String brightGreen = '\x1B[92m';
  // static const String brightYellow = '\x1B[93m';
  static const String brightBlue = '\x1B[94m';
  // static const String brightMagenta = '\x1B[95m';
  // static const String brightCyan = '\x1B[96m';

  // Background colors
  static const String bgRed = '\x1B[41m';
  // static const String bgGreen = '\x1B[42m';
  // static const String bgYellow = '\x1B[43m';
  // static const String bgBlue = '\x1B[44m';

  // Text styles
  static const String bold = '\x1B[1m';
  static const String dim = '\x1B[2m';
  // static const String italic = '\x1B[3m';
  // static const String underline = '\x1B[4m';
}

/// Log levels for filtering
enum LogLevel {
  debug(0),
  info(1),
  warning(2),
  error(3),
  critical(4);

  const LogLevel(this.value);
  final int value;
}

/// Main logging utility class
class AppLogger {
  static LogLevel _minLogLevel = LogLevel.debug;
  static bool _enableColors = true;
  static bool _enableTimestamps = true;
  static bool _enableFileInfo = true;
  static String _loggerName = 'MVC_APP';

  /// Configure the logger
  static void configure({
    LogLevel minLogLevel = LogLevel.debug,
    bool enableColors = true,
    bool enableTimestamps = true,
    bool enableFileInfo = true,
    String loggerName = 'MVC_APP',
  }) {
    _minLogLevel = minLogLevel;
    _enableColors =
        enableColors && Platform.isIOS ||
        Platform.isAndroid ||
        Platform.isMacOS;
    _enableTimestamps = enableTimestamps;
    _enableFileInfo = enableFileInfo;
    _loggerName = loggerName;
  }

  /// Internal logging method
  static void _log(
    String message,
    LogLevel level,
    String color,
    String emoji, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.value < _minLogLevel.value) return;

    final timestamp = _enableTimestamps
        ? DateTime.now().toIso8601String().substring(11, 23)
        : '';

    final tagStr = tag != null ? '[$tag] ' : '';
    final timestampStr = timestamp.isNotEmpty ? '[$timestamp] ' : '';

    String formattedMessage;
    if (_enableColors) {
      formattedMessage =
          '$color$emoji $timestampStr$tagStr$message${_AnsiColors.reset}';
    } else {
      formattedMessage = '$emoji $timestampStr$tagStr$message';
    }

    // Use developer.log for better performance and no truncation
    developer.log(
      formattedMessage,
      name: _loggerName,
      level: level.value * 300, // Convert to developer log levels
      error: error,
      stackTrace: stackTrace,
    );
  }
}

// ============================================================================
// COLORED LOGGING FUNCTIONS
// ============================================================================

/// Debug logging (gray/dim)
void debugLog(
  String message, {
  String? tag,
  Object? error,
  StackTrace? stackTrace,
}) {
  AppLogger._log(
    message,
    LogLevel.debug,
    _AnsiColors.dim,
    '🔍',
    tag: tag,
    error: error,
    stackTrace: stackTrace,
  );
}

/// Info logging (blue)
void infoLog(
  String message, {
  String? tag,
  Object? error,
  StackTrace? stackTrace,
}) {
  AppLogger._log(
    message,
    LogLevel.info,
    _AnsiColors.blue,
    'ℹ️',
    tag: tag,
    error: error,
    stackTrace: stackTrace,
  );
}

/// Success logging (green)
void successLog(
  String message, {
  String? tag,
  Object? error,
  StackTrace? stackTrace,
}) {
  AppLogger._log(
    message,
    LogLevel.info,
    _AnsiColors.green,
    '✅',
    tag: tag,
    error: error,
    stackTrace: stackTrace,
  );
}

/// Warning logging (yellow/orange)
void warningLog(
  String message, {
  String? tag,
  Object? error,
  StackTrace? stackTrace,
}) {
  AppLogger._log(
    message,
    LogLevel.warning,
    _AnsiColors.yellow,
    '⚠️',
    tag: tag,
    error: error,
    stackTrace: stackTrace,
  );
}

/// Error logging (red)
void errorLog(
  String message, {
  String? tag,
  Object? error,
  StackTrace? stackTrace,
}) {
  AppLogger._log(
    message,
    LogLevel.error,
    _AnsiColors.red,
    '❌',
    tag: tag,
    error: error,
    stackTrace: stackTrace,
  );
}

/// Critical error logging (bright red with background)
void criticalLog(
  String message, {
  String? tag,
  Object? error,
  StackTrace? stackTrace,
}) {
  AppLogger._log(
    message,
    LogLevel.critical,
    '${_AnsiColors.bgRed}${_AnsiColors.white}${_AnsiColors.bold}',
    '🚨',
    tag: tag,
    error: error,
    stackTrace: stackTrace,
  );
}

// ============================================================================
// COLORED DEBUG FUNCTIONS (as requested)
// ============================================================================

/// Green debug logging
void debugLogGreen(String message, {String? tag}) {
  AppLogger._log(message, LogLevel.debug, _AnsiColors.green, '🟢', tag: tag);
}

/// Blue debug logging
void debugLogBlue(String message, {String? tag}) {
  AppLogger._log(message, LogLevel.debug, _AnsiColors.blue, '🔵', tag: tag);
}

/// Orange debug logging
void debugLogOrange(String message, {String? tag}) {
  AppLogger._log(message, LogLevel.debug, _AnsiColors.orange, '🟠', tag: tag);
}

/// Red debug logging
void debugLogRed(String message, {String? tag}) {
  AppLogger._log(message, LogLevel.debug, _AnsiColors.red, '🔴', tag: tag);
}

/// Yellow debug logging
void debugLogYellow(String message, {String? tag}) {
  AppLogger._log(message, LogLevel.debug, _AnsiColors.yellow, '🟡', tag: tag);
}

/// Purple debug logging
void debugLogPurple(String message, {String? tag}) {
  AppLogger._log(message, LogLevel.debug, _AnsiColors.purple, '🟣', tag: tag);
}

/// Pink debug logging
void debugLogPink(String message, {String? tag}) {
  AppLogger._log(message, LogLevel.debug, _AnsiColors.pink, '🩷', tag: tag);
}

/// Cyan debug logging
void debugLogCyan(String message, {String? tag}) {
  AppLogger._log(message, LogLevel.debug, _AnsiColors.cyan, '🔷', tag: tag);
}

/// Lime debug logging
void debugLogLime(String message, {String? tag}) {
  AppLogger._log(message, LogLevel.debug, _AnsiColors.lime, '🟢', tag: tag);
}

/// Magenta debug logging
void debugLogMagenta(String message, {String? tag}) {
  AppLogger._log(message, LogLevel.debug, _AnsiColors.magenta, '🟪', tag: tag);
}

// ============================================================================
// SPECIALIZED LOGGING FUNCTIONS
// ============================================================================

/// API request logging
void apiRequestLog(
  String method,
  String endpoint, {
  Map<String, dynamic>? data,
  String? tag,
}) {
  final dataStr = data != null ? '\nData: ${data.toString()}' : '';
  AppLogger._log(
    '$method $endpoint$dataStr',
    LogLevel.info,
    _AnsiColors.cyan,
    '🌐',
    tag: tag ?? 'API',
  );
}

/// API response logging
void apiResponseLog(String endpoint, {dynamic response, String? tag}) {
  final responseStr = response != null
      ? '\nResponse: ${response.toString()}'
      : '';
  AppLogger._log(
    'Response from $endpoint$responseStr',
    LogLevel.info,
    _AnsiColors.green,
    '📥',
    tag: tag ?? 'API',
  );
}

/// API error logging
void apiErrorLog(String endpoint, dynamic error, {String? tag}) {
  AppLogger._log(
    'API Error at $endpoint: $error',
    LogLevel.error,
    _AnsiColors.red,
    '🚨',
    tag: tag ?? 'API',
    error: error,
  );
}

/// Authentication logging
void authLog(String message, {String? tag}) {
  AppLogger._log(
    message,
    LogLevel.info,
    _AnsiColors.blue,
    '🔐',
    tag: tag ?? 'AUTH',
  );
}

/// Database logging
void dbLog(String message, {String? tag}) {
  AppLogger._log(
    message,
    LogLevel.info,
    _AnsiColors.purple,
    '🗄️',
    tag: tag ?? 'DB',
  );
}

/// Network logging
void networkLog(String message, {String? tag}) {
  AppLogger._log(
    message,
    LogLevel.info,
    _AnsiColors.cyan,
    '🌍',
    tag: tag ?? 'NETWORK',
  );
}

/// Performance logging
void performanceLog(String message, {String? tag}) {
  AppLogger._log(
    message,
    LogLevel.info,
    _AnsiColors.orange,
    '⚡',
    tag: tag ?? 'PERF',
  );
}

/// Navigation logging
void navigationLog(String message, {String? tag}) {
  AppLogger._log(
    message,
    LogLevel.info,
    _AnsiColors.magenta,
    '🧭',
    tag: tag ?? 'NAV',
  );
}

/// UI logging
void uiLog(String message, {String? tag}) {
  AppLogger._log(
    message,
    LogLevel.info,
    _AnsiColors.brightBlue,
    '🎨',
    tag: tag ?? 'UI',
  );
}

/// Business logic logging
void businessLog(String message, {String? tag}) {
  AppLogger._log(
    message,
    LogLevel.info,
    _AnsiColors.brightGreen,
    '💼',
    tag: tag ?? 'BUSINESS',
  );
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/// Log a separator line
void logSeparator({String char = '=', int length = 50, String color = ''}) {
  final separator = char * length;
  final colorCode = color.isNotEmpty ? color : _AnsiColors.dim;
  AppLogger._log(separator, LogLevel.debug, colorCode, '');
}

/// Log a section header
void logSection(String title, {String color = ''}) {
  final colorCode = color.isNotEmpty ? color : _AnsiColors.bold;
  logSeparator(char: '=', color: colorCode);
  AppLogger._log(title.toUpperCase(), LogLevel.info, colorCode, '📋');
  logSeparator(char: '=', color: colorCode);
}

/// Log JSON data in a formatted way
void logJson(String title, Map<String, dynamic> data, {String? tag}) {
  AppLogger._log(
    '$title:\n${_formatJson(data)}',
    LogLevel.debug,
    _AnsiColors.cyan,
    '📄',
    tag: tag,
  );
}

/// Format JSON for better readability
String _formatJson(Map<String, dynamic> json) {
  final buffer = StringBuffer();
  _formatJsonRecursive(json, buffer, 0);
  return buffer.toString();
}

void _formatJsonRecursive(dynamic obj, StringBuffer buffer, int indent) {
  final indentStr = '  ' * indent;

  if (obj is Map<String, dynamic>) {
    buffer.writeln('{');
    final entries = obj.entries.toList();
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      buffer.write('$indentStr  "${entry.key}": ');
      _formatJsonRecursive(entry.value, buffer, indent + 1);
      if (i < entries.length - 1) buffer.write(',');
      buffer.writeln();
    }
    buffer.write('$indentStr}');
  } else if (obj is List) {
    buffer.writeln('[');
    for (int i = 0; i < obj.length; i++) {
      buffer.write('$indentStr  ');
      _formatJsonRecursive(obj[i], buffer, indent + 1);
      if (i < obj.length - 1) buffer.write(',');
      buffer.writeln();
    }
    buffer.write('$indentStr]');
  } else if (obj is String) {
    buffer.write('"$obj"');
  } else {
    buffer.write(obj.toString());
  }
}

// ============================================================================
// CONDITIONAL LOGGING (based on build mode)
// ============================================================================

/// Log only in debug mode
void debugOnlyLog(String message, {String? tag}) {
  assert(() {
    debugLog(message, tag: tag);
    return true;
  }());
}

/// Log only in release mode
void releaseOnlyLog(String message, {String? tag}) {
  if (const bool.fromEnvironment('dart.vm.product')) {
    infoLog(message, tag: tag);
  }
}

// ============================================================================
// USAGE EXAMPLES (commented out)
// ============================================================================

/*
// Basic usage examples:

void exampleUsage() {
  // Configure logger (optional, call once at app startup)
  AppLogger.configure(
    minLogLevel: LogLevel.debug,
    enableColors: true,
    enableTimestamps: true,
    loggerName: 'MVC_APP',
  );
  
  // Basic logging
  debugLog('This is a debug message');
  infoLog('This is an info message');
  successLog('Operation completed successfully');
  warningLog('This is a warning');
  errorLog('This is an error');
  criticalLog('This is a critical error');
  
  // Colored debug logging
  debugLogGreen('Success operation');
  debugLogBlue('Information');
  debugLogOrange('Warning state');
  debugLogRed('Error state');
  debugLogYellow('Attention needed');
  debugLogPurple('Special case');
  debugLogPink('Highlight');
  debugLogCyan('Data flow');
  
  // Specialized logging
  apiRequestLog('POST', '/api/users', data: {'name': 'John'});
  apiResponseLog('/api/users', response: {'id': 1, 'name': 'John'});
  apiErrorLog('/api/users', 'Network timeout');
  authLog('User signed in successfully');
  dbLog('Database connection established');
  networkLog('Network request completed');
  performanceLog('Operation took 150ms');
  navigationLog('Navigated to home screen');
  uiLog('Button pressed');
  businessLog('Order processed');
  
  // Utility functions
  logSection('USER AUTHENTICATION');
  logSeparator();
  logJson('User Data', {'id': 1, 'name': 'John', 'email': 'john@example.com'});
  
  // Conditional logging
  debugOnlyLog('This only shows in debug builds');
  releaseOnlyLog('This only shows in release builds');
}
*/
