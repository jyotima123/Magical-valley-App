// lib/services/api/supabase_api_service.dart
// Supabase implementation of the API service

import 'dart:async' show StreamSubscription, TimeoutException;
import 'dart:convert';
import 'dart:io' show Platform, SocketException;
import 'dart:typed_data' show Uint8List;
import 'package:crypto/crypto.dart' show sha256;
import 'package:mvc_app/flavour_config.dart';
import 'package:mvc_app/modules/auth/auth_state.dart' hide AuthState;
import 'package:mvc_app/modules/cars/vehicle_inquiry_conversation.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:mvc_app/modules/chat/models/chat_message.dart';
import 'package:mvc_app/modules/chat/models/direct_message_conversation.dart';
import 'package:mvc_app/modules/chat/models/direct_message_item.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';
import 'package:mvc_app/modules/chat/models/post_reactions_model.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/api_service.dart';
import 'package:mvc_app/services/models/feature_flags.dart';
import 'package:mvc_app/utils/logging_utils.dart';
import 'package:mvc_app/services/amplitude_service.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Custom error types for better error handling
enum ApiErrorType {
  authentication,
  authorization,
  validation,
  network,
  server,
  database,
  unknown,
}

class ApiError {
  final ApiErrorType type;
  final String code;
  final String message;
  final String? details;
  final Map<String, dynamic>? metadata;

  const ApiError({
    required this.type,
    required this.code,
    required this.message,
    this.details,
    this.metadata,
  });

  @override
  String toString() => 'ApiError($type): $message';
}

typedef AuthStateCallback =
    void Function(AuthState authState, Session? session);
AuthStateCallback? _onAuthStateChanged;

class SupabaseApiService implements ApiService {
  static SupabaseApiService? _instance;
  late SupabaseClient _client;

  StreamSubscription<AuthState>? _authStateSubscription;

  // Debug flag - can be set based on environment or configuration
  static const bool DEBUG = true; // Set to false for production

  SupabaseApiService._internal();

  static SupabaseApiService get instance {
    _instance ??= SupabaseApiService._internal();
    return _instance!;
  }

  static GoTrueClient get auth {
    // _instance ??= SupabaseApiService._internal();
    return _instance!._client.auth;
  }

  @override
  Future<AuthResult?> getCurrentUser() async {
    debugLogBlue("getCurrentUser", tag: "AUTH");
    try {
      if (DEBUG) {
        authLog(
          'AUTH REQUEST: ${jsonEncode({'operation': 'getCurrentUser', 'timestamp': DateTime.now().toUtc().toIso8601String()})}',
        );
      }

      // Check if there's already a current user.
      final currentUser = _client.auth.currentUser;
      if (currentUser != null) {
        // currentUser can be non-null (loaded from cache) while currentSession
        // is null — e.g. when the access token expired and auto-refresh hasn't
        // fired yet. Calling updateUser() or any RPC in that window throws
        // AuthSessionMissingException (BUG-004 / BUG-005).
        if (_client.auth.currentSession != null) {
          return AuthResult.success(
            userId: currentUser.id,
            email: currentUser.email,
            userData: {
              ...?currentUser.userMetadata,
              'app_metadata': currentUser.appMetadata,
              'phone_confirmed_at': currentUser.phoneConfirmedAt,
            },
          );
        }

        // Session is null but user is cached — try to refresh before giving up.
        try {
          await _client.auth.refreshSession();
          final refreshedUser = _client.auth.currentUser;
          if (refreshedUser != null) {
            return AuthResult.success(
              userId: refreshedUser.id,
              email: refreshedUser.email,
              userData: {
                ...?refreshedUser.userMetadata,
                'app_metadata': refreshedUser.appMetadata,
                'phone_confirmed_at': refreshedUser.phoneConfirmedAt,
              },
            );
          }
        } catch (refreshError) {
          warningLog(
            'Session refresh failed (user cached but session missing): $refreshError',
            tag: "AUTH",
          );
        }

        return null;
      }

      // No cached user — try a full session refresh.
      try {
        await _client.auth.refreshSession();

        final user = _client.auth.currentUser;
        if (user != null) {
          return AuthResult.success(
            userId: user.id,
            email: user.email,
            userData: {
              ...?user.userMetadata,
              'app_metadata': user.appMetadata,
              'phone_confirmed_at': user.phoneConfirmedAt,
            },
          );
        }
      } catch (refreshError) {
        // If refresh fails, it's likely there's no session to refresh
        warningLog(
          'Session refresh failed (expected if no session): $refreshError',
          tag: "AUTH",
        );
      }

      return null;
    } catch (e) {
      _logError('getCurrentUser', e);
      errorLog('Error getting current user: $e', tag: "AUTH");
      return null;
    }
  }

  // void setupAuthStateListener(AuthStateCallback onAuthStateChanged) {
  //   _onAuthStateChanged = onAuthStateChanged;
  //
  //   // Cancel existing subscription if any
  //   _authStateSubscription?.cancel();
  //
  //   // Set up new subscription
  //   _authStateSubscription = _client.auth.onAuthStateChange.listen((data) {
  //     final AuthChangeEvent event = data.event;
  //     final Session? session = data.session;
  //     AuthState authState = AuthState(event, session);
  //
  //     if (DEBUG) {
  //       print('🔐 Supabase auth state changed: $authState');
  //       if (session != null) {
  //         print('✅ User: ${session.user.email} (${session.user.appMetadata['provider']})');
  //
  //         if (event == AuthChangeEvent.signedIn) {
  //
  //           print("SIGN IN DOES WORK INDEEED!! But it redirects to login screen instead of the main screen!");
  //
  //           _authBloc!.add(const NavigateToHomeEvent(
  //               successMessage: 'Successfully signed in with Apple ID'
  //           ));
  //         }
  //       }
  //     }
  //
  //     // Call the callback function
  //     _onAuthStateChanged?.call(authState, session);
  //   });
  // }

  // Add method to remove the listener
  void removeAuthStateListener() {
    _authStateSubscription?.cancel();
    _authStateSubscription = null;
    _onAuthStateChanged = null;
  }

  // Make sure to clean up when the service is disposed
  void dispose() {
    _authStateSubscription?.cancel();
  }

