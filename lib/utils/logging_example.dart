// lib/utils/logging_example.dart
// Example usage of the new logging utilities

import 'package:mvc_app/utils/logging_utils.dart';

/// Example class showing how to use the new logging functions
class LoggingExample {
  /// Initialize the logger (call this once at app startup)
  static void initializeLogging() {
    AppLogger.configure(
      minLogLevel: LogLevel.debug,
      enableColors: true,
      enableTimestamps: true,
      loggerName: 'MVC_APP',
    );

    successLog('Logging system initialized successfully!', tag: 'INIT');
  }

  /// Example of basic logging functions
  static void demonstrateBasicLogging() {
    logSection('BASIC LOGGING EXAMPLES');

    debugLog('This is a debug message');
    infoLog('This is an info message');
    successLog('Operation completed successfully');
    warningLog('This is a warning');
    errorLog('This is an error');
    criticalLog('This is a critical error');
  }

  /// Example of colored debug logging
  static void demonstrateColoredLogging() {
    logSection('COLORED DEBUG LOGGING');

    debugLogGreen('Success operation');
    debugLogBlue('Information');
    debugLogOrange('Warning state');
    debugLogRed('Error state');
    debugLogYellow('Attention needed');
    debugLogPurple('Special case');
    debugLogPink('Highlight');
    debugLogCyan('Data flow');
    debugLogLime('Positive feedback');
    debugLogMagenta('Special highlight');
  }

  /// Example of specialized logging
  static void demonstrateSpecializedLogging() {
    logSection('SPECIALIZED LOGGING');

    // API logging
    apiRequestLog(
      'POST',
      '/api/users',
      data: {'name': 'John', 'email': 'john@example.com'},
    );
    apiResponseLog(
      '/api/users',
      response: {'id': 1, 'name': 'John', 'created': true},
    );
    apiErrorLog('/api/users', 'Network timeout occurred');

    // Authentication logging
    authLog('User signed in successfully');
    authLog('Password reset requested');

    // Database logging
    dbLog('Database connection established');
    dbLog('Query executed successfully');

    // Network logging
    networkLog('Network request completed');
    networkLog('Connection restored');

    // Performance logging
    performanceLog('Operation took 150ms');
    performanceLog('Cache hit ratio: 85%');

    // Navigation logging
    navigationLog('Navigated to home screen');
    navigationLog('Back button pressed');

    // UI logging
    uiLog('Button pressed');
    uiLog('Form submitted');

    // Business logic logging
    businessLog('Order processed');
    businessLog('Payment completed');
  }

  /// Example of utility functions
  static void demonstrateUtilityFunctions() {
    logSection('UTILITY FUNCTIONS');

    // JSON logging
    final userData = {
      'id': 1,
      'name': 'John Doe',
      'email': 'john@example.com',
      'preferences': {'theme': 'dark', 'notifications': true, 'language': 'en'},
      'roles': ['user', 'admin'],
    };

    logJson('User Data', userData);

    // Separators
    logSeparator();
    logSeparator(char: '-', length: 30);

    // Conditional logging
    debugOnlyLog('This only shows in debug builds');
    releaseOnlyLog('This only shows in release builds');
  }

  /// Example of error logging with context
  static void demonstrateErrorLogging() {
    logSection('ERROR LOGGING WITH CONTEXT');

    try {
      // Simulate an error
      throw Exception('Something went wrong');
    } catch (e, stackTrace) {
      errorLog(
        'Failed to process user data',
        tag: 'USER_SERVICE',
        error: e,
        stackTrace: stackTrace,
      );
    }

    // API error example
    apiErrorLog('/api/orders', 'Connection timeout after 30 seconds');

    // Critical error example
    criticalLog('Database connection lost - immediate attention required!');
  }

  /// Example of replacing old print statements
  static void oldVsNewLogging() {
    logSection('OLD VS NEW LOGGING COMPARISON');

    // OLD WAY (what we replaced):
    // print("getUserProfile");
    // print('🔐 DEBUG AUTH REQUEST: ...');
    // print('DEBUG: Getting admin organizations for user: $userId');
    // print('Error getting current user: $e');

    // NEW WAY (what we use now):
    debugLogCyan("getUserProfile", tag: "API");
    authLog('AUTH REQUEST: getCurrentUser');
    debugLogOrange(
      'Getting admin organizations for user: user123',
      tag: "ADMIN",
    );
    errorLog('Error getting current user: Network timeout', tag: "AUTH");

    successLog('All print statements have been replaced with proper logging!');
  }

  /// Run all examples
  static void runAllExamples() {
    initializeLogging();

    demonstrateBasicLogging();
    demonstrateColoredLogging();
    demonstrateSpecializedLogging();
    demonstrateUtilityFunctions();
    demonstrateErrorLogging();
    oldVsNewLogging();

    logSection('LOGGING EXAMPLES COMPLETED');
    successLog('All logging examples have been demonstrated!');
  }
}

// Uncomment the line below to run examples when this file is imported
// final _ = LoggingExample.runAllExamples();