  @override
  Future<ApiResult<UserProfile>> getUserProfile(String userId) async {
    debugLogCyan("getUserProfile", tag: "API");
    try {
      _logRequest(
        'select',
        'user_profiles',
        null,
        additionalInfo: 'userId: $userId',
      );

      final response = await _client
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response == null) {
        // User profile doesn't exist - return error with a clear message
        return ApiResult.error('User profile not found for user: $userId');
      }

      return ApiResult.success(UserProfile.fromJson(response));
    } catch (e) {
      _logError('getUserProfile', e, context: 'userId: $userId');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<UserProfile>> updateUserProfile(
    String userId,
    Map<String, dynamic> data,
  ) async {
    debugLogCyan("updateUserProfile", tag: "API");
    try {
      data['updated_at'] = DateTime.now().toUtc().toIso8601String();

      _logRequest(
        'update',
        'user_profiles',
        data,
        additionalInfo: 'userId: $userId',
      );

      final response = await _client
          .from('user_profiles')
          .update(data)
          .eq('id', userId)
          .select()
          .single();

      AmplitudeService.instance.logEvent('profile_updated', eventProperties: {'fields': data.keys.where((k) => k != 'updated_at').toList()});
      return ApiResult.success(UserProfile.fromJson(response));
    } catch (e) {
      _logError('updateUserProfile', e, context: 'userId: $userId');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<UserRole>> getUserRole(String userId) async {
    debugLogCyan("getUserRole", tag: "API");
    try {
      _logRequest(
        'select_role',
        'user_profiles',
        null,
        additionalInfo: 'userId: $userId',
      );

      final response = await _client
          .from('user_profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();

      if (response == null) {
        // User profile doesn't exist - return default role
        return ApiResult.success(UserRole.fromString('regular'));
      }

      final roleString = response['role'] as String? ?? 'regular';
      return ApiResult.success(UserRole.fromString(roleString));
    } catch (e) {
      _logError('getUserRole', e, context: 'userId: $userId');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<List<Organization>>> getUserManagedOrganizations(
    String userId,
  ) async {
    debugLogCyan("getUserManagedOrganizations", tag: "API");
    try {
      _logRequest(
        'select_managed_organizations',
        'user_profiles',
        null,
        additionalInfo: 'userId: $userId',
      );

      // First, get the user's role
      final userRoleResult = await getUserRole(userId);
      if (!userRoleResult.isSuccess) {
        return ApiResult.error(
          'Failed to get user role: ${userRoleResult.error}',
        );
      }

      final userRole = userRoleResult.data!;
      List<Map<String, dynamic>> organizationsData = [];

      if (userRole.isRegular) {
        // Regular users manage no organizations
        return const ApiResult.success([]);
      } else if (userRole.isSuperAdmin) {
        // Super admins can manage all organizations
        final response = await _client.from('organizations').select('*');
        organizationsData = List<Map<String, dynamic>>.from(response);
      } else if (userRole.isAdmin) {
        // For admins, first get the organization IDs they manage
        debugLogOrange(
          'Getting admin organizations for user: $userId',
          tag: "ADMIN",
        );

        final adminOrgsResponse = await _client
            .from('admin_organizations')
            .select('organization_id')
            .eq('user_id', userId);

        debugLogOrange(
          'Admin organizations response: $adminOrgsResponse',
          tag: "ADMIN",
        );

        if (adminOrgsResponse.isEmpty) {
          debugLogYellow('No admin organizations found for user', tag: "ADMIN");
          return const ApiResult.success([]);
        }

        // Extract organization IDs
        final orgIds = adminOrgsResponse
            .map((row) => row['organization_id'] as String)
            .toList();

        debugLogOrange('Organization IDs to fetch: $orgIds', tag: "ADMIN");

        // Now get the organizations - let's try the simplest approach first
        List<Map<String, dynamic>> orgsData = [];

        for (String orgId in orgIds) {
          try {
            final orgResponse = await _client
                .from('organizations')
                .select('*')
                .eq('id', orgId)
                .single();

            orgsData.add(orgResponse);
          } catch (e) {
            errorLog('Error fetching organization $orgId: $e', tag: "ADMIN");
            // Continue with other organizations
          }
        }

        final orgsResponse = orgsData;

        debugLogOrange('Organizations response: $orgsResponse', tag: "ADMIN");

        organizationsData = List<Map<String, dynamic>>.from(orgsResponse);
      }

      debugLogGreen(
        'Final organizations data count: ${organizationsData.length}',
        tag: "ADMIN",
      );

      // For now, let's simplify and not worry about categories
      final organizations = organizationsData.map((orgData) {
        // Just add empty category_ids for now
        final cleanOrgData = Map<String, dynamic>.from(orgData);
        cleanOrgData['category_ids'] = <String>[];
        return Organization.fromJson(cleanOrgData);
      }).toList();

      return ApiResult.success(organizations);
    } catch (e) {
      _logError('getUserManagedOrganizations', e, context: 'userId: $userId');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<List<T>>> getAll<T>(
    String table, {
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
    int? limit,
    int? offset,
  }) async {
    debugLogCyan("getAll $table", tag: "API");
    try {
      final queryInfo = {
        if (filters != null) 'filters': filters,
        if (orderBy != null) 'orderBy': orderBy,
        'ascending': ascending,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      };

      _logRequest('select_all', table, queryInfo);

      // Start with the base query
      var query = _client.from(table).select();

      // Apply filters (these maintain PostgrestFilterBuilder type)
      if (filters != null) {
        filters.forEach((key, value) {
          query = query.eq(key, value);
        });
      }

      // Now build the final query based on what options we have
      dynamic finalQuery;

      if (orderBy != null) {
        finalQuery = query.order(orderBy, ascending: ascending);
      } else {
        finalQuery = query;
      }

      // Apply pagination
      if (offset != null && limit != null) {
        finalQuery = finalQuery.range(offset, offset + limit - 1);
      } else if (limit != null) {
        finalQuery = finalQuery.limit(limit);
      }

      final response = await finalQuery;

      // Note: Generic type casting would need specific implementation
      // based on your model classes
      return ApiResult.success(response as List<T>);
    } catch (e) {
      _logError('getAll', e, context: 'table: $table');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<T>> getById<T>(String table, String id) async {
    debugLogCyan("getById $table", tag: "API");
    try {
      _logRequest('select_by_id', table, null, additionalInfo: 'id: $id');

      final response = await _client.from(table).select().eq('id', id).single();

      return ApiResult.success(response as T);
    } catch (e) {
      _logError('getById', e, context: 'table: $table, id: $id');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<T>> create<T>(
    String table,
    Map<String, dynamic> data,
  ) async {
    debugLogGreen("create $table", tag: "API");
    try {
      data['created_at'] = DateTime.now().toUtc().toIso8601String();
      data['updated_at'] = DateTime.now().toUtc().toIso8601String();

      _logRequest('insert', table, data);

      final response = await _client.from(table).insert(data).select().single();

      return ApiResult.success(response as T);
    } catch (e) {
      _logError('create', e, context: 'table: $table');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<T>> update<T>(
    String table,
    String id,
    Map<String, dynamic> data,
  ) async {
    debugLogYellow("update $table", tag: "API");
    try {
      data['updated_at'] = DateTime.now().toUtc().toIso8601String();

      _logRequest('update', table, data, additionalInfo: 'id: $id');

      final response = await _client
          .from(table)
          .update(data)
          .eq('id', id)
          .select()
          .single();

      return ApiResult.success(response as T);
    } catch (e) {
      _logError('update', e, context: 'table: $table, id: $id');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<bool>> delete(String table, String id) async {
    debugLogRed("delete $table", tag: "API");
    try {
      _logRequest('delete', table, null, additionalInfo: 'id: $id');

      await _client.from(table).delete().eq('id', id);

      return const ApiResult.success(true);
    } catch (e) {
      _logError('delete', e, context: 'table: $table, id: $id');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Enhanced error handler that maps Supabase exceptions to our custom error types
  ApiError _handleError(dynamic error) {
    if (DEBUG) {
      print('🚨 ERROR DETAILS: ${error.runtimeType} - $error');
    }

    // Check for network errors first (including nested exceptions)
    final networkError = _extractNetworkError(error);
    if (networkError != null) {
      return networkError;
    }

    // Handle AuthException
    if (error is AuthException) {
      return _handleAuthException(error);
    }

    // Handle AuthRetryableFetchException (network-related auth errors)
    if (error.toString().contains('AuthRetryableFetchException')) {
      // Extract the underlying error message
      final errorString = error.toString();
      if (_isNetworkErrorString(errorString)) {
        return const ApiError(
          type: ApiErrorType.network,
          code: 'network_error',
          message:
              'Unable to connect to the server. Please check your internet connection and try again.',
        );
      }
      // If it's a retryable fetch exception but not clearly network-related,
      // still treat it as network error since it's retryable
      return ApiError(
        type: ApiErrorType.network,
        code: 'network_error',
        message:
            'Connection error. Please check your internet connection and try again.',
        details: errorString,
      );
    }

    // Handle PostgrestException (database errors)
    if (error is PostgrestException) {
      return _handlePostgrestException(error);
    }

    // Handle StorageException
    if (error is StorageException) {
      // Check if storage error is network-related
      final storageNetworkError = _extractNetworkError(error);
      if (storageNetworkError != null) {
        return storageNetworkError;
      }
      return ApiError(
        type: ApiErrorType.server,
        code: error.statusCode ?? 'storage_error',
        message: error.message,
        details: 'Storage operation failed',
      );
    }

    // Generic error fallback
    return ApiError(
      type: ApiErrorType.unknown,
      code: 'unknown_error',
      message: 'An unexpected error occurred',
      details: error.toString(),
    );
  }

  /// Extracts network-related errors from exceptions (including nested ones)
  ApiError? _extractNetworkError(dynamic error) {
    // Check if error is a SocketException
    if (error is SocketException) {
      return const ApiError(
        type: ApiErrorType.network,
        code: 'network_error',
        message:
            'Unable to connect to the server. Please check your internet connection and try again.',
      );
    }

    // Check if error is a TimeoutException
    if (error is TimeoutException) {
      return const ApiError(
        type: ApiErrorType.network,
        code: 'network_timeout',
        message:
            'Request timed out. Please check your internet connection and try again.',
      );
    }

    // Check error string for network-related patterns
    final errorString = error.toString();
    if (_isNetworkErrorString(errorString)) {
      // Determine specific network error type
      if (errorString.contains('Failed host lookup') ||
          errorString.contains('No address associated with hostname')) {
        return const ApiError(
          type: ApiErrorType.network,
          code: 'dns_error',
          message:
              'Unable to reach the server. Please check your internet connection and try again.',
        );
      }
      if (errorString.contains('TimeoutException') ||
          errorString.contains('timed out')) {
        return const ApiError(
          type: ApiErrorType.network,
          code: 'network_timeout',
          message:
              'Request timed out. Please check your internet connection and try again.',
        );
      }
      if (errorString.contains('HandshakeException') ||
          errorString.contains('SSL') ||
          errorString.contains('TLS')) {
        return const ApiError(
          type: ApiErrorType.network,
          code: 'ssl_error',
          message:
              'Secure connection failed. Please check your internet connection and try again.',
        );
      }
      // Generic network error
      return const ApiError(
        type: ApiErrorType.network,
        code: 'network_error',
        message:
            'Network connection failed. Please check your internet connection and try again.',
      );
    }

    return null;
  }

  /// Checks if an error string indicates a network error
  bool _isNetworkErrorString(String errorString) {
    final lowerError = errorString.toLowerCase();
    return lowerError.contains('socketexception') ||
        lowerError.contains('timeoutexception') ||
        lowerError.contains('handshakeexception') ||
        lowerError.contains('failed host lookup') ||
        lowerError.contains('no address associated with hostname') ||
        lowerError.contains('network is unreachable') ||
        lowerError.contains('connection refused') ||
        lowerError.contains('connection reset') ||
        lowerError.contains('connection timed out') ||
        lowerError.contains('no internet connection') ||
        lowerError.contains('networkerror') ||
        lowerError.contains('clientexception') ||
        lowerError.contains('retryablefetchexception');
  }

  /// Handle AuthException with specific error codes
  ApiError _handleAuthException(AuthException error) {
    switch (error.statusCode) {
      case '400':
        if (error.message.contains('Invalid login credentials')) {
          return const ApiError(
            type: ApiErrorType.authentication,
            code: 'invalid_credentials',
            message: 'Invalid email or password',
          );
        }
        if (error.message.contains('Email not confirmed')) {
          return const ApiError(
            type: ApiErrorType.authentication,
            code: 'email_not_confirmed',
            message: 'Please confirm your email address before signing in',
          );
        }
        if (error.message.contains('Invalid email')) {
          return const ApiError(
            type: ApiErrorType.validation,
            code: 'invalid_email',
            message: 'Please enter a valid email address',
          );
        }
        if (error.message.contains('Unacceptable audience in id_token')) {
          return const ApiError(
            type: ApiErrorType.authentication,
            code: 'apple_audience_mismatch',
            message:
                'Apple Sign-In configuration mismatch. Please contact support.',
          );
        }
        break;
      case '422':
        if (error.message.contains('Password should be at least')) {
          return const ApiError(
            type: ApiErrorType.validation,
            code: 'weak_password',
            message: 'Password should be at least 6 characters long',
          );
        }
        if (error.message.contains('only lowercase letters')) {
          return const ApiError(
            type: ApiErrorType.validation,
            code: 'invalid_email_format',
            message: 'Email must contain only lowercase letters',
          );
        }
        break;
      case '429':
        if (error.message.contains('rate limit') ||
            error.toString().contains('over_email_send_rate_limit')) {
          return const ApiError(
            type: ApiErrorType.server,
            code: 'email_rate_limit',
            message:
                'Account creation failed. Email service is not available.',
          );
        }
        return const ApiError(
          type: ApiErrorType.server,
          code: 'rate_limit_exceeded',
          message: 'Too many requests. Please try again later.',
        );
      case '500':
        return const ApiError(
          type: ApiErrorType.server,
          code: 'server_error',
          message: 'Server error. Please try again later.',
        );
    }

    return ApiError(
      type: ApiErrorType.authentication,
      code: error.statusCode ?? 'auth_error',
      message: error.message,
    );
  }

  /// Handle PostgrestException with specific database error codes
  ApiError _handlePostgrestException(PostgrestException error) {
    final code = error.code;
    final message = error.message;
    final details = error.details;

    // Handle specific PostgreSQL error codes
    switch (code) {
      // Unique constraint violation
      case '23505':
        if (message.contains('email')) {
          return const ApiError(
            type: ApiErrorType.validation,
            code: 'email_already_exists',
            message: 'An account with this email already exists',
          );
        }
        if (message.contains('username')) {
          return const ApiError(
            type: ApiErrorType.validation,
            code: 'username_already_exists',
            message: 'This username is already taken',
          );
        }
        return const ApiError(
          type: ApiErrorType.validation,
          code: 'duplicate_entry',
          message: 'This entry already exists',
        );

      // Not null constraint violation
      case '23502':
        return ApiError(
          type: ApiErrorType.validation,
          code: 'missing_required_field',
          message: 'Required field is missing',
          details: details.toString(),
        );

      // Foreign key constraint violation
      case '23503':
        return const ApiError(
          type: ApiErrorType.validation,
          code: 'invalid_reference',
          message: 'Referenced record does not exist',
        );

      // Check constraint violation
      case '23514':
        return ApiError(
          type: ApiErrorType.validation,
          code: 'constraint_violation',
          message: 'Data validation failed',
          details: details.toString(),
        );

      // Insufficient privilege
      case '42501':
        return const ApiError(
          type: ApiErrorType.authorization,
          code: 'insufficient_permissions',
          message: 'You do not have permission to perform this action',
        );

      // Undefined table
      case '42P01':
        return const ApiError(
          type: ApiErrorType.server,
          code: 'table_not_found',
          message: 'Resource not found',
        );

      // Undefined column
      case '42703':
        return const ApiError(
          type: ApiErrorType.server,
          code: 'column_not_found',
          message: 'Invalid field specified',
        );
    }

    // Handle RLS (Row Level Security) errors
    if (message.contains('new row violates row-level security policy')) {
      return const ApiError(
        type: ApiErrorType.authorization,
        code: 'permission_denied',
        message: 'You do not have permission to access this resource',
      );
    }

    // Handle JWT token errors
    if (message.contains('JWT expired') || message.contains('invalid token')) {
      return const ApiError(
        type: ApiErrorType.authentication,
        code: 'token_expired',
        message: 'Your session has expired. Please sign in again.',
      );
    }

    return ApiError(
      type: ApiErrorType.database,
      code: code ?? 'database_error',
      message: message,
      details: details.toString(),
    );
  }

  /// Check if user already exists during signup (handles the identities empty array case)
  bool _isUserAlreadyExists(AuthResponse response) {
    return response.user != null &&
        response.user!.identities != null &&
        response.user!.identities!.isEmpty;
  }

  bool _isUserNotConfirmed(AuthResponse response) {
    return response.user != null && response.user?.emailConfirmedAt == null;
  }

  /// Log request data as JSON if DEBUG is enabled
  void _logRequest(
    String operation,
    String table,
    Map<String, dynamic>? data, {
    String? additionalInfo,
  }) {
    if (!DEBUG) return;

    final logData = {
      'operation': operation,
      'table': table,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      if (data != null) 'request_data': data,
      if (additionalInfo != null) 'additional_info': additionalInfo,
    };

    apiRequestLog(operation, table, data: logData);
  }

  /// Log authentication requests
  void _logAuthRequest(
    String operation,
    String email, {
    Map<String, dynamic>? additionalData,
  }) {
    if (!DEBUG) return;

    final logData = {
      'operation': operation,
      'email': email,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      if (additionalData != null) 'additional_data': additionalData,
    };

    authLog('AUTH REQUEST: ${jsonEncode(logData)}');
  }

  /// Log errors with full context
  void _logError(String operation, dynamic error, {String? context}) {
    if (!DEBUG) return;

    final logData = {
      'operation': operation,
      'error_type': error.runtimeType.toString(),
      'error_message': error.toString(),
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      if (context != null) 'context': context,
    };

    apiErrorLog(operation, jsonEncode(logData));
  }

  /// Initialize Supabase with environment-specific configuration
  /// [environment] - The environment to load ('dev', 'qa', 'prod')
  /// If not specified, defaults to '.env'
  Future<void> initialize({String? environment}) async {
    String envFile = '.env';

    if (environment != null) {
      envFile = '.env_$environment';
    }

    infoLog("Trying to load the file $envFile...", tag: "INIT");

    try {
      await dotenv.load(fileName: envFile);
      successLog('Loaded environment file: $envFile', tag: "INIT");
    } catch (e) {
      warningLog('Failed to load $envFile, falling back to .env', tag: "INIT");
      await dotenv.load(fileName: '.env');
    }

    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

    if (supabaseUrl == null || supabaseAnonKey == null) {
      throw Exception(
        'SUPABASE_URL and SUPABASE_ANON_KEY must be set in $envFile',
      );
    }

    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        debug: environment == 'dev', // Enable debug mode for development
        // The app's AuthSignalChain is now the sole deep-link processor;
        // disable Supabase's own auto-detection to avoid a second,
        // competing pipeline (see lib/modules/auth/chain).
        authOptions: const FlutterAuthClientOptions(
          detectSessionInUri: false,
        ),
      );
    } catch (e) {
      errorLog('Error initializing Supabase: $e', tag: "INIT");
      // rethrow; // ! This is probably required in tests
    }

    _client = Supabase.instance.client;
    successLog(
      'Supabase initialized successfully for environment: ${environment ?? 'default'}',
      tag: "INIT",
    );
  }

  @override
  Future<AuthResult> signIn(String email, String password) async {
    authLog("signIn attempt for email: ${email.substring(0, 3)}***");
    authLog("signIn attempt for password: ${password}");
    try {
      _logAuthRequest('signIn', email);

      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        // Check if email is confirmed
        if (response.user!.emailConfirmedAt == null) {
          // User exists but email not confirmed - redirect to OTP explanation
          return AuthResult.pendingEmailConfirmation(
            email: email,
            message: 'Please confirm your email address to continue',
          );
        }

        return AuthResult.success(
          userId: response.user!.id,
          email: response.user!.email,
          userData: response.user!.userMetadata,
        );
      } else {
        AmplitudeService.instance.logEvent('login_error', eventProperties: {'method': 'email', 'error': 'login_failed'});
        return const AuthResult.error('Login failed');
      }
    } catch (e) {
      _logError(
        'signIn',
        e,
        context: 'email: 🟠$email🟠 password: 🟠$password🟠',
      );

      // Check if the error is specifically about email not being confirmed
      final apiError = _handleError(e);
      if (apiError.code == 'email_not_confirmed') {
        return AuthResult.pendingEmailConfirmation(
          email: email,
          message: apiError.message,
        );
      }

      AmplitudeService.instance.logEvent('login_error', eventProperties: {'method': 'email', 'error': apiError.code});
      return AuthResult.error(apiError.message);
    }
  }

  @override
  Future<AuthResult> signUp(
    String email,
    String password,
    String fullName,
  ) async {
    authLog("signUp attempt for email: ${email.substring(0, 3)}***");
    try {
      final signUpData = {'full_name': fullName};
      _logAuthRequest('signUp', email, additionalData: signUpData);
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: signUpData,
      );

      // Check if user has already signed up but not confirmed email yet
      if (_isUserNotConfirmed(response)) {
        return AuthResult.pendingEmailConfirmation(
          email: email,
          message: 'Please confirm your email address to continue',
        );
      }

      // Check if user already exists using the identities method
      if (_isUserAlreadyExists(response)) {
        return const AuthResult.error(
          'An account with this email already exists',
        );
      }

      if (response.user != null) {
        // User profile is created by the handle_new_user DB trigger.
        AmplitudeService.instance.logEvent('sign_up', eventProperties: {'method': 'email'});
        return AuthResult.pendingEmailConfirmation(
          email: email,
          message: 'Account created! Choose how to verify your account.',
        );
      } else {
        AmplitudeService.instance.logEvent('sign_up_error', eventProperties: {'error': 'creation_failed'});
        return const AuthResult.error('Account creation failed');
      }
    } catch (e) {
      _logError('signUp', e, context: 'email: $email');
      final apiError = _handleError(e);

      // Email rate limit hit — account may have been created but email not sent.
      // Route user to the verification choice screen so they can use SMS instead.
      if (apiError.code == 'email_rate_limit' ||
          e.toString().contains('over_email_send_rate_limit')) {
        AmplitudeService.instance.logEvent('sign_up', eventProperties: {'method': 'email'});
        return AuthResult.pendingEmailConfirmation(
          email: email,
          message: 'Account created! Email service is temporarily unavailable — please verify via SMS.',
        );
      }

      // Check if error is about user already registered but unconfirmed
      if (apiError.message.contains('already registered') ||
          apiError.message.contains('Email already registered')) {
        return AuthResult.pendingEmailConfirmation(
          email: email,
          message:
              'Account exists but email not confirmed. Please check your email.',
        );
      }

      AmplitudeService.instance.logEvent('sign_up_error', eventProperties: {'error': apiError.code});
      return AuthResult.error(apiError.message);
    }
  }

  /// Performs Apple sign in on iOS or macOS
  Future<AuthResponse> signInWithApple() async {
    final rawNonce = _client.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    // Get the current bundle identifier based on environment
    final bundleId = _getCurrentBundleIdentifier();

    authLog('Using bundle identifier: $bundleId for Apple Sign-In');

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );
    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException(
        'Could not find ID Token from generated credential.',
      );
    }

    // Log the ID token for debugging (remove in production)
    if (DEBUG) {
      authLog(
        'Apple ID Token received, attempting to sign in with Supabase...',
      );
    }

    return _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
  }

  @override
  Future<AuthResult> signInWithProvider(
    String provider, {
    String? customRedirectUrl,
  }) async {
    authLog("signInWithProvider: $provider");
    try {
      _logAuthRequest(
        'signInWithProvider',
        'N/A',
        additionalData: {'provider': provider},
      );

      OAuthProvider oAuthProvider;

      switch (provider.toLowerCase()) {
        case 'google':
          oAuthProvider = OAuthProvider.google;
          break;
        case 'facebook':
          oAuthProvider = OAuthProvider.facebook;
          break;
        case 'apple':
          oAuthProvider = OAuthProvider.apple;
          break;
        default:
          return AuthResult.error('Unsupported provider: $provider');
      }

      // Use native iOS sign up, otherwise web version will be used
      if (provider.toLowerCase() == 'apple' && Platform.isIOS) {
        AuthResponse appleResponse = await signInWithApple();

        // After successful Apple sign-in, update/create user profile
        if (appleResponse.user != null) {
          await _updateUserProfileAfterSocialLogin(appleResponse.user!);

          return AuthResult.success(
            userId: appleResponse.user?.id ?? "",
            email: appleResponse.user?.email,
            userData: appleResponse.user?.userMetadata,
          );
        }
      }

      // Configure the redirect URL based on environment
      final String redirectUrl =
          "${customRedirectUrl ?? _getEnvironmentRedirectUrl()}://login-callback";
      print("Using custom redirectUrl $redirectUrl...");

      final response = await _client.auth
          .signInWithOAuth(
            oAuthProvider,
            redirectTo: redirectUrl,
            authScreenLaunchMode: LaunchMode.inAppWebView,
          )
          .timeout(
            Duration(seconds: 6),
            onTimeout: () {
              // Handle timeout case
              print("REDIRECTED TO URL $redirectUrl");
              return false;
            },
          );

      if (response) {
        final user = _client.auth.currentUser;
        if (user != null) {
          // Update/create user profile for web-based OAuth flows too
          await _updateUserProfileAfterSocialLogin(user);

          return AuthResult.success(
            userId: user.id,
            email: user.email,
            userData: user.userMetadata,
          );
        }
      }

      AmplitudeService.instance.logEvent('login_error', eventProperties: {'method': provider, 'error': 'oauth_failed'});
      return AuthResult.error('$provider login failed');
    } catch (e) {
      _logError('signInWithProvider', e, context: 'provider: $provider');
      final apiError = _handleError(e);
      AmplitudeService.instance.logEvent('login_error', eventProperties: {'method': provider, 'error': apiError.code});
      return AuthResult.error(apiError.message);
    }
  }

  // Add this new helper method to handle profile updates after social login
  Future<void> _updateUserProfileAfterSocialLogin(User user) async {
    try {
      print('🔄 Updating user profile after social login...');

      // Extract user information from metadata
      final userMetadata = user.userMetadata ?? {};
      final fullName =
          userMetadata['full_name'] ??
          userMetadata['name'] ??
          userMetadata['display_name'] ??
          '';
      final email = user.email ?? '';

      // Check if user profile already exists
      final existingProfile = await _client
          .from('user_profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (existingProfile == null) {
        // Create new profile
        final profileData = {
          'id': user.id,
          'email': email,
          'username': email, // Use email as username initially
          'full_name': fullName,
          'role': 'regular', // Default role
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };

        _logRequest('insert', 'user_profiles', profileData);
        await _client.from('user_profiles').insert(profileData);
        print('✅ Created new user profile for social login');
      } else {
        // Update existing profile with latest information
        final updateData = <String, dynamic>{
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };

        // Only update fields if they have values and are different
        if (fullName.isNotEmpty && fullName != existingProfile['full_name']) {
          updateData['full_name'] = fullName;
        }

        if (email.isNotEmpty && email != existingProfile['email']) {
          updateData['email'] = email;
        }

        // Only update if there are changes
        if (updateData.length > 1) {
          // More than just updated_at
          _logRequest('update', 'user_profiles', updateData);
          await _client
              .from('user_profiles')
              .update(updateData)
              .eq('id', user.id);
          print('✅ Updated existing user profile for social login');
        } else {
          print('ℹ️ No profile updates needed for social login');
        }
      }
    } catch (e) {
      _logError('_updateUserProfileAfterSocialLogin', e);
      print('⚠️ Warning: Failed to update user profile after social login: $e');
      // Don't throw error - we don't want to fail the login process
    }
  }

  @override
  Future<void> signOut() async {
    print("signOut");
    try {
      if (DEBUG) {
        print(
          '🔐 DEBUG AUTH REQUEST: ${jsonEncode({'operation': 'signOut', 'timestamp': DateTime.now().toUtc().toIso8601String()})}',
        );
      }
      await _client.auth.signOut();
    } catch (e) {
      _logError('signOut', e);
      // Don't throw error for signOut, just log it
      print('Warning: Error during sign out: $e');
    }
  }

  Future<bool> isSessionValid() async {
    print("isSessionValid");
    try {
      final session = _client.auth.currentSession;
      if (session == null) return false;

      // Check if token is expired
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      return session.expiresAt != null && session.expiresAt! > now;
    } catch (e) {
      _logError('isSessionValid', e);
      return false;
    }
  }

  @override
  Future<ApiResult<UserProfile>> createUserProfile({
    required String userId,
    required String username,
    required String fullName,
    required String email,
    String role = 'regular',
  }) async {
    try {
      final response = await _client
          .from('user_profiles')
          .insert({
            'id': userId,
            'username': username,
            'full_name': fullName,
            'email': email,
            'role': role,
          })
          .select()
          .single();

      final userProfile = UserProfile.fromJson(response);
      return ApiResult.success(userProfile);
    } catch (e) {
      print('🚨 Error creating user profile: $e');
      return ApiResult.error('Failed to create user profile: ${e.toString()}');
    }
  }

  // Also add this method to handle username conflicts
  Future<String> _generateUniqueUsername(String baseUsername) async {
    String username = baseUsername;
    int counter = 1;

    while (true) {
      try {
        final existing = await _client
            .from('user_profiles')
            .select('id')
            .eq('username', username)
            .maybeSingle();

        if (existing == null) {
          return username; // Username is available
        }

        username = '${baseUsername}_$counter';
        counter++;
      } catch (e) {
        print('Error checking username availability: $e');
        return '${baseUsername}_${DateTime.now().millisecondsSinceEpoch}';
      }
    }
  }

  @override
  Future<AuthResult> verifyOtp(
    String email,
    String token,
    String otpType,
  ) async {
    print("verifyOtp");
    try {
      _logAuthRequest(
        'verifyOtp',
        email,
        additionalData: {
          'otpType': otpType,
          'token': '${token.substring(0, 3)}***',
        },
      );

      // Map string type to OtpType enum
      OtpType otpTypeEnum;
      switch (otpType.toLowerCase()) {
        case 'email':
          otpTypeEnum = OtpType.email;
          break;
        case 'signup':
          otpTypeEnum = OtpType.signup;
          break;
        case 'email_change':
          otpTypeEnum = OtpType.emailChange;
          break;
        case 'sms':
          otpTypeEnum = OtpType.sms;
          break;
        case 'phone_change':
          otpTypeEnum = OtpType.phoneChange;
          break;
        case 'recovery':
          otpTypeEnum = OtpType.recovery;
          break;
        default:
          print(" 'recovery' == '$otpType' ?");
          return AuthResult.error('Invalid OTP type: $otpType');
      }

      final response = await _client.auth.verifyOTP(
        type: otpTypeEnum,
        token: token,
        email: email,
      );

      if (response.user != null) {
        // For signup verification, we might need to create/update the user profile
        if (otpType.toLowerCase() == 'signup') {
          try {
            // Check if user profile already exists
            final existingProfile = await _client
                .from('user_profiles')
                .select()
                .eq('id', response.user!.id)
                .maybeSingle();

            if (existingProfile == null) {
              // Create user profile if it doesn't exist
              final profileData = {
                'id': response.user!.id,
                'email': response.user!.email,
                'username': response.user!.email, // Using email as username
                'full_name': response.user!.userMetadata?['full_name'] ?? '',
                'role': 'regular', // Default role
                'created_at': DateTime.now().toUtc().toIso8601String(),
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              };

              _logRequest('insert', 'user_profiles', profileData);
              await _client.from('user_profiles').insert(profileData);
            }
          } catch (profileError) {
            // Log the error but don't fail the OTP verification
            _logError('verifyOtp_profile_creation', profileError);
            print(
              'Warning: Failed to create/update user profile: $profileError',
            );
          }
        }

        return AuthResult.success(
          userId: response.user!.id,
          email: response.user!.email,
          userData: response.user!.userMetadata,
        );
      } else {
        return const AuthResult.error('OTP verification failed');
      }
    } catch (e) {
      _logError('verifyOtp', e, context: 'email: $email, otpType: $otpType');
      final apiError = _handleError(e);
      return AuthResult.error(apiError.message);
    }
  }

  @override
  @override
  Future<AuthResult> sendEmailOtp(String email) async {
    print("sendEmailOtp");
    try {
      // signInWithOtp is unauthenticated — works before the user has a session.
      // shouldCreateUser: false ensures we never create a new user here; the
      // account was already created by signUp.
      await _client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: false,
      );
      return const AuthResult.success(
        userId: "",
        message: 'Verification code sent to email',
      );
    } on AuthException catch (e) {
      return AuthResult.error(e.message);
    } catch (e) {
      return AuthResult.error('Failed to send email OTP: ${e.toString()}');
    }
  }

  Future<AuthResult> resendOtp(String email, String otpType) async {
    print("resendOtp");
    try {
      _logAuthRequest('resendOtp', email, additionalData: {'otpType': otpType});

      if (otpType.toLowerCase() == 'email') {
        // Re-send via signInWithOtp — same as the initial send.
        await _client.auth.signInWithOtp(
          email: email,
          shouldCreateUser: false,
        );
        return const AuthResult.success(userId: "", email: null, userData: null);
      }

      // Map string type to OtpType enum
      OtpType otpTypeEnum;
      switch (otpType.toLowerCase()) {
        case 'signup':
          otpTypeEnum = OtpType.signup;
          break;
        case 'email_change':
          otpTypeEnum = OtpType.emailChange;
          break;
        case 'sms':
          otpTypeEnum = OtpType.sms;
          break;
        case 'phone_change':
          otpTypeEnum = OtpType.phoneChange;
          break;
        default:
          return AuthResult.error('Invalid OTP type: $otpType');
      }

      await _client.auth.resend(type: otpTypeEnum, email: email);
      return const AuthResult.success(userId: "", email: null, userData: null);
    } on AuthException catch (e) {
      return AuthResult.error(e.message);
    } catch (e) {
      return AuthResult.error('Failed to resend OTP: ${e.toString()}');
    }
  }

  static const String _sessionExpiredMessage =
      'We could not restore your session. Please check your connection and '
      'try again — if the problem persists, log in again to continue '
      'verification.';

  /// Returns true once a usable (non-expired) session is available.
  ///
  /// At cold start supabase_flutter restores the persisted session
  /// asynchronously; calling updateUser()/resend() in that window throws
  /// AuthSessionMissingException ("Auth session missing!" — BUG-004/BUG-005).
  /// Waits briefly for the recovery to land and refreshes an expired token
  /// before any authenticated auth call is attempted.
  Future<bool> _ensureSession() async {
    var session = _client.auth.currentSession;

    for (var i = 0; session == null && i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      session = _client.auth.currentSession;
    }
    if (session == null) return false;
    if (!session.isExpired) return true;

    try {
      await _client.auth.refreshSession();
    } catch (e) {
      warningLog('Session refresh failed in _ensureSession: $e', tag: "AUTH");
    }
    final refreshed = _client.auth.currentSession;
    return refreshed != null && !refreshed.isExpired;
  }

  @override
  Future<AuthResult> sendPhoneOtp(String phoneNumber) async {
    print("sendPhoneOtp");
    try {
      if (!await _ensureSession()) {
        return const AuthResult.error(_sessionExpiredMessage);
      }

      // Use updateUser so the phone is linked to the existing authenticated
      // user rather than creating a new phone-only auth.users row (which would
      // fire the handle_new_user trigger and crash with a NOT NULL violation on
      // user_profiles.email). Verification uses OtpType.phoneChange.
      print("Updating user with phone number $phoneNumber");
      await _client.auth.updateUser(UserAttributes(phone: phoneNumber));
      return const AuthResult.success(
        userId: "",
        message: 'SMS verification code sent successfully',
      );
    } on AuthSessionMissingException {
      return const AuthResult.error(_sessionExpiredMessage);
    } on AuthException catch (e) {
      return AuthResult.error(e.message);
    } catch (e) {
      return AuthResult.error('Failed to send SMS OTP: ${e.toString()}');
    }
  }

  @override
  Future<AuthResult> verifyPhoneOtp(String phoneNumber, String otpCode) async {
    print("verifyPhoneOtp");
    try {
      if (!await _ensureSession()) {
        return const AuthResult.error(_sessionExpiredMessage);
      }

      final response = await _client.auth.verifyOTP(
        type: OtpType.phoneChange,
        phone: phoneNumber,
        token: otpCode,
      );

      if (response.session != null) {
        final user = response.user;
        return AuthResult.success(
          userId: user?.id ?? '',
          email: user?.email,
          message: 'Phone verified successfully!',
          userData: user?.toJson(),
        );
      } else {
        return const AuthResult.error('Phone OTP verification failed');
      }
    } on AuthSessionMissingException {
      return const AuthResult.error(_sessionExpiredMessage);
    } on AuthException catch (e) {
      return AuthResult.error(e.message);
    } catch (e) {
      return AuthResult.error('Failed to verify phone OTP: ${e.toString()}');
    }
  }

  @override
  Future<AuthResult> resendPhoneOtp(String phoneNumber) async {
    print("resendPhoneOtp");
    try {
      if (!await _ensureSession()) {
        return const AuthResult.error(_sessionExpiredMessage);
      }

      await _client.auth.resend(
        type: OtpType.phoneChange,
        phone: phoneNumber,
      );
      return const AuthResult.success(
        userId: "",
        message: 'SMS verification code resent successfully',
      );
    } on AuthSessionMissingException {
      return const AuthResult.error(_sessionExpiredMessage);
    } on AuthException catch (e) {
      return AuthResult.error(e.message);
    } catch (e) {
      return AuthResult.error('Failed to resend SMS OTP: ${e.toString()}');
    }
  }

  @override
  Future<AuthResult> requestPasswordReset(String email) async {
    print("requestPasswordReset");
    try {
      _logAuthRequest('requestPasswordReset', email);

      final String redirectUrl =
          "${_getEnvironmentRedirectUrl()}://reset-password";

      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: redirectUrl, // Custom redirect URL
      );

      // Password reset email sent successfully
      return const AuthResult.success(
        userId: "",
        email: null,
        userData: {'message': 'Password reset email sent successfully'},
      );
    } catch (e) {
      _logError('requestPasswordReset', e, context: 'email: $email');
      final apiError = _handleError(e);
      return AuthResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<User>> processAppleLogin({
    required String authorizationCode,
    String? state,
  }) async {
    try {
      // Exchange the authorization code for tokens with Apple
      final AuthSessionUrlResponse response = await _client.auth
          .exchangeCodeForSession(authorizationCode);

      if (response.session.accessToken.isNotEmpty) {
        final user = User(
          id: response.session.user.id,
          email: response.session.user.email ?? '',
          // fullName: response.session.user!.userMetadata?['full_name'] ??
          //          response.session.user!.userMetadata?['name'] ??
          //          'Apple User',
          // profilePictureUrl: response.session.user!.userMetadata?['avatar_url'],
          // TODO: What should we put here?
          appMetadata: {},
          userMetadata: {},
          aud: '',
          createdAt: '',
        );

        return ApiResult.success(user);
      } else {
        return ApiResult.error('Failed to authenticate with Apple');
      }
    } catch (e) {
      print('Apple login error: $e');
      return ApiResult.error('Apple authentication failed: ${e.toString()}');
    }
  }

  Future<ApiResult<String>> initiateAppleLogin() async {
    try {
      // Use native sign_in_with_apple library on iOS, Supabase OAuth on other platforms
      if (Platform.isIOS) {
        print('🍎 Using native Apple Sign-In on iOS');

        // Use the existing native Apple Sign-In method
        final appleResponse = await signInWithApple();

        // After successful Apple sign-in, update/create user profile
        if (appleResponse.user != null) {
          await _updateUserProfileAfterSocialLogin(appleResponse.user!);

          print('✅ Apple login completed successfully on iOS');
          return ApiResult.success('Apple login completed successfully');
        } else {
          return ApiResult.error('Apple login failed - no user returned');
        }
      } else {
        // Use Supabase OAuth for Android, web, and other platforms
        final String redirectUrl =
            '${_getEnvironmentRedirectUrl()}://login-callback';

        print('🍎 Initiating Apple login with redirect URL: $redirectUrl');

        // Use externalApplication launch mode for proper OAuth flow
        final response = await _client.auth
            .signInWithOAuth(
              OAuthProvider.apple,
              redirectTo: redirectUrl,
              authScreenLaunchMode: LaunchMode.externalApplication,
            )
            .timeout(
              Duration(seconds: 10),
              onTimeout: () {
                print(
                  "⏰ Apple login timeout - this is normal for external flow",
                );
                return true; // Return true for external flow as it continues in background
              },
            );

        // For external application flow, response might be true even before completion
        print('🍎 Apple login flow initiated: $response');
        return ApiResult.success('Apple login initiated');
      }
    } catch (e) {
      print('❌ Apple login initiation error: $e');
      return ApiResult.error('Failed to start Apple login: ${e.toString()}');
    }
  }

  @override
  Future<AuthResult> resetPassword(String newPassword) async {
    print("resetPassword");
    try {
      _logAuthRequest(
        'resetPassword',
        'N/A',
        additionalData: {
          'hasValidSession': _client.auth.currentSession != null,
        },
      );

      // This method should only be called when the user has a valid session
      // from clicking the reset password link
      final response = await _client.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (response.user != null) {
        return AuthResult.success(
          userId: response.user!.id,
          email: response.user!.email,
          userData: response.user!.userMetadata,
        );
      } else {
        return const AuthResult.error('Failed to reset password');
      }
    } catch (e) {
      _logError('resetPassword', e);
      final apiError = _handleError(e);
      return AuthResult.error(apiError.message);
    }
  }

  @override
  Future<AuthResult> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    print("changePassword");
    try {
      _logAuthRequest('changePassword', 'N/A');

      // First verify the current password by attempting to sign in
      final user = _client.auth.currentUser;
      if (user?.email == null) {
        return const AuthResult.error('No authenticated user found');
      }

      // Verify current password
      try {
        // ! Wait, we should verify the curent password only if changing it from profile screen and not through passwrod reset
        await _client.auth.signInWithPassword(
          email: user!.email!,
          password: currentPassword,
        );
      } catch (e) {
        if (e is AuthApiException) {
          return AuthResult.error(e.message);
        }
        return const AuthResult.error('Current password is incorrect');
      }

      // Update to new password
      final response = await _client.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (response.user != null) {
        return AuthResult.success(
          userId: response.user!.id,
          email: response.user!.email,
          userData: response.user!.userMetadata,
        );
      } else {
        return const AuthResult.error('Failed to change password');
      }
    } catch (e) {
      _logError('changePassword', e);
      final apiError = _handleError(e);
      return AuthResult.error(apiError.message);
    }
  }

  // Enhanced error handling for password-related errors
  ApiError _handlePasswordError(dynamic error) {
    if (error is AuthException) {
      // Handle specific password-related auth errors
      if (error.message.contains('Password should be at least')) {
        return const ApiError(
          type: ApiErrorType.validation,
          code: 'weak_password',
          message: 'Password should be at least 6 characters long',
        );
      }

      if (error.message.contains('New password should be different')) {
        return const ApiError(
          type: ApiErrorType.validation,
          code: 'same_password',
          message: 'New password must be different from the current password',
        );
      }

      if (error.message.contains('Invalid login credentials')) {
        return const ApiError(
          type: ApiErrorType.authentication,
          code: 'invalid_current_password',
          message: 'Current password is incorrect',
        );
      }

      if (error.message.contains('Token has expired')) {
        return const ApiError(
          type: ApiErrorType.authentication,
          code: 'token_expired',
          message: 'Password reset link has expired. Please request a new one.',
        );
      }

      if (error.message.contains('Invalid token')) {
        return const ApiError(
          type: ApiErrorType.authentication,
          code: 'invalid_token',
          message: 'Invalid password reset link. Please request a new one.',
        );
      }
    }

    // Fall back to the general error handler
    return _handleError(error);
  }

  /// Verify password reset token from deep link

  /// This method handles the PKCE token from password reset emails
  /// [token] - The token parameter from the password reset deep link
  @override
  Future<AuthResult> verifyPasswordResetTokenTwo(String token) async {
    print("verifyPasswordResetToken");
    try {
      _logAuthRequest(
        'verifyPasswordResetToken',
        'N/A',
        additionalData: {
          'tokenLength': token.length,
          'tokenPrefix': '${token.substring(0, 10)}...',
        },
      );

      // For PKCE flow, we need to exchange the token for a session
      // The token is actually a code that needs to be exchanged
      final response = await _client.auth.exchangeCodeForSession(token);

      print('✅ Session established successfully for password reset');
      return AuthResult.success(
        userId: response.session.user.id,
        email: response.session.user.email,
        userData: response.session.user.userMetadata,
      );
    } catch (e) {
      print('🚨 Error in verifyPasswordResetToken: $e');
      _logError(
        'verifyPasswordResetToken',
        e,
        context: 'token: ${token.substring(0, 10)}...',
      );

      // Use the enhanced password error handler for better error messages
      final apiError = _handlePasswordError(e);
      return AuthResult.error(apiError.message);
    }
  }

  /// Exchange authorization code from password reset link for session
  /// This method handles the deep link callback from password reset emails
  /// [passwordResetLinkUriAsString] - The full URI from the password reset email
  Future<AuthResult> exchangeCodeForSession(
    String passwordResetLinkUriAsString,
  ) async {
    print("exchangeCodeForSession");
    try {
      _logAuthRequest(
        'exchangeCodeForSession',
        'N/A',
        additionalData: {
          'uri': '${passwordResetLinkUriAsString.substring(0, 50)}...',
        },
      );

      // Parse the URI to extract the code/token and other parameters
      final uri = Uri.parse(passwordResetLinkUriAsString);

      // Try both 'code' and 'token' parameters (Supabase might use either)
      final code = uri.queryParameters['code'] ?? uri.queryParameters['token'];

      if (code == null) {
        print(
          '❌ No code or token found in URI parameters: ${uri.queryParameters}',
        );
        return const AuthResult.error(
          'Invalid password reset link: No authorization code found',
        );
      }

      print('🔑 Found code/token: ${code.substring(0, 10)}...');

      // Exchange the code for a session using Supabase's exchangeCodeForSession method
      final response = await _client.auth.exchangeCodeForSession(code);

      print('✅ Session established successfully');
      return AuthResult.success(
        userId: response.session.user.id,
        email: response.session.user.email,
        userData: response.session.user.userMetadata,
      );
    } catch (e) {
      print('🚨 Error in exchangeCodeForSession: $e');
      _logError(
        'exchangeCodeForSession',
        e,
        context: 'uri: $passwordResetLinkUriAsString',
      );

      // Use the enhanced password error handler for better error messages
      final apiError = _handlePasswordError(e);
      return AuthResult.error(apiError.message);
    }
  }

  /// Update the current user's password
  /// This method should be called after a successful exchangeCodeForSession
  /// [rawStringPasswordField] - The new password in plain text
  Future<AuthResult> updatePassword(String rawStringPasswordField) async {
    print("updatePassword");
    try {
      _logAuthRequest(
        'updatePassword',
        'N/A',
        additionalData: {
          'hasValidSession': _client.auth.currentSession != null,
          'passwordLength': rawStringPasswordField.length,
        },
      );

      // Verify that we have a valid session
      final currentUser = _client.auth.currentUser;
      if (currentUser == null) {
        return const AuthResult.error(
          'No authenticated user found. Please use the password reset link again.',
        );
      }

      // Validate password strength (basic validation)
      if (rawStringPasswordField.length < 6) {
        return const AuthResult.error(
          'Password should be at least 6 characters long',
        );
      }

      // Update the user's password
      final response = await _client.auth.updateUser(
        UserAttributes(password: rawStringPasswordField),
      );

      if (response.user != null) {
        // Password updated successfully
        return AuthResult.success(
          userId: response.user!.id,
          email: response.user!.email,
          userData: {
            ...?response.user!.userMetadata,
            'password_updated_at': DateTime.now().toUtc().toIso8601String(),
          },
        );
      } else {
        return const AuthResult.error('Failed to update password');
      }
    } catch (e) {
      _logError('updatePassword', e);

      // Use the enhanced password error handler for better error messages
      final apiError = _handlePasswordError(e);
      return AuthResult.error(apiError.message);
    }
  }

  /// Verifies (and consumes — recovery tokens are single-use) the token hash
  /// from a reset-password deep link. On success the client holds a recovery
  /// session for the link's account; the caller decides whether to proceed.
  ///
  /// Called at link-open time, not at submit time, so expired/used/tampered
  /// links fail before any reset screen is shown (DL-104/DL-105/DL-106) and
  /// the link's account can be compared to the signed-in user (DL-103).
  Future<AuthResult> verifyRecoveryToken(String tokenHash) async {
    print("verifyRecoveryToken");
    try {
      final response = await _client.auth.verifyOTP(
        type: OtpType.recovery,
        tokenHash: tokenHash.trim(),
      );

      final user = response.user;
      if (response.session == null || user == null) {
        return const AuthResult.error(
          'This password reset link is invalid, has expired, or was already '
          'used. Please request a new one.',
        );
      }

      return AuthResult.success(userId: user.id, email: user.email);
    } on AuthRetryableFetchException catch (e) {
      _logError('verifyRecoveryToken', e);
      return const AuthResult.error(
        'Could not verify the password reset link. Please check your '
        'connection and open the link again.',
      );
    } on AuthException catch (e) {
      _logError('verifyRecoveryToken', e);
      return const AuthResult.error(
        'This password reset link is invalid, has expired, or was already '
        'used. Please request a new one.',
      );
    } catch (e) {
      _logError('verifyRecoveryToken', e);
      return const AuthResult.error(
        'Could not verify the password reset link. Please try again.',
      );
    }
  }

  Future<UserResponse> setNewPassword(String newPassword) async {
    // Update the password
    final updateResult = await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
    print('Password updated successfully!');
    return updateResult;
  }

  /// Organizations management panel
  @override
  Future<ApiResult<bool>> deleteOrganization(String id) async {
    print("deleteOrganization");
    try {
      _logRequest('delete', 'organizations', null, additionalInfo: 'id: $id');

      await _client.from('organizations').delete().eq('id', id);

      return const ApiResult.success(true);
    } catch (e) {
      _logError('deleteOrganization', e, context: 'id: $id');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<List<Organization>>> getAllOrganizations({
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
    int? limit,
    int? offset,
  }) async {
    print("getAllOrganizations");
    try {
      final queryInfo = {
        if (filters != null) 'filters': filters,
        if (orderBy != null) 'orderBy': orderBy,
        'ascending': ascending,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      };

      _logRequest('select_all', 'organizations', queryInfo);

      // Start with the base query (PostgrestFilterBuilder)
      var query = _client.from('organizations_overview').select();

      // Apply filters (still PostgrestFilterBuilder)
      if (filters != null) {
        filters.forEach((key, value) {
          query = query.eq(key, value);
        });
      }

      // Now we need to handle the transform operations that return PostgrestTransformBuilder
      dynamic finalQuery = query;

      // Apply ordering (returns PostgrestTransformBuilder)
      if (orderBy != null) {
        finalQuery = query.order(orderBy, ascending: ascending);
      }

      // Apply pagination (returns PostgrestTransformBuilder)
      if (offset != null && limit != null) {
        finalQuery = finalQuery.range(offset, offset + limit - 1);
      } else if (limit != null) {
        finalQuery = finalQuery.limit(limit);
      }

      // Execute the query
      final response = await finalQuery;

      // Cast the response to List<Map<String, dynamic>> to ensure proper typing
      final List<Map<String, dynamic>> responseList =
          List<Map<String, dynamic>>.from(response);

      return ApiResult.success(
        responseList.map((org) => Organization.fromJson(org)).toList(),
      );
    } catch (e) {
      _logError('getAllOrganizations', e);
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<List<UserProfile>>> getOrganizationManagers(
    String organizationId,
  ) async {
    print("getOrganizationManagers");
    try {
      _logRequest(
        'select_organization_managers',
        'admin_organizations',
        null,
        additionalInfo: 'organizationId: $organizationId',
      );

      // Query the admin_organizations junction table joined with user_profiles
      final response = await _client
          .from('admin_organizations')
          .select('''
          user_profiles!inner(
            id,
            email,
            full_name,
            role,
            profile_picture_url,
            created_at,
            updated_at
          )
        ''')
          .eq('organization_id', organizationId);

      // Extract user profiles from the response
      final List<UserProfile> managers = [];
      for (final item in response) {
        if (item['user_profiles'] != null) {
          managers.add(UserProfile.fromJson(item['user_profiles']));
        }
      }

      return ApiResult.success(managers);
    } catch (e) {
      _logError(
        'getOrganizationManagers',
        e,
        context: 'organizationId: $organizationId',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<List<UserProfile>>> getOrganizationFollowers(
    String organizationId,
  ) async {
    print("getOrganizationFollowers");
    try {
      _logRequest(
        'select_organization_followers',
        'user_follows',
        null,
        additionalInfo: 'organizationId: $organizationId',
      );

      final response = await _client
          .from('user_follows')
          .select('''
          followed_at,
          user_profiles!inner(
            id,
            email,
            username,
            full_name,
            profile_picture_url,
            role,
            created_at,
            updated_at
          )
        ''')
          .eq('organization_id', organizationId)
          .order('followed_at', ascending: false);

      final List<UserProfile> followers = [];
      for (final item in response) {
        final profileData = item['user_profiles'];
        if (profileData != null) {
          followers.add(
            UserProfile.fromJson(
              Map<String, dynamic>.from(profileData as Map<String, dynamic>),
            ),
          );
        }
      }

      return ApiResult.success(followers);
    } catch (e) {
      _logError(
        'getOrganizationFollowers',
        e,
        context: 'organizationId: $organizationId',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  // Alternative approach if you prefer a direct query on user_profiles
  @override
  Future<ApiResult<List<UserProfile>>> getOrganizationManagersAlt(
    String organizationId,
  ) async {
    print("getOrganizationManagersAlt");
    try {
      _logRequest(
        'select_organization_managers_alt',
        'user_profiles',
        null,
        additionalInfo: 'organizationId: $organizationId',
      );

      // Query user_profiles joined with admin_organizations
      final response = await _client
          .from('user_profiles')
          .select('''
          id,
          email,
          full_name,
          role,
          profile_picture_url,
          created_at,
          updated_at,
          admin_organizations!inner(organization_id)
        ''')
          .eq('admin_organizations.organization_id', organizationId);

      // Convert response to UserProfile objects
      final List<UserProfile> managers = response.map((item) {
        // Remove the junction table data before creating UserProfile
        final cleanData = Map<String, dynamic>.from(item);
        cleanData.remove('admin_organizations');
        return UserProfile.fromJson(cleanData);
      }).toList();

      return ApiResult.success(managers);
    } catch (e) {
      _logError(
        'getOrganizationManagersAlt',
        e,
        context: 'organizationId: $organizationId',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Assigns a user as an admin to an organization
  /// This promotes regular users to admin role and assigns them to the organization
  /// For existing admins, it just adds the organization assignment
  @override
  Future<ApiResult<bool>> assignUserAsOrganizationAdmin(
    String userEmail,
    String organizationId,
  ) async {
    print("assignUserAsOrganizationAdmin");
    try {
      _logRequest('assign_admin', 'user_profiles', {
        'email': userEmail,
        'organizationId': organizationId,
      });

      // Use the database function to handle the promotion/assignment
      final response = await _client.rpc(
        'promote_user_to_admin',
        params: {'user_email': userEmail, 'org_id': organizationId},
      );

      final success = response as bool? ?? false;

      if (success) {
        return const ApiResult.success(true);
      } else {
        return const ApiResult.error('Failed to assign user as admin');
      }
    } catch (e) {
      _logError(
        'assignUserAsOrganizationAdmin',
        e,
        context: 'email: $userEmail, orgId: $organizationId',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Assigns a user as an admin to an organization by organization name
  @override
  Future<ApiResult<bool>> assignUserAsOrganizationAdminByName(
    String userEmail,
    String organizationName,
  ) async {
    print("assignUserAsOrganizationAdminByName");
    try {
      _logRequest('assign_admin_by_name', 'user_profiles', {
        'email': userEmail,
        'organizationName': organizationName,
      });

      // Use the database function to handle the promotion/assignment by name
      final response = await _client.rpc(
        'promote_user_to_admin_by_org_name',
        params: {'user_email': userEmail, 'org_name': organizationName},
      );

      final success = response as bool? ?? false;

      if (success) {
        return const ApiResult.success(true);
      } else {
        return const ApiResult.error('Failed to assign user as admin');
      }
    } catch (e) {
      _logError(
        'assignUserAsOrganizationAdminByName',
        e,
        context: 'email: $userEmail, orgName: $organizationName',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Removes an admin from an organization
  /// If this is the admin's last organization, they will be demoted to regular user
  @override
  Future<ApiResult<bool>> removeAdminFromOrganization(
    String userEmail,
    String organizationId,
  ) async {
    print("removeAdminFromOrganization");
    try {
      _logRequest('remove_admin', 'admin_organizations', {
        'email': userEmail,
        'organizationId': organizationId,
      });

      // Use the database function to handle the removal
      final response = await _client.rpc(
        'remove_admin_from_organization',
        params: {'user_email': userEmail, 'org_id': organizationId},
      );

      final success = response as bool? ?? false;

      if (success) {
        return const ApiResult.success(true);
      } else {
        return const ApiResult.error(
          'Failed to remove admin from organization',
        );
      }
    } catch (e) {
      _logError(
        'removeAdminFromOrganization',
        e,
        context: 'email: $userEmail, orgId: $organizationId',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Gets all admins for a specific organization
  @override
  Future<ApiResult<List<UserProfile>>> getOrganizationAdmins(
    String organizationId,
  ) async {
    print("getOrganizationAdmins");
    try {
      _logRequest(
        'select_org_admins',
        'user_profiles',
        null,
        additionalInfo: 'organizationId: $organizationId',
      );

      final response = await _client
          .from('user_profiles')
          .select('''
          *,
          admin_organizations!inner(organization_id, assigned_at)
        ''')
          .eq('admin_organizations.organization_id', organizationId)
          .order('admin_organizations.assigned_at', ascending: false);

      final admins = (response as List<dynamic>).map((userData) {
        // Clean up the data by removing the junction table info
        final cleanData = Map<String, dynamic>.from(userData);
        cleanData.remove('admin_organizations');
        return UserProfile.fromJson(cleanData);
      }).toList();

      return ApiResult.success(admins);
    } catch (e) {
      _logError(
        'getOrganizationAdmins',
        e,
        context: 'organizationId: $organizationId',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Gets all organizations that a user is admin of
  @override
  Future<ApiResult<List<Organization>>> getUserAdminOrganizations(
    String userId,
  ) async {
    print("getUserAdminOrganizations");
    try {
      _logRequest(
        'select_user_admin_orgs',
        'organizations',
        null,
        additionalInfo: 'userId: $userId',
      );

      final response = await _client
          .from('organizations')
          .select('''
          *,
          organization_categories!inner(category_id),
          admin_organizations!inner(user_id, assigned_at)
        ''')
          .eq('admin_organizations.user_id', userId)
          .order('admin_organizations.assigned_at', ascending: false);

      final organizations = (response as List<dynamic>).map((orgData) {
        // Extract category IDs from the junction table data
        final categoryIds = <String>[];
        if (orgData['organization_categories'] != null) {
          final categories = orgData['organization_categories'];
          if (categories is List) {
            categoryIds.addAll(
              categories.map((cat) => cat['category_id'].toString()),
            );
          }
        }

        // Create a clean organization data map
        final cleanOrgData = Map<String, dynamic>.from(orgData);
        cleanOrgData.remove('organization_categories');
        cleanOrgData.remove('admin_organizations');
        cleanOrgData['category_ids'] = categoryIds;

        return Organization.fromJson(cleanOrgData);
      }).toList();

      return ApiResult.success(organizations);
    } catch (e) {
      _logError('getUserAdminOrganizations', e, context: 'userId: $userId');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Assigns multiple users as admins to an organization
  @override
  Future<ApiResult<List<AdminAssignmentResult>>> assignMultipleUsersAsAdmins(
    List<String> userEmails,
    String organizationId,
  ) async {
    print("assignMultipleUsersAsAdmins");
    try {
      _logRequest('assign_multiple_admins', 'user_profiles', {
        'emails': userEmails,
        'organizationId': organizationId,
      });

      final response = await _client.rpc(
        'promote_multiple_users_to_admin',
        params: {'user_emails': userEmails, 'org_id': organizationId},
      );

      final results = (response as List<dynamic>)
          .map((result) => AdminAssignmentResult.fromJson(result))
          .toList();

      return ApiResult.success(results);
    } catch (e) {
      _logError(
        'assignMultipleUsersAsAdmins',
        e,
        context: 'emails: $userEmails, orgId: $organizationId',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Checks if a user is an admin of a specific organization
  @override
  Future<ApiResult<bool>> isUserAdminOfOrganization(
    String userId,
    String organizationId,
  ) async {
    print("isUserAdminOfOrganization");
    try {
      _logRequest('check_admin_status', 'admin_organizations', {
        'userId': userId,
        'organizationId': organizationId,
      });

      final response = await _client
          .from('admin_organizations')
          .select('user_id')
          .eq('user_id', userId)
          .eq('organization_id', organizationId)
          .maybeSingle();

      final isAdmin = response != null;
      return ApiResult.success(isAdmin);
    } catch (e) {
      _logError(
        'isUserAdminOfOrganization',
        e,
        context: 'userId: $userId, orgId: $organizationId',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Upload a file to Supabase Storage
  /// [bucketName] - The name of the storage bucket
  /// [filePath] - The path where the file will be stored in the bucket
  /// [fileBytes] - The file data as bytes
  /// [contentType] - The MIME type of the file (e.g., 'image/jpeg', 'image/png')
  @override
  Future<ApiResult<String>> uploadFile({
    required String bucketName,
    required String filePath,
    required Uint8List fileBytes,
    String? contentType,
  }) async {
    print("uploadFile to bucket: $bucketName");
    try {
      _logRequest('upload_file', 'storage', {
        'bucketName': bucketName,
        'filePath': filePath,
        'fileSize': fileBytes.length,
        'contentType': contentType,
      });

      // Upload the file to Supabase Storage
      final response = await _client.storage
          .from(bucketName)
          .uploadBinary(
            filePath,
            fileBytes,
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: true, // Allow overwriting existing files
            ),
          );

      // Get the public URL for the uploaded file
      final publicUrl = _client.storage.from(bucketName).getPublicUrl(filePath);

      if (DEBUG) {
        print('✅ File uploaded successfully: $publicUrl');
      }

      return ApiResult.success(publicUrl);
    } catch (e) {
      _logError(
        'uploadFile',
        e,
        context: 'bucket: $bucketName, path: $filePath',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Upload a profile picture for a user
  /// [userId] - The user ID
  /// [fileBytes] - The image file data as bytes
  /// [fileName] - The original filename (used to determine file extension)
  /// [contentType] - The MIME type of the image
  @override
  Future<ApiResult<String>> uploadProfilePicture(
    Uint8List imageBytes, { // TODO Is imageBytes required?
    required String userId,
    required Uint8List fileBytes,
    required String fileName,
    String? contentType,
  }) async {
    print("uploadProfilePicture for user: $userId");
    try {
      // Extract file extension from filename
      final extension = fileName.split('.').last.toLowerCase();

      // Validate file type
      if (!['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension)) {
        return const ApiResult.error(
          'Invalid file type. Only JPG, PNG, GIF, and WebP images are allowed.',
        );
      }

      // Generate unique file path
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '$userId/avatar_$timestamp.$extension';

      // Determine content type if not provided
      contentType ??= _getContentTypeFromExtension(extension);

      // Upload to the 'avatars' bucket
      final uploadResult = await uploadFile(
        bucketName: 'avatars',
        filePath: filePath,
        fileBytes: fileBytes,
        contentType: contentType,
      );

      if (uploadResult.isSuccess) {
        // Update user profile with the new picture URL
        final updateResult = await updateUserProfile(userId, {
          'profile_picture_url': uploadResult.data,
        });

        if (updateResult.isSuccess) {
          return ApiResult.success(uploadResult.data!);
        } else {
          // Upload succeeded but profile update failed
          // You might want to delete the uploaded file here
          return ApiResult.error(
            'Failed to update profile: ${updateResult.error}',
          );
        }
      } else {
        return ApiResult.error(uploadResult.error!);
      }
    } catch (e) {
      _logError('uploadProfilePicture', e, context: 'userId: $userId');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Upload an organization logo
  /// [organizationId] - The organization ID
  /// [fileBytes] - The image file data as bytes
  /// [fileName] - The original filename
  /// [contentType] - The MIME type of the image
  @override
  Future<ApiResult<String>> uploadOrganizationLogo({
    required String organizationId,
    required Uint8List fileBytes,
    required String fileName,
    String? contentType,
  }) async {
    print("uploadOrganizationLogo for org: $organizationId");
    try {
      // Extract file extension from filename
      final extension = fileName.split('.').last.toLowerCase();

      // Validate file type
      if (!['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension)) {
        return const ApiResult.error(
          'Invalid file type. Only JPG, PNG, GIF, and WebP images are allowed.',
        );
      }

      // Generate unique file path
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '$organizationId/logo_$timestamp.$extension';

      // Determine content type if not provided
      contentType ??= _getContentTypeFromExtension(extension);

      // Upload to the 'logos' bucket
      final uploadResult = await uploadFile(
        bucketName: 'logos',
        filePath: filePath,
        fileBytes: fileBytes,
        contentType: contentType,
      );

      if (uploadResult.isSuccess) {
        // Update organization with the new logo URL
        final updateResult = await update<Map<String, dynamic>>(
          'organizations',
          organizationId,
          {'logo_url': uploadResult.data},
        );

        if (updateResult.isSuccess) {
          return ApiResult.success(uploadResult.data!);
        } else {
          return ApiResult.error(
            'Failed to update organization: ${updateResult.error}',
          );
        }
      } else {
        return ApiResult.error(uploadResult.error!);
      }
    } catch (e) {
      _logError('uploadOrganizationLogo', e, context: 'orgId: $organizationId');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Upload a file (images, PDFs, SVGs)
  /// [userId] - The user ID (optional, for organizing files by user)
  /// [fileBytes] - The file data as bytes
  /// [fileName] - The original filename (used to determine file extension)
  /// [contentType] - The MIME type of the file
  /// [subFolder] - Optional subfolder within the uploads bucket
  @override
  Future<ApiResult<String>> uploadGenericFile({
    String? userId,
    required Uint8List fileBytes,
    required String fileName,
    String? contentType,
    String? subFolder,
  }) async {
    print("uploadFile: $fileName${userId != null ? ' for user: $userId' : ''}");
    try {
      // Extract file extension from filename
      final extension = fileName.split('.').last.toLowerCase();

      // Validate file type - supports images, PDFs, and SVGs
      final allowedExtensions = [
        'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff', 'tif', // Images
        'pdf', // PDFs
        'svg', // SVGs
      ];

      if (!allowedExtensions.contains(extension)) {
        return const ApiResult.error(
          'Invalid file type. Only images (JPG, PNG, GIF, WebP, BMP, TIFF), PDFs, and SVGs are allowed.',
        );
      }

      // Generate unique file path
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final sanitizedFileName = fileName.replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );

      String filePath;
      if (userId != null && subFolder != null) {
        filePath = '$userId/$subFolder/${timestamp}_$sanitizedFileName';
      } else if (userId != null) {
        filePath = '$userId/${timestamp}_$sanitizedFileName';
      } else if (subFolder != null) {
        filePath = '$subFolder/${timestamp}_$sanitizedFileName';
      } else {
        filePath = '${timestamp}_$sanitizedFileName';
      }

      // Determine content type if not provided
      contentType ??= _getContentTypeFromExtension(extension);

      // Upload to the 'uploads' bucket
      final uploadResult = await uploadFile(
        bucketName: 'uploads',
        filePath: filePath,
        fileBytes: fileBytes,
        contentType: contentType,
      );

      if (uploadResult.isSuccess) {
        return ApiResult.success(uploadResult.data!);
      } else {
        return ApiResult.error(uploadResult.error!);
      }
    } catch (e) {
      _logError(
        'uploadFile',
        e,
        context:
            'fileName: $fileName${userId != null ? ', userId: $userId' : ''}',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Helper method to determine content type from file extension
  String _getContentTypeFromExtension(String extension) {
    switch (extension.toLowerCase()) {
      // Images
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'tiff':
      case 'tif':
        return 'image/tiff';
      // SVG
      case 'svg':
        return 'image/svg+xml';
      // PDF
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  /// Delete a file from Supabase Storage
  /// [bucketName] - The name of the storage bucket
  /// [filePath] - The path of the file to delete
  @override
  Future<ApiResult<bool>> deleteFile({
    required String bucketName,
    required String filePath,
  }) async {
    print("deleteFile from bucket: $bucketName");
    try {
      _logRequest('delete_file', 'storage', {
        'bucketName': bucketName,
        'filePath': filePath,
      });

      final response = await _client.storage.from(bucketName).remove([
        filePath,
      ]);

      if (response.isNotEmpty) {
        return const ApiResult.success(true);
      } else {
        return const ApiResult.error('File not found or already deleted');
      }
    } catch (e) {
      _logError(
        'deleteFile',
        e,
        context: 'bucket: $bucketName, path: $filePath',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Resize image if needed (you'll need to implement this based on your needs)
  /// This is a placeholder - you might want to use packages like 'image' for resizing
  Future<Uint8List> _resizeImageIfNeeded(
    Uint8List imageBytes,
    int maxWidth,
    int maxHeight,
  ) async {
    // TODO: Implement image resizing logic
    // You can use packages like 'image' or 'flutter_image_compress'
    return imageBytes;
  }

  /// Validate image file
  bool _isValidImageFile(Uint8List fileBytes) {
    // Check file signature (magic numbers)
    if (fileBytes.length < 4) return false;

    // JPEG: FF D8 FF
    if (fileBytes[0] == 0xFF && fileBytes[1] == 0xD8 && fileBytes[2] == 0xFF) {
      return true;
    }

    // PNG: 89 50 4E 47
    if (fileBytes[0] == 0x89 &&
        fileBytes[1] == 0x50 &&
        fileBytes[2] == 0x4E &&
        fileBytes[3] == 0x47) {
      return true;
    }

    // GIF: 47 49 46 38
    if (fileBytes[0] == 0x47 &&
        fileBytes[1] == 0x49 &&
        fileBytes[2] == 0x46 &&
        fileBytes[3] == 0x38) {
      return true;
    }

    // WebP: 52 49 46 46 ... 57 45 42 50
    if (fileBytes.length >= 12 &&
        fileBytes[0] == 0x52 &&
        fileBytes[1] == 0x49 &&
        fileBytes[2] == 0x46 &&
        fileBytes[3] == 0x46 &&
        fileBytes[8] == 0x57 &&
        fileBytes[9] == 0x45 &&
        fileBytes[10] == 0x42 &&
        fileBytes[11] == 0x50) {
      return true;
    }

    return false;
  }

  @override
  Future<ApiResult<bool>> updateOrganization(Organization updatedOrg) async {
    print("updateOrganization");
    try {
      // 1. Update the main organization data (only fields that exist in the table)
      final organizationData = {
        'name': updatedOrg.name,
        'logo_url': updatedOrg.logoUrl,
        // Don't include follower_count as it's managed by triggers
        // Don't include created_at/updated_at as they're managed by triggers
      };

      _logRequest(
        'update',
        'organizations',
        organizationData,
        additionalInfo: 'id: ${updatedOrg.id}',
      );

      await _client
          .from('organizations')
          .update(organizationData)
          .eq('id', updatedOrg.id);

      // 2. Handle category updates separately
      if (updatedOrg.categoryIds.isNotEmpty) {
        await _updateOrganizationCategories(
          updatedOrg.id,
          updatedOrg.categoryIds,
        );
      } else {
        // If no categories are provided, we still need at least one category per business rules
        throw Exception('Organization must belong to at least one category');
      }

      return const ApiResult.success(true);
    } catch (e) {
      _logError('updateOrganization', e, context: 'id: ${updatedOrg.id}');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  Future<void> _updateOrganizationCategories(
    String organizationId,
    List<String> categoryIds,
  ) async {
    try {
      // Use a transaction-like approach to ensure data consistency

      // 1. First, get current categories to compare
      final currentCategories = await _client
          .from('organization_categories')
          .select('category_id')
          .eq('organization_id', organizationId);

      final currentCategoryIds = currentCategories
          .map<String>((row) => row['category_id'] as String)
          .toSet();

      final newCategoryIds = categoryIds.toSet();

      // 2. Find categories to remove and add
      final categoriesToRemove = currentCategoryIds.difference(newCategoryIds);
      final categoriesToAdd = newCategoryIds.difference(currentCategoryIds);

      // 3. Remove categories that are no longer needed
      if (categoriesToRemove.isNotEmpty) {
        await _client
            .from('organization_categories')
            .delete()
            .eq('organization_id', organizationId)
            .inFilter('category_id', categoriesToRemove.toList());
      }

      // 4. Add new categories
      if (categoriesToAdd.isNotEmpty) {
        final categoryData = categoriesToAdd
            .map(
              (categoryId) => {
                'organization_id': organizationId,
                'category_id': categoryId,
              },
            )
            .toList();

        await _client.from('organization_categories').insert(categoryData);
      }
    } catch (e) {
      print('Error updating organization categories: $e');
      rethrow;
    }
  }

  /// Gets a list of organization IDs that a user follows
  /// [userId] - The user ID to get followed organizations for
  /// Returns a list of organization IDs
  @override
  Future<ApiResult<List<String>>> getUserFollowedOrganizationIds({
    required String userId,
  }) async {
    print("getUserFollowedOrganizationIds");
    try {
      _logRequest(
        'select_user_followed_org_ids',
        'user_follows',
        null,
        additionalInfo: 'userId: $userId',
      );

      final response = await _client
          .from('user_follows')
          .select('organization_id')
          .eq('user_id', userId)
          .order('followed_at', ascending: false);

      // Extract organization IDs from the response
      final organizationIds = (response as List<dynamic>)
          .map((row) => row['organization_id'] as String)
          .toList();

      if (DEBUG) {
        print(
          '✅ Found ${organizationIds.length} followed organizations for user $userId',
        );
      }

      return ApiResult.success(organizationIds);
    } catch (e) {
      _logError(
        'getUserFollowedOrganizationIds',
        e,
        context: 'userId: $userId',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Gets full organization objects that a user follows
  /// [userId] - The user ID to get followed organizations for
  /// Returns a list of Organization objects with their details
  @override
  Future<ApiResult<List<Organization>>> getUserFollowedOrganizations({
    required String userId,
  }) async {
    print("getUserFollowedOrganizations");
    try {
      _logRequest(
        'select_user_followed_orgs',
        'user_follows',
        null,
        additionalInfo: 'userId: $userId',
      );

      // Step 1: get the org IDs this user follows, ordered by followed_at.
      final followsResponse = await _client
          .from('user_follows')
          .select('organization_id')
          .eq('user_id', userId)
          .order('followed_at', ascending: false);

      if (followsResponse.isEmpty) {
        return ApiResult.success([]);
      }

      final orderedOrgIds = List<String>.from(
        followsResponse.map((row) => row['organization_id'] as String),
      );

      // Step 2: fetch full org details (including live follower_count,
      // is_following, and category_ids) from the overview view in one query.
      final orgsResponse = await _client
          .from('organizations_overview')
          .select()
          .inFilter('id', orderedOrgIds);

      final orgMap = <String, Organization>{};
      for (final row in List<Map<String, dynamic>>.from(orgsResponse)) {
        final org = Organization.fromJson(row);
        orgMap[org.id] = org;
      }

      // Preserve the followed_at ordering from step 1.
      final organizations = orderedOrgIds
          .map((id) => orgMap[id])
          .whereType<Organization>()
          .toList();

      if (DEBUG) {
        print(
          '✅ Found ${organizations.length} followed organizations with details for user $userId',
        );
      }

      return ApiResult.success(organizations);
    } catch (e) {
      _logError('getUserFollowedOrganizations', e, context: 'userId: $userId');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Checks if a user follows a specific organization
  /// [userId] - The user ID
  /// [organizationId] - The organization ID to check
  /// Returns true if the user follows the organization, false otherwise
  @override
  Future<ApiResult<bool>> isUserFollowingOrganization(
    String userId,
    String organizationId,
  ) async {
    print("isUserFollowingOrganization");
    try {
      _logRequest('check_user_following', 'user_follows', {
        'userId': userId,
        'organizationId': organizationId,
      });

      final response = await _client
          .from('user_follows')
          .select('id')
          .eq('user_id', userId)
          .eq('organization_id', organizationId)
          .maybeSingle();

      final isFollowing = response != null;

      if (DEBUG) {
        print(
          '✅ User $userId ${isFollowing ? 'is' : 'is not'} following organization $organizationId',
        );
      }

      return ApiResult.success(isFollowing);
    } catch (e) {
      _logError(
        'isUserFollowingOrganization',
        e,
        context: 'userId: $userId, organizationId: $organizationId',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Follow an organization
  /// [userId] - The user ID
  /// [organizationId] - The organization ID to follow
  /// Returns true if successfully followed, false if already following
  @override
  Future<ApiResult<bool>> followOrganization(
    String userId,
    String organizationId,
  ) async {
    print("followOrganization");
    try {
      _logRequest('follow_organization', 'user_follows', {
        'userId': userId,
        'organizationId': organizationId,
      });

      // Check if already following
      final isAlreadyFollowing = await isUserFollowingOrganization(
        userId,
        organizationId,
      );
      if (!isAlreadyFollowing.isSuccess) {
        return ApiResult.error(isAlreadyFollowing.error!);
      }

      if (isAlreadyFollowing.data!) {
        return const ApiResult.error(
          'User is already following this organization',
        );
      }

      // Create follow relationship
      final followData = {
        'user_id': userId,
        'organization_id': organizationId,
        'followed_at': DateTime.now().toUtc().toIso8601String(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      await _client.from('user_follows').insert(followData);

      if (DEBUG) {
        print(
          '✅ User $userId successfully followed organization $organizationId',
        );
      }

      AmplitudeService.instance.logEvent('channel_followed', eventProperties: {'organization_id': organizationId});
      return const ApiResult.success(true);
    } catch (e) {
      _logError(
        'followOrganization',
        e,
        context: 'userId: $userId, organizationId: $organizationId',
      );
      final apiError = _handleError(e);
      AmplitudeService.instance.logEvent('channel_follow_error', eventProperties: {'organization_id': organizationId, 'error': apiError.code});
      return ApiResult.error(apiError.message);
    }
  }

  /// Unfollow an organization
  /// [userId] - The user ID
  /// [organizationId] - The organization ID to unfollow
  /// Returns true if successfully unfollowed, false if wasn't following
  @override
  Future<ApiResult<bool>> unfollowOrganization(
    String userId,
    String organizationId,
  ) async {
    print("unfollowOrganization");
    try {
      _logRequest('unfollow_organization', 'user_follows', {
        'userId': userId,
        'organizationId': organizationId,
      });

      // Check if currently following
      final isCurrentlyFollowing = await isUserFollowingOrganization(
        userId,
        organizationId,
      );
      if (!isCurrentlyFollowing.isSuccess) {
        return ApiResult.error(isCurrentlyFollowing.error!);
      }

      if (!isCurrentlyFollowing.data!) {
        return const ApiResult.error('User is not following this organization');
      }

      // Remove follow relationship
      await _client
          .from('user_follows')
          .delete()
          .eq('user_id', userId)
          .eq('organization_id', organizationId);

      if (DEBUG) {
        print(
          '✅ User $userId successfully unfollowed organization $organizationId',
        );
      }

      AmplitudeService.instance.logEvent('channel_unfollowed', eventProperties: {'organization_id': organizationId});
      return const ApiResult.success(true);
    } catch (e) {
      _logError(
        'unfollowOrganization',
        e,
        context: 'userId: $userId, organizationId: $organizationId',
      );
      final apiError = _handleError(e);
      AmplitudeService.instance.logEvent('channel_unfollow_error', eventProperties: {'organization_id': organizationId, 'error': apiError.code});
      return ApiResult.error(apiError.message);
    }
  }

  // Add these methods to your SupabaseApiService class

  // ============================================================================
  // POST REACTIONS API METHODS
  // ============================================================================

  /// Get all reactions for a specific post
  @override
  Future<ApiResult<List<PostReaction>>> getPostReactions(String postId) async {
    print("getPostReactions");
    try {
      _logRequest(
        'select',
        'post_reactions',
        null,
        additionalInfo: 'postId: $postId',
      );

      final response = await _client
          .from('post_reactions')
          .select(
            '*, user_profiles!inner(id, username, full_name, email, created_at, updated_at, profile_picture_url)',
          )
          .eq('post_id', postId)
          .order('created_at', ascending: false);

      final reactions = (response as List)
          .map((json) => PostReaction.fromJson(json))
          .toList();

      return ApiResult.success(reactions);
    } catch (e) {
      _logError('getPostReactions', e, context: 'postId: $postId');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Add or update a user's reaction to a post
  @override
  Future<ApiResult<PostReaction>> upsertPostReaction(
    String postId,
    List<String> emojiReactions,
  ) async {
    print("upsertPostReaction");
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        return ApiResult.error('User not authenticated');
      }

      // Validate emoji reactions
      if (emojiReactions.isEmpty) {
        return ApiResult.error('At least one emoji reaction is required');
      }

      // Remove duplicates while preserving order
      final uniqueEmojis = emojiReactions.toSet().toList();

      _logRequest('upsert', 'post_reactions', {
        'post_id': postId,
        'user_id': userId,
        'emoji_reactions': uniqueEmojis,
      });

      // Use the database function for upsert
      final response = await _client.rpc(
        'upsert_post_reaction',
        params: {
          'p_post_id': postId,
          'p_user_id': userId,
          'p_emoji_reactions': uniqueEmojis,
        },
      );

      if (response == true) {
        // Fetch the updated reaction
        final reactionResponse = await _client
            .from('post_reactions')
            .select(
              '*, user_profiles!inner(id, username, email, full_name, profile_picture_url, created_at, updated_at)',
            )
            .eq('post_id', postId)
            .eq('user_id', userId)
            .single();

        print("REACTION RESPONSE: ${reactionResponse.toString()}");
        print("REACTION RESPONSE type: ${reactionResponse.runtimeType}");
        AmplitudeService.instance.logEvent('post_reacted', eventProperties: {'post_id': postId, 'emojis': uniqueEmojis});
        return ApiResult.success(PostReaction.fromJson(reactionResponse));
      } else {
        AmplitudeService.instance.logEvent('post_reaction_error', eventProperties: {'post_id': postId, 'error': 'upsert_failed'});
        return ApiResult.error('Failed to upsert reaction');
      }
    } catch (e) {
      _logError('upsertPostReaction', e, context: 'postId: $postId');
      final apiError = _handleError(e);
      AmplitudeService.instance.logEvent('post_reaction_error', eventProperties: {'post_id': postId, 'error': apiError.code});
      return ApiResult.error(apiError.message);
    }
  }

  /// Remove a user's reaction from a post
  @override
  Future<ApiResult<bool>> removePostReaction(String postId) async {
    print("removePostReaction");
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        return ApiResult.error('User not authenticated');
      }

      _logRequest(
        'delete',
        'post_reactions',
        null,
        additionalInfo: 'postId: $postId, userId: $userId',
      );

      // Use the database function for removal
      final response = await _client.rpc(
        'remove_post_reaction',
        params: {'p_post_id': postId, 'p_user_id': userId},
      );

      if (response == true) AmplitudeService.instance.logEvent('post_reaction_removed', eventProperties: {'post_id': postId});
      return ApiResult.success(response == true);
    } catch (e) {
      _logError('removePostReaction', e, context: 'postId: $postId');
      final apiError = _handleError(e);
      AmplitudeService.instance.logEvent('post_reaction_error', eventProperties: {'post_id': postId, 'error': apiError.code});
      return ApiResult.error(apiError.message);
    }
  }

  /// Get reaction summary for a post (total counts)
  @override
  Future<ApiResult<PostReactionSummary>> getPostReactionSummary(
    String postId,
  ) async {
    print("getPostReactionSummary");
    try {
      _logRequest(
        'select',
        'post_reaction_summary',
        null,
        additionalInfo: 'postId: $postId',
      );

      final response = await _client
          .from('post_reaction_summary')
          .select()
          .eq('post_id', postId)
          .single();

      return ApiResult.success(PostReactionSummary.fromJson(response));
    } catch (e) {
      _logError('getPostReactionSummary', e, context: 'postId: $postId');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Get emoji counts for a post (individual emoji statistics)
  @override
  Future<ApiResult<List<EmojiCount>>> getPostEmojiCounts(String postId) async {
    print("getPostEmojiCounts");
    try {
      _logRequest(
        'select',
        'post_emoji_counts',
        null,
        additionalInfo: 'postId: $postId',
      );

      final response = await _client
          .from('post_emoji_counts')
          .select()
          .eq('post_id', postId)
          .order('count', ascending: false);

      final emojiCounts = (response as List)
          .map((json) => EmojiCount.fromJson(json))
          .toList();

      return ApiResult.success(emojiCounts);
    } catch (e) {
      _logError('getPostEmojiCounts', e, context: 'postId: $postId');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Get the current user's reaction for a specific post
  @override
  Future<ApiResult<PostReaction?>> getUserReactionForPost(String postId) async {
    print("getUserReactionForPost");
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        return ApiResult.error('User not authenticated');
      }

      _logRequest(
        'select',
        'post_reactions',
        null,
        additionalInfo: 'postId: $postId, userId: $userId',
      );

      final response = await _client
          .from('post_reactions')
          .select(
            '*, user_profiles!inner(id, username, full_name, profile_picture_url)',
          )
          .eq('post_id', postId)
          .eq('user_id', userId)
          .maybeSingle(); // Use maybeSingle to handle case where no reaction exists

      if (response == null) {
        return ApiResult.success(null); // No reaction found
      }

      return ApiResult.success(PostReaction.fromJson(response));
    } catch (e) {
      _logError('getUserReactionForPost', e, context: 'postId: $postId');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  // ============================================================================
  // CATEGORY COUNTS API METHODS
  // ============================================================================

  /// Get organization counts for all categories
  @override
  Future<ApiResult<List<CategoryCount>>> getCategoryOrganizationCounts() async {
    print("getCategoryOrganizationCounts");
    try {
      _logRequest('select', 'category_organization_counts', null);

      final response = await _client
          .from('category_organization_counts')
          .select()
          .order('organization_count', ascending: false);

      final categoryCounts = (response as List)
          .map((json) => CategoryCount.fromJson(json))
          .toList();
      debugLogMagenta("Category counts: $response");

      return ApiResult.success(categoryCounts);
    } catch (e) {
      _logError('getCategoryOrganizationCounts', e);
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Get category counts as a JSON map (categoryId -> count)
  @override
  Future<ApiResult<Map<String, int>>> getCategoryCountsMap() async {
    print("getCategoryCountsMap");
    try {
      _logRequest('rpc', 'get_category_counts_json', null);

      final response = await _client.rpc('get_category_counts_json');

      // The response is a JSONB object from PostgreSQL
      final Map<String, dynamic> jsonResponse =
          response as Map<String, dynamic>;

      // Convert to Map<String, int>
      final Map<String, int> categoryCountsMap = {};
      jsonResponse.forEach((key, value) {
        categoryCountsMap[key] = (value as num).toInt();
      });

      return ApiResult.success(categoryCountsMap);
    } catch (e) {
      _logError('getCategoryCountsMap', e);
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  // ============================================================================
  // BATCH OPERATIONS (OPTIONAL)
  // ============================================================================

  /// Get reactions for multiple posts at once
  @override
  Future<ApiResult<Map<String, List<PostReaction>>>> getMultiplePostReactions(
    List<String> postIds,
  ) async {
    print("getMultiplePostReactions");
    try {
      if (postIds.isEmpty) {
        return ApiResult.success({});
      }

      _logRequest(
        'select',
        'post_reactions',
        null,
        additionalInfo: 'postIds: ${postIds.length} posts',
      );

      final response = await _client
          .from('post_reactions')
          .select(
            '*, user_profiles!inner(id, username, full_name, profile_picture_url)',
          )
          .inFilter('post_id', postIds)
          .order('created_at', ascending: false);

      // Group reactions by post ID
      final Map<String, List<PostReaction>> groupedReactions = {};
      for (final json in response as List) {
        final reaction = PostReaction.fromJson(json);
        final postId = reaction.postId;

        groupedReactions.putIfAbsent(postId, () => []);
        groupedReactions[postId]!.add(reaction);
      }

      // Ensure all requested post IDs are in the result (even if empty)
      for (final postId in postIds) {
        groupedReactions.putIfAbsent(postId, () => []);
      }

      return ApiResult.success(groupedReactions);
    } catch (e) {
      _logError(
        'getMultiplePostReactions',
        e,
        context: 'postIds: ${postIds.length}',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Get reaction summaries for multiple posts at once
  @override
  Future<ApiResult<Map<String, PostReactionSummary>>>
  getMultiplePostReactionSummaries(List<String> postIds) async {
    print("getMultiplePostReactionSummaries");
    try {
      if (postIds.isEmpty) {
        return ApiResult.success({});
      }

      _logRequest(
        'select',
        'post_reaction_summary',
        null,
        additionalInfo: 'postIds: ${postIds.length} posts',
      );

      final response = await _client
          .from('post_reaction_summary')
          .select()
          .inFilter('post_id', postIds);

      // Convert to map
      final Map<String, PostReactionSummary> summariesMap = {};
      for (final json in response as List) {
        final summary = PostReactionSummary.fromJson(json);
        summariesMap[summary.postId] = summary;
      }

      return ApiResult.success(summariesMap);
    } catch (e) {
      _logError(
        'getMultiplePostReactionSummaries',
        e,
        context: 'postIds: ${postIds.length}',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Check if current user has reacted to a specific post
  @override
  Future<ApiResult<bool>> hasUserReactedToPost(String postId) async {
    print("hasUserReactedToPost");
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        return ApiResult.error('User not authenticated');
      }

      _logRequest(
        'select',
        'post_reactions',
        null,
        additionalInfo: 'postId: $postId, userId: $userId',
      );

      final response = await _client
          .from('post_reactions')
          .select('id')
          .eq('post_id', postId)
          .eq('user_id', userId)
          .maybeSingle();

      return ApiResult.success(response != null);
    } catch (e) {
      _logError('hasUserReactedToPost', e, context: 'postId: $postId');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  /// Get total reaction count for a post (quick count without fetching all data)
  @override
  Future<ApiResult<int>> getPostReactionCount(String postId) async {
    print("getPostReactionCount");
    try {
      _logRequest(
        'select',
        'post_reactions',
        null,
        additionalInfo: 'postId: $postId (count only)',
      );

      final response = await _client
          .from('post_reactions')
          .count(CountOption.exact)
          .eq('post_id', postId);

      return ApiResult.success(response ?? 0);
    } catch (e) {
      _logError('getPostReactionCount', e, context: 'postId: $postId');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  // ============================================================================
  // STREAM METHODS FOR REAL-TIME UPDATES
  // ============================================================================

  /// Stream reactions for a specific post (real-time updates)
  @override
  Stream<List<PostReaction>> streamPostReactions(String postId) {
    print("streamPostReactions");
    return _client
        .from('post_reactions')
        .stream(primaryKey: ['id'])
        .eq('post_id', postId)
        .order('created_at', ascending: false)
        .map((data) => data.map((json) => PostReaction.fromJson(json)).toList())
        .handleError((error) {
          _logError('streamPostReactions', error, context: 'postId: $postId');
        });
  }

  /// Stream category organization counts (real-time updates)
  @override
  Stream<List<CategoryCount>> streamCategoryOrganizationCounts() {
    print("streamCategoryOrganizationCounts");
    return _client
        .from('category_organization_counts')
        .stream(primaryKey: ['category_id'])
        .order('organization_count', ascending: false)
        .map(
          (data) => data.map((json) => CategoryCount.fromJson(json)).toList(),
        )
        .handleError((error) {
          _logError('streamCategoryOrganizationCounts', error);
        });
  }

  // ============================================================================
  // USAGE EXAMPLES
  // ============================================================================

  /*
// Example 1: Add reaction to a post
final result = await apiService.upsertPostReaction('post-id', ['👍', '❤️']);
if (result.isSuccess) {
  print('Reaction added: ${result.data!.emojiReactions}');
}

// Example 2: Get all reactions for a post
final reactions = await apiService.getPostReactions('post-id');
if (reactions.isSuccess) {
  for (final reaction in reactions.data!) {
    print('${reaction.userProfile?.username}: ${reaction.emojiReactions}');
  }
}

// Example 3: Get category counts
final categoryCounts = await apiService.getCategoryOrganizationCounts();
if (categoryCounts.isSuccess) {
  for (final category in categoryCounts.data!) {
    print('${category.categoryName}: ${category.organizationCount} organizations');
  }
}

// Example 4: Get category counts as map for quick lookup
final countsMap = await apiService.getCategoryCountsMap();
if (countsMap.isSuccess) {
  final count = countsMap.data!['category-id-here'] ?? 0;
  print('Category has $count organizations');
}

// Example 5: Stream real-time reactions
apiService.streamPostReactions('post-id').listen((reactions) {
  print('Updated reactions count: ${reactions.length}');
});
*/

  // /// Get the count of organizations a user follows
  // /// [userId] - The user ID
  // /// Returns the count of followed organizations
  // @override
  // Future<ApiResult<int>> getUserFollowedOrganizationsCount(
  //     String userId,
  //     ) async {
  //   print("getUserFollowedOrganizationsCount");
  //   try {
  //     _logRequest(
  //       'count_user_followed_orgs',
  //       'user_follows',
  //       null,
  //       additionalInfo: 'userId: $userId',
  //     );
  //
  //     final response = await _client
  //         .from('user_follows')
  //         .select('id', const FetchOptions(count: CountOption.exact))
  //         .eq('user_id', userId);
  //
  //     final count = response.count ?? 0;
  //
  //     if (DEBUG) {
  //       print('✅ User $userId follows $count organizations');
  //     }
  //
  //     return ApiResult.success(count);
  //   } catch (e) {
  //     _logError('getUserFollowedOrganizationsCount', e, context: 'userId: $userId');
  //     final apiError = _handleError(e);
  //     return ApiResult.error(apiError.message);
  //   }
  // }

  // Alternative simpler approach (delete all and re-insert)
  Future<void> _updateOrganizationCategoriesSimple(
    String organizationId,
    List<String> categoryIds,
  ) async {
    try {
      // 1. Delete existing categories for the organization
      await _client
          .from('organization_categories')
          .delete()
          .eq('organization_id', organizationId);

      // 2. Insert new categories
      if (categoryIds.isNotEmpty) {
        final categoryData = categoryIds
            .map(
              (categoryId) => {
                'organization_id': organizationId,
                'category_id': categoryId,
              },
            )
            .toList();

        await _client.from('organization_categories').insert(categoryData);
      }
    } catch (e) {
      print('Error updating organization categories: $e');
      rethrow;
    }
  }

  Future<void> _deleteOrganizationCategories(String organizationId) async {
    await _client
        .from('organization_categories')
        .delete()
        .eq('organization_id', organizationId);
  }

  String _getEnvironmentRedirectUrl() {
    switch (FlavorConfig.appFlavor) {
      case Flavor.development:
        return 'com.magicvalleycentral.mvcapp.qa';
      case Flavor.production:
        return 'com.magicvalleycentral.mvcapp';
      default:
        return 'com.magicvalleycentral.mvcapp';
    }
  }

  /// Get the current bundle identifier based on the environment
  String _getCurrentBundleIdentifier() {
    switch (FlavorConfig.appFlavor) {
      case Flavor.development:
        return 'com.magicvalleycentral.mvcapp.qa';
      case Flavor.production:
        return 'com.magicvalleycentral.mvcapp';
      default:
        return 'com.magicvalleycentral.mvcapp';
    }
  }

  // ============================================================================
  // FCM TOKEN METHODS
  // ============================================================================

  @override
  Future<ApiResult<bool>> storeFCMToken(String token) async {
    try {
      _logRequest('store_fcm_token', 'user_fcm_tokens', {
        'token': '${token.substring(0, 20)}...',
      });

      final user = _client.auth.currentUser;
      if (user == null) {
        return const ApiResult.error('User not authenticated');
      }

      // Upsert the token (insert or update if exists)
      // The unique constraint on (user_id, fcm_token) will handle conflicts
      await _client.from('user_fcm_tokens').upsert({
        'user_id': user.id,
        'fcm_token': token,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,fcm_token');

      if (DEBUG) {
        print('✅ FCM token stored for user ${user.id}');
      }

      return const ApiResult.success(true);
    } catch (e) {
      _logError('storeFCMToken', e);
      return ApiResult.error('Failed to store FCM token: $e');
    }
  }

  @override
  Future<ApiResult<bool>> removeFCMToken(String token) async {
    try {
      _logRequest('remove_fcm_token', 'user_fcm_tokens', {
        'token': '${token.substring(0, 20)}...',
      });

      final user = _client.auth.currentUser;
      if (user == null) {
        return const ApiResult.error('User not authenticated');
      }

      await _client
          .from('user_fcm_tokens')
          .delete()
          .eq('user_id', user.id)
          .eq('fcm_token', token);

      if (DEBUG) {
        print('✅ FCM token removed for user ${user.id}');
      }

      return const ApiResult.success(true);
    } catch (e) {
      _logError('removeFCMToken', e);
      return ApiResult.error('Failed to remove FCM token: $e');
    }
  }

  @override
  Future<ApiResult<List<String>>> getFCMTokensForChannel(
    String channelId,
  ) async {
    try {
      _logRequest('get_fcm_tokens_for_channel', 'user_fcm_tokens', {
        'channelId': channelId,
      });

      // Get all users following this channel/organization and their FCM tokens
      final response = await _client
          .from('user_fcm_tokens')
          .select('fcm_token')
          .inFilter('user_id', [
            // Subquery to get users following this organization/channel
            _client
                .from('user_follows')
                .select('user_id')
                .eq('organization_id', channelId),
          ]);

      final tokens = (response as List<dynamic>)
          .map((item) => item['fcm_token'] as String)
          .toList();

      if (DEBUG) {
        print('✅ Retrieved ${tokens.length} FCM tokens for channel $channelId');
      }

      return ApiResult.success(tokens);
    } catch (e) {
      _logError('getFCMTokensForChannel', e, context: 'channelId: $channelId');
      return ApiResult.error('Failed to get FCM tokens for channel: $e');
    }
  }

  @override
  Future<ApiResult<bool>> updateFCMToken(
    String oldToken,
    String newToken,
  ) async {
    try {
      _logRequest('update_fcm_token', 'user_fcm_tokens', {
        'oldToken': '${oldToken.substring(0, 20)}...',
        'newToken': '${newToken.substring(0, 20)}...',
      });

      final user = _client.auth.currentUser;
      if (user == null) {
        return const ApiResult.error('User not authenticated');
      }

      // First, remove the old token if it exists
      await _client
          .from('user_fcm_tokens')
          .delete()
          .eq('user_id', user.id)
          .eq('fcm_token', oldToken);

      // Then upsert the new token
      await _client.from('user_fcm_tokens').upsert({
        'user_id': user.id,
        'fcm_token': newToken,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,fcm_token');

      if (DEBUG) {
        print('✅ FCM token updated for user ${user.id}');
      }

      return const ApiResult.success(true);
    } catch (e) {
      _logError('updateFCMToken', e);
      return ApiResult.error('Failed to update FCM token: $e');
    }
  }

  @override
  Future<ApiResult<FeatureFlags>> getFeatureFlags() async {
    try {
      _logRequest('get_feature_flags', 'feature_flags', {});

      final response = await _client
          .from('feature_flags')
          .select()
          .limit(1)
          .maybeSingle();

      if (response == null) {
        return const ApiResult.error('Feature flags not found in database');
      }

      final featureFlags = FeatureFlags.fromJson(
        Map<String, dynamic>.from(response),
      );

      if (DEBUG) {
        print('✅ Retrieved feature flags');
      }

      return ApiResult.success(featureFlags);
    } catch (e) {
      _logError('getFeatureFlags', e);
      return ApiResult.error('Failed to get feature flags: $e');
    }
  }

  // ============================================================================
  // POST VIEWS METHODS
  // ============================================================================

  /// Batch insert post views for multiple posts
  /// This is more efficient than inserting views one by one
  /// Only inserts views that don't already exist for the current user
  @override
  Future<ApiResult<bool>> batchInsertPostViews(List<String> postIds) async {
    print("batchInsertPostViews");
    try {
      if (postIds.isEmpty) {
        return const ApiResult.success(true);
      }

      final user = _client.auth.currentUser;
      if (user == null) {
        return const ApiResult.error('User not authenticated');
      }

      _logRequest('batch_insert_post_views', 'post_views', {
        'postIds': postIds,
        'count': postIds.length,
      });

      // First, check which posts the user has already viewed
      final existingViews = await _client
          .from('post_views')
          .select('post_id')
          .eq('user_id', user.id)
          .inFilter('post_id', postIds);

      final existingPostIds = (existingViews as List<dynamic>)
          .map((view) => view['post_id'] as String)
          .toSet();

      // Filter out posts that have already been viewed
      final newPostIds = postIds
          .where((postId) => !existingPostIds.contains(postId))
          .toList();

      if (newPostIds.isEmpty) {
        if (DEBUG) {
          print('✅ All posts already viewed, skipping insert');
        }
        return const ApiResult.success(true);
      }

      // Prepare batch insert data
      final now = DateTime.now().toUtc().toIso8601String();
      final viewsData = newPostIds
          .map(
            (postId) => {
              'user_id': user.id,
              'post_id': postId,
              'viewed_at': now,
            },
          )
          .toList();

      // Batch insert using Supabase's insert with multiple rows
      await _client.from('post_views').insert(viewsData);

      if (DEBUG) {
        print(
          '✅ Successfully inserted ${newPostIds.length} post views (${postIds.length - newPostIds.length} already existed)',
        );
      }

      return const ApiResult.success(true);
    } catch (e) {
      _logError(
        'batchInsertPostViews',
        e,
        context: 'postIds: ${postIds.length}',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  // ============================================================================
  // DIRECT MESSAGES METHODS
  // ============================================================================

  @override
  Future<ApiResult<List<DirectMessageConversation>>>
  getDirectMessageConversations(String userId) async {
    print("getDirectMessageConversations");
    try {
      _logRequest(
        'select',
        'direct_message_conversations_view',
        null,
        additionalInfo: 'userId: $userId',
      );

      // Use the view that includes organization info and unread counts
      final response = await _client
          .from('direct_message_conversations_view')
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false);

      final conversations = (response as List<dynamic>).map((json) {
        // Map the view response to DirectMessageConversation
        final lastMessageId = json['last_message_id'] as String?;
        final lastMessageContent = json['last_message_content'] as String?;
        final lastMessageCreatedAt = json['last_message_created_at'] as String?;

        // Create a simplified last message if available
        final lastMessage = lastMessageId != null && lastMessageContent != null
            ? {
                'id': lastMessageId,
                'organization_id': json['organization_id'],
                'created_by': '', // Will be filled if needed
                'content': lastMessageContent,
                'post_type': 'text',
                'status': 'active',
                'view_count': 0,
                'created_at':
                    lastMessageCreatedAt ?? DateTime.now().toIso8601String(),
                'updated_at':
                    lastMessageCreatedAt ?? DateTime.now().toIso8601String(),
              }
            : null;

        return DirectMessageConversation(
          id: json['id'] as String,
          userId: json['user_id'] as String,
          organizationId: json['organization_id'] as String,
          organizationName: json['organization_name'] as String,
          organizationLogoUrl: json['organization_logo_url'] as String?,
          createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
          updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
          lastMessage: lastMessage != null
              ? ChatMessage.fromJson(lastMessage)
              : null,
          unreadCount: (json['unread_count'] as int?) ?? 0,
          userUsername: json['user_username'] as String?,
          userFullName: json['user_full_name'] as String?,
          userProfilePictureUrl: json['user_profile_picture_url'] as String?,
        );
      }).toList();

      return ApiResult.success(conversations);
    } catch (e) {
      _logError('getDirectMessageConversations', e, context: 'userId: $userId');
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<DirectMessageConversation>>
  createOrGetDirectMessageConversation(
    String userId,
    String organizationId,
  ) async {
    print("createOrGetDirectMessageConversation");
    try {
      _logRequest('upsert', 'direct_message_conversations', {
        'userId': userId,
        'organizationId': organizationId,
      });

      // Try to get existing conversation first
      final existing = await _client
          .from('direct_message_conversations')
          .select()
          .eq('user_id', userId)
          .eq('organization_id', organizationId)
          .maybeSingle();

      String conversationId;
      if (existing != null) {
        conversationId = existing['id'] as String;
      } else {
        // Create new conversation
        final newConversation = await _client
            .from('direct_message_conversations')
            .insert({'user_id': userId, 'organization_id': organizationId})
            .select()
            .single();
        conversationId = newConversation['id'] as String;
      }

      // Get the full conversation with organization details
      final conversation = await _client
          .from('direct_message_conversations_view')
          .select()
          .eq('id', conversationId)
          .single();

      // Map to DirectMessageConversation
      final lastMessageId = conversation['last_message_id'] as String?;
      final lastMessageContent =
          conversation['last_message_content'] as String?;
      final lastMessageCreatedAt =
          conversation['last_message_created_at'] as String?;

      final lastMessage = lastMessageId != null && lastMessageContent != null
          ? ChatMessage.fromJson({
              'id': lastMessageId,
              'organization_id': conversation['organization_id'],
              'created_by': '',
              'content': lastMessageContent,
              'post_type': 'text',
              'status': 'active',
              'view_count': 0,
              'created_at':
                  lastMessageCreatedAt ?? DateTime.now().toIso8601String(),
              'updated_at':
                  lastMessageCreatedAt ?? DateTime.now().toIso8601String(),
            })
          : null;

      return ApiResult.success(
        DirectMessageConversation(
          id: conversation['id'] as String,
          userId: conversation['user_id'] as String,
          organizationId: conversation['organization_id'] as String,
          organizationName: conversation['organization_name'] as String,
          organizationLogoUrl: conversation['organization_logo_url'] as String?,
          createdAt: DateTime.parse(
            conversation['created_at'] as String,
          ).toUtc(),
          updatedAt: DateTime.parse(
            conversation['updated_at'] as String,
          ).toUtc(),
          lastMessage: lastMessage,
          unreadCount: (conversation['unread_count'] as int?) ?? 0,
          userUsername: conversation['user_username'] as String?,
          userFullName: conversation['user_full_name'] as String?,
          userProfilePictureUrl: conversation['user_profile_picture_url'] as String?,
        ),
      );
    } catch (e) {
      _logError(
        'createOrGetDirectMessageConversation',
        e,
        context: 'userId: $userId, organizationId: $organizationId',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<List<DirectMessageItem>>> getDirectMessages(
    String conversationId, {
    int? limit,
    int? offset,
  }) async {
    print("getDirectMessages");
    try {
      _logRequest(
        'select',
        'direct_messages',
        null,
        additionalInfo: 'conversationId: $conversationId',
      );

      var query = _client
          .from('direct_messages')
          .select(
            '*, user_profiles!inner(id, username, full_name, email, profile_picture_url, created_at, updated_at)',
          )
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false);

      if (limit != null) {
        query = query.limit(limit);
      }
      if (offset != null) {
        query = query.range(offset, offset + (limit ?? 50) - 1);
      }

      final response = await query;

      final messages = (response as List<dynamic>)
          .map((json) => DirectMessageItem.fromJson(json))
          .toList();

      return ApiResult.success(messages);
    } catch (e) {
      _logError(
        'getDirectMessages',
        e,
        context: 'conversationId: $conversationId',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<DirectMessageItem>> sendDirectMessage(
    String conversationId,
    String content, {
    String messageType = 'text',
    String? fileUrl,
  }) async {
    print("sendDirectMessage");
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        return const ApiResult.error('User not authenticated');
      }

      _logRequest('insert', 'direct_messages', {
        'conversationId': conversationId,
        'content': content.substring(
          0,
          content.length > 50 ? 50 : content.length,
        ),
        'messageType': messageType,
      });

      final messageData = {
        'conversation_id': conversationId,
        'sender_id': userId,
        'content': content,
        'message_type': messageType,
        if (fileUrl != null) 'file_url': fileUrl,
        'is_read': false,
      };

      final response = await _client
          .from('direct_messages')
          .insert(messageData)
          .select(
            '*, user_profiles!inner(id, username, full_name, email, profile_picture_url, created_at, updated_at)',
          )
          .single();

      AmplitudeService.instance.logEvent('direct_message_sent', eventProperties: {'conversation_id': conversationId, 'message_type': messageType});
      // Push notification is triggered server-side via the notify_direct_message_created
      // DB trigger (see migration 064), which calls the send-dm-notification edge function.
      return ApiResult.success(DirectMessageItem.fromJson(response));
    } catch (e) {
      _logError(
        'sendDirectMessage',
        e,
        context: 'conversationId: $conversationId',
      );
      final apiError = _handleError(e);
      AmplitudeService.instance.logEvent('direct_message_error', eventProperties: {'conversation_id': conversationId, 'error': apiError.code});
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<bool>> markDirectMessagesAsRead(
    String conversationId,
    String userId,
  ) async {
    print("markDirectMessagesAsRead");
    try {
      _logRequest(
        'update',
        'direct_messages',
        null,
        additionalInfo: 'conversationId: $conversationId, userId: $userId',
      );

      // Mark all unread messages in this conversation as read
      // Only mark messages that were sent by someone else (not the current user)
      await _client
          .from('direct_messages')
          .update({'is_read': true})
          .eq('conversation_id', conversationId)
          .neq('sender_id', userId)
          .eq('is_read', false);

      return const ApiResult.success(true);
    } catch (e) {
      _logError(
        'markDirectMessagesAsRead',
        e,
        context: 'conversationId: $conversationId, userId: $userId',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Stream<List<DirectMessageItem>> streamDirectMessages(String conversationId) {
    print("streamDirectMessages");
    return _client
        .from('direct_messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .map(
          (data) =>
              data.map((json) => DirectMessageItem.fromJson(json)).toList(),
        )
        .handleError((error) {
          _logError(
            'streamDirectMessages',
            error,
            context: 'conversationId: $conversationId',
          );
        });
  }

  @override
  Stream<List<DirectMessageConversation>> streamDirectMessageConversations(
    String userId,
  ) {
    print("streamDirectMessageConversations");
    // Stream from base table, then fetch full details from view
    return _client
        .from('direct_message_conversations')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .asyncMap((data) async {
          // Fetch full details from view for all conversations
          if (data.isEmpty) return <DirectMessageConversation>[];

          final conversationIds = data
              .map((conv) => conv['id'] as String)
              .toList();

          try {
            final viewData = await _client
                .from('direct_message_conversations_view')
                .select()
                .inFilter('id', conversationIds)
                .order('updated_at', ascending: false);

            return (viewData as List<dynamic>).map((viewData) {
              final lastMessageId = viewData['last_message_id'] as String?;
              final lastMessageContent =
                  viewData['last_message_content'] as String?;
              final lastMessageCreatedAt =
                  viewData['last_message_created_at'] as String?;

              final lastMessage =
                  lastMessageId != null && lastMessageContent != null
                  ? ChatMessage.fromJson({
                      'id': lastMessageId,
                      'organization_id': viewData['organization_id'],
                      'created_by': '',
                      'content': lastMessageContent,
                      'post_type': 'text',
                      'status': 'active',
                      'view_count': 0,
                      'created_at':
                          lastMessageCreatedAt ??
                          DateTime.now().toIso8601String(),
                      'updated_at':
                          lastMessageCreatedAt ??
                          DateTime.now().toIso8601String(),
                    })
                  : null;

              return DirectMessageConversation(
                id: viewData['id'] as String,
                userId: viewData['user_id'] as String,
                organizationId: viewData['organization_id'] as String,
                organizationName: viewData['organization_name'] as String,
                organizationLogoUrl:
                    viewData['organization_logo_url'] as String?,
                createdAt: DateTime.parse(
                  viewData['created_at'] as String,
                ).toUtc(),
                updatedAt: DateTime.parse(
                  viewData['updated_at'] as String,
                ).toUtc(),
                lastMessage: lastMessage,
                unreadCount: (viewData['unread_count'] as int?) ?? 0,
                userUsername: viewData['user_username'] as String?,
                userFullName: viewData['user_full_name'] as String?,
                userProfilePictureUrl: viewData['user_profile_picture_url'] as String?,
              );
            }).toList();
          } catch (e) {
            print('Error fetching conversation details in stream: $e');
            return <DirectMessageConversation>[];
          }
        })
        .handleError((error) {
          _logError(
            'streamDirectMessageConversations',
            error,
            context: 'userId: $userId',
          );
        });
  }

  @override
  Future<ApiResult<List<DirectMessageConversation>>>
  getDirectMessageConversationsByOrganizations(
    List<String> organizationIds,
  ) async {
    print("getDirectMessageConversationsByOrganizations");
    try {
      if (organizationIds.isEmpty) {
        return ApiResult.success([]);
      }

      _logRequest(
        'select',
        'direct_message_conversations_view',
        null,
        additionalInfo: 'organizationIds: ${organizationIds.length}',
      );

      // Use the view that includes organization info and unread counts
      // Filter by organization_id instead of user_id for admins
      final response = await _client
          .from('direct_message_conversations_view')
          .select()
          .inFilter('organization_id', organizationIds)
          .order('updated_at', ascending: false);

      final conversations = (response as List<dynamic>).map((json) {
        // Map the view response to DirectMessageConversation
        final lastMessageId = json['last_message_id'] as String?;
        final lastMessageContent = json['last_message_content'] as String?;
        final lastMessageCreatedAt = json['last_message_created_at'] as String?;

        // Create a simplified last message if available
        final lastMessage = lastMessageId != null && lastMessageContent != null
            ? {
                'id': lastMessageId,
                'organization_id': json['organization_id'],
                'created_by': '', // Will be filled if needed
                'content': lastMessageContent,
                'post_type': 'text',
                'status': 'active',
                'view_count': 0,
                'created_at':
                    lastMessageCreatedAt ?? DateTime.now().toIso8601String(),
                'updated_at':
                    lastMessageCreatedAt ?? DateTime.now().toIso8601String(),
              }
            : null;

        return DirectMessageConversation(
          id: json['id'] as String,
          userId: json['user_id'] as String,
          organizationId: json['organization_id'] as String,
          organizationName: json['organization_name'] as String,
          organizationLogoUrl: json['organization_logo_url'] as String?,
          createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
          updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
          lastMessage: lastMessage != null
              ? ChatMessage.fromJson(lastMessage)
              : null,
          unreadCount: (json['unread_count'] as int?) ?? 0,
          userUsername: json['user_username'] as String?,
          userFullName: json['user_full_name'] as String?,
          userProfilePictureUrl: json['user_profile_picture_url'] as String?,
        );
      }).toList();

      return ApiResult.success(conversations);
    } catch (e) {
      _logError(
        'getDirectMessageConversationsByOrganizations',
        e,
        context: 'organizationIds: ${organizationIds.length}',
      );
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Stream<List<DirectMessageConversation>>
  streamDirectMessageConversationsByOrganizations(
    List<String> organizationIds,
  ) {
    print("streamDirectMessageConversationsByOrganizations");
    if (organizationIds.isEmpty) {
      return Stream.value(<DirectMessageConversation>[]);
    }

    // Stream from base table filtered by organization_id, then fetch full details from view
    return _client
        .from('direct_message_conversations')
        .stream(primaryKey: ['id'])
        .inFilter('organization_id', organizationIds)
        .order('updated_at', ascending: false)
        .asyncMap((data) async {
          // Fetch full details from view for all conversations
          if (data.isEmpty) return <DirectMessageConversation>[];

          final conversationIds = data
              .map((conv) => conv['id'] as String)
              .toList();

          try {
            final viewData = await _client
                .from('direct_message_conversations_view')
                .select()
                .inFilter('id', conversationIds)
                .order('updated_at', ascending: false);

            return (viewData as List<dynamic>).map((viewData) {
              final lastMessageId = viewData['last_message_id'] as String?;
              final lastMessageContent =
                  viewData['last_message_content'] as String?;
              final lastMessageCreatedAt =
                  viewData['last_message_created_at'] as String?;

              final lastMessage =
                  lastMessageId != null && lastMessageContent != null
                  ? ChatMessage.fromJson({
                      'id': lastMessageId,
                      'organization_id': viewData['organization_id'],
                      'created_by': '',
                      'content': lastMessageContent,
                      'post_type': 'text',
                      'status': 'active',
                      'view_count': 0,
                      'created_at':
                          lastMessageCreatedAt ??
                          DateTime.now().toIso8601String(),
                      'updated_at':
                          lastMessageCreatedAt ??
                          DateTime.now().toIso8601String(),
                    })
                  : null;

              return DirectMessageConversation(
                id: viewData['id'] as String,
                userId: viewData['user_id'] as String,
                organizationId: viewData['organization_id'] as String,
                organizationName: viewData['organization_name'] as String,
                organizationLogoUrl:
                    viewData['organization_logo_url'] as String?,
                createdAt: DateTime.parse(
                  viewData['created_at'] as String,
                ).toUtc(),
                updatedAt: DateTime.parse(
                  viewData['updated_at'] as String,
                ).toUtc(),
                lastMessage: lastMessage,
                unreadCount: (viewData['unread_count'] as int?) ?? 0,
                userUsername: viewData['user_username'] as String?,
                userFullName: viewData['user_full_name'] as String?,
                userProfilePictureUrl: viewData['user_profile_picture_url'] as String?,
              );
            }).toList();
          } catch (e) {
            print('Error fetching conversation details in stream: $e');
            return <DirectMessageConversation>[];
          }
        })
        .handleError((error) {
          _logError(
            'streamDirectMessageConversationsByOrganizations',
            error,
            context: 'organizationIds: ${organizationIds.length}',
          );
        });
  }

  // ============================================================================
  // FEEDBACK METHODS
  // ============================================================================

  @override
  Future<ApiResult<Map<String, dynamic>>> submitFeedback({
    required String userId,
    required String feedbackType,
    required String description,
    String? screenshotUrl,
  }) async {
    debugLogGreen("submitFeedback", tag: "API");
    try {
      _logRequest('submit_feedback', 'feedback', {
        'user_id': userId,
        'feedback_type': feedbackType,
        'description_length': description.length,
        'has_screenshot': screenshotUrl != null,
      });

      final feedbackData = {
        'user_id': userId,
        'feedback_type': feedbackType,
        'description': description,
        'screenshot_url': screenshotUrl,
        'status': 'pending',
      };

      final response = await _client
          .from('feedback')
          .insert(feedbackData)
          .select()
          .single();

      if (DEBUG) {
        print('✅ Feedback submitted successfully: ${response['id']}');
      }

      AmplitudeService.instance.logEvent('feedback_submitted', eventProperties: {'feedback_type': feedbackType, 'has_screenshot': screenshotUrl != null});
      return ApiResult.success(response as Map<String, dynamic>);
    } catch (e) {
      _logError('submitFeedback', e, context: 'userId: $userId');
      final apiError = _handleError(e);
      AmplitudeService.instance.logEvent('feedback_error', eventProperties: {'feedback_type': feedbackType, 'error': apiError.code});
      return ApiResult.error(apiError.message);
    }
  }

  // ============================================================================
  // VEHICLE INQUIRY METHODS
  // ============================================================================

  @override
  Future<ApiResult<VehicleInquiryConversation>> createOrGetVehicleInquiry(
    String vehicleId,
  ) async {
    try {
      if (_client.auth.currentUser == null) {
        return const ApiResult.error('User not authenticated');
      }

      // The RPC reads the seller side off the listing: its author for a
      // personal listing, the organization behind the feed for a dealer one.
      // The client cannot insert the row itself, so it cannot name a seller.
      final conversationId = await _client.rpc(
        'create_or_get_vehicle_inquiry',
        params: {'p_vehicle_id': vehicleId},
      ) as String;

      final view = await _client
          .from('vehicle_inquiry_conversations_view')
          .select()
          .eq('id', conversationId)
          .single();

      return ApiResult.success(VehicleInquiryConversation.fromJson(view));
    } catch (e) {
      _logError('createOrGetVehicleInquiry', e);
      // "Seller no longer has an account" and "no dealership configured" are
      // both states the buyer should see verbatim, not as a generic failure.
      if (e is PostgrestException && e.message.isNotEmpty) {
        return ApiResult.error(e.message);
      }
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<VehicleInquiryConversation>> createOrGetDealerInquiry(
    VehicleListing listing,
  ) async {
    try {
      if (_client.auth.currentUser == null) {
        return const ApiResult.error('User not authenticated');
      }
      if (!listing.isFromDealerFeed) {
        return const ApiResult.error('Not a dealer listing');
      }

      // The RPC resolves the receiving dealer account from the feed, mirrors
      // the vehicle into vehicle_listings and returns the conversation — a
      // buyer has no rights to do any of that directly.
      final conversationId = await _client.rpc(
        'create_or_get_dealer_vehicle_inquiry',
        params: {
          'p_source': listing.dealerSourceKey,
          // An ingested vehicle already exists as a row, so its uuid and its
          // provider-side id are different strings. Keying on the uuid would
          // miss the existing row and mirror a duplicate alongside it.
          'p_external_id': listing.externalId ?? listing.id,
          'p_vehicle': listing.toJson(),
        },
      ) as String;

      final view = await _client
          .from('vehicle_inquiry_conversations_view')
          .select()
          .eq('id', conversationId)
          .single();

      return ApiResult.success(VehicleInquiryConversation.fromJson(view));
    } catch (e) {
      _logError('createOrGetDealerInquiry', e);
      // The "no dealer configured yet" case is an operator task, not a bug —
      // surface it as-is instead of a generic failure.
      if (e is PostgrestException && e.message.isNotEmpty) {
        return ApiResult.error(e.message);
      }
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<VehicleInquiryConversation>> createOrGetMarketItemInquiry(
    String itemId,
  ) async {
    try {
      if (_client.auth.currentUser == null) {
        return const ApiResult.error('User not authenticated');
      }

      // Same contract as createOrGetVehicleInquiry: the RPC reads the seller
      // off the item, so the client never names one.
      final conversationId = await _client.rpc(
        'create_or_get_market_item_inquiry',
        params: {'p_item_id': itemId},
      ) as String;

      final view = await _client
          .from('vehicle_inquiry_conversations_view')
          .select()
          .eq('id', conversationId)
          .single();

      return ApiResult.success(VehicleInquiryConversation.fromJson(view));
    } catch (e) {
      _logError('createOrGetMarketItemInquiry', e);
      // "This item has already been sold" is for the buyer to read as-is.
      if (e is PostgrestException && e.message.isNotEmpty) {
        return ApiResult.error(e.message);
      }
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<List<VehicleInquiryConversation>>> getListingInquiries() async {
    try {
      // A dealer conversation has no seller_id — it belongs to an
      // organization — so filtering on buyer_id/seller_id would leave every
      // dealership admin with an empty inbox. The RPC adds the conversations
      // of the orgs this user administers, which the client cannot enumerate.
      //
      // get_vehicle_inquiries_for_user is the vehicle-only variant, kept for
      // builds that cannot parse an item conversation (migration 081).
      final data = await _client.rpc('get_listing_inquiries_for_user');

      final list = (data as List)
          .map((e) =>
              VehicleInquiryConversation.fromJson(e as Map<String, dynamic>))
          .toList();
      return ApiResult.success(list);
    } catch (e) {
      _logError('getListingInquiries', e);
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<List<VehicleInquiryConversation>>> getMarketItemInquiries(
    String itemId,
  ) async {
    try {
      final data = await _client
          .from('vehicle_inquiry_conversations_view')
          .select()
          .eq('market_item_id', itemId)
          .order('updated_at', ascending: false);

      final list = (data as List)
          .map((e) =>
              VehicleInquiryConversation.fromJson(e as Map<String, dynamic>))
          .toList();
      return ApiResult.success(list);
    } catch (e) {
      _logError('getMarketItemInquiries', e);
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<List<VehicleInquiryConversation>>>
      getVehicleInquiriesForListing(String vehicleId) async {
    try {
      final data = await _client
          .from('vehicle_inquiry_conversations_view')
          .select()
          .eq('vehicle_id', vehicleId)
          .order('updated_at', ascending: false);

      final list = (data as List)
          .map((e) =>
              VehicleInquiryConversation.fromJson(e as Map<String, dynamic>))
          .toList();
      return ApiResult.success(list);
    } catch (e) {
      _logError('getVehicleInquiriesForListing', e);
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<VehicleInquiryConversation>> getVehicleInquiryById(
    String conversationId,
  ) async {
    try {
      final view = await _client
          .from('vehicle_inquiry_conversations_view')
          .select()
          .eq('id', conversationId)
          .single();

      return ApiResult.success(VehicleInquiryConversation.fromJson(view));
    } catch (e) {
      _logError('getVehicleInquiryById', e);
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<List<DirectMessageItem>>> getVehicleInquiryMessages(
    String conversationId, {
    int? limit,
    int? offset,
  }) async {
    try {
      var query = _client
          .from('vehicle_inquiry_messages')
          .select(
            '*, user_profiles!inner(id, username, full_name, email, profile_picture_url, created_at, updated_at)',
          )
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false);

      if (limit != null) query = query.limit(limit);
      if (offset != null) query = query.range(offset, offset + (limit ?? 50) - 1);

      final response = await query;
      final messages = (response as List)
          .map((json) => DirectMessageItem.fromJson(json))
          .toList();
      return ApiResult.success(messages);
    } catch (e) {
      _logError('getVehicleInquiryMessages', e);
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<DirectMessageItem>> sendVehicleInquiryMessage(
    String conversationId,
    String content, {
    String messageType = 'text',
    String? fileUrl,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        return const ApiResult.error('User not authenticated');
      }

      final response = await _client
          .from('vehicle_inquiry_messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': userId,
            'content': content,
            'message_type': messageType,
            if (fileUrl != null) 'file_url': fileUrl,
            'is_read': false,
          })
          .select(
            '*, user_profiles!inner(id, username, full_name, email, profile_picture_url, created_at, updated_at)',
          )
          .single();

      return ApiResult.success(DirectMessageItem.fromJson(response));
    } catch (e) {
      _logError('sendVehicleInquiryMessage', e);
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Future<ApiResult<bool>> markVehicleInquiryMessagesAsRead(
    String conversationId,
    String userId,
  ) async {
    try {
      await _client
          .from('vehicle_inquiry_messages')
          .update({'is_read': true})
          .eq('conversation_id', conversationId)
          .neq('sender_id', userId)
          .eq('is_read', false);

      return const ApiResult.success(true);
    } catch (e) {
      _logError('markVehicleInquiryMessagesAsRead', e);
      final apiError = _handleError(e);
      return ApiResult.error(apiError.message);
    }
  }

  @override
  Stream<List<DirectMessageItem>> streamVehicleInquiryMessages(
    String conversationId,
  ) {
    return _client
        .from('vehicle_inquiry_messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .map((data) =>
            data.map((json) => DirectMessageItem.fromJson(json)).toList())
        .handleError((error) {
          _logError('streamVehicleInquiryMessages', error);
        });
  }
}

// Future<void> _updateOrganizationCategories(
//   String organizationId,
//   List<String> categoryIds,
// ) async {
//   // 1. Delete existing categories for the organization
//   await _deleteOrganizationCategories(organizationId);

//   // 2. Insert new categories
//   final categoryData = categoryIds
//       .map(
//         (categoryId) => {
//           'organization_id': organizationId,
//           'category_id': categoryId,
//         },
//       )
//       .toList();

//   await _client.from('organization_categories').insert(categoryData);
// }

// Future<void> _deleteOrganizationCategories(String organizationId) async {
//   await _client
//       .from('organization_categories')
//       .delete()
//       .eq('organization_id', organizationId);
// }

// Helper class for multiple admin assignment results
class AdminAssignmentResult {
  final String email;
  final bool success;
  final String message;

  const AdminAssignmentResult({
    required this.email,
    required this.success,
    required this.message,
  });

  factory AdminAssignmentResult.fromJson(Map<String, dynamic> json) {
    return AdminAssignmentResult(
      email: json['email'] as String,
      success: json['success'] as bool,
      message: json['message'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'email': email, 'success': success, 'message': message};
  }
}
