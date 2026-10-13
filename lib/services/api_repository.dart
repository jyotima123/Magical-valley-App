// lib/services/api_repository.dart
// Repository pattern for API service

import 'dart:typed_data';

import 'package:mvc_app/modules/cars/vehicle_inquiry_conversation.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:mvc_app/modules/chat/models/direct_message_conversation.dart';
import 'package:mvc_app/modules/chat/models/direct_message_item.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';
import 'package:mvc_app/modules/chat/models/post_reactions_model.dart';
import 'package:mvc_app/services/api_service.dart';
import 'package:mvc_app/services/models/feature_flags.dart';

class ApiRepository {
  final ApiService _apiService;

  ApiRepository(this._apiService);

  // Authentication methods
  Future<AuthResult> login(String email, String password) async {
    return await _apiService.signIn(email, password);
  }

  Future<AuthResult> register(
    String email,
    String password,
    String fullName,
  ) async {
    return await _apiService.signUp(email, password, fullName);
  }

  Future<AuthResult> socialLogin(String provider) async {
    return await _apiService.signInWithProvider(provider);
  }

  Future<void> logout() async {
    await _apiService.signOut();
  }

  Future<AuthResult?> getCurrentUser() async {
    return await _apiService.getCurrentUser();
  }

  // User profile methods
  Future<ApiResult<UserProfile>> getUserProfile(String userId) async {
    return await _apiService.getUserProfile(userId);
  }

  Future<ApiResult<UserProfile>> updateUserProfile(
    String userId,
    Map<String, dynamic> data,
  ) async {
    return await _apiService.updateUserProfile(userId, data);
  }

  // New user role and organization management methods
  Future<ApiResult<UserRole>> getUserRole(String userId) async {
    return await _apiService.getUserRole(userId);
  }

  Future<ApiResult<List<Organization>>> getUserManagedOrganizations(
    String userId,
  ) async {
    return await _apiService.getUserManagedOrganizations(userId);
  }

  // Generic CRUD methods
  Future<ApiResult<List<T>>> fetchAll<T>(
    String table, {
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
    int? limit,
    int? offset,
  }) async {
    return await _apiService.getAll<T>(
      table,
      filters: filters,
      orderBy: orderBy,
      ascending: ascending,
      limit: limit,
      offset: offset,
    );
  }

  Future<ApiResult<T>> fetchById<T>(String table, String id) async {
    return await _apiService.getById<T>(table, id);
  }

  Future<ApiResult<T>> create<T>(
    String table,
    Map<String, dynamic> data,
  ) async {
    return await _apiService.create<T>(table, data);
  }

  Future<ApiResult<T>> update<T>(
    String table,
    String id,
    Map<String, dynamic> data,
  ) async {
    return await _apiService.update<T>(table, id, data);
  }

  Future<ApiResult<bool>> delete(String table, String id) async {
    return await _apiService.delete(table, id);
  }

  /// Email OTP methods
  Future<AuthResult> sendEmailOtp(String email) async {
    return await _apiService.sendEmailOtp(email);
  }

  Future<AuthResult> resendOtp(String email, String otpType) async {
    return await _apiService.resendOtp(email, otpType);
  }

  Future<AuthResult> verifyOtp(
    String email,
    String otpCode,
    String otpType,
  ) async {
    return await _apiService.verifyOtp(email, otpCode, otpType);
  }

  /// Phone/SMS OTP methods
  Future<AuthResult> sendPhoneOtp(String phoneNumber) async {
    return await _apiService.sendPhoneOtp(phoneNumber);
  }

  Future<AuthResult> verifyPhoneOtp(String phoneNumber, String otpCode) async {
    return await _apiService.verifyPhoneOtp(phoneNumber, otpCode);
  }

  Future<AuthResult> resendPhoneOtp(String phoneNumber) async {
    return await _apiService.resendPhoneOtp(phoneNumber);
  }

  Future removeProfilePicture() async {}

  Future uploadProfilePicture(Uint8List imageBytes) async {}

  Future createUserProfile({
    required String userId,
    required String username,
    required String fullName,
    required String email,
    required String role,
  }) async {
    return await _apiService.createUserProfile(
      userId: userId,
      username: username,
      fullName: fullName,
      email: email,
      role: role,
    );
  }

  Future getUserFollowedOrganizationIds(String userId) async {
    return await _apiService.getUserFollowedOrganizationIds(userId: userId);
  }

  Future<ApiResult<bool>> unfollowOrganization(
    String id,
    String organizationId,
  ) async {
    return await _apiService.unfollowOrganization(id, organizationId);
  }

  Future<ApiResult<List<Organization>>> getUserFollowedOrganizations(
    String userId,
  ) async {
    return await _apiService.getUserFollowedOrganizations(userId: userId);
  }

  Future<ApiResult<List<UserProfile>>> getOrganizationFollowers(
    String organizationId,
  ) async {
    return await _apiService.getOrganizationFollowers(organizationId);
  }
  // Future<AuthResult> exchangeCodeForSession(
  //   String passwordResetLinkUriAsString,

  // ) async {
  //   return await _apiService.exchangeCodeForSession
  // }

  // ============================================================================
  // POST REACTION METHODS
  // ============================================================================

  /// Get all reactions for a specific post
  Future<ApiResult<List<PostReaction>>> getPostReactions(String postId) async {
    return await _apiService.getPostReactions(postId);
  }

  /// Add or update a user's reaction to a post
  Future<ApiResult<PostReaction>> upsertPostReaction(
    String postId,
    List<String> emojiReactions,
  ) async {
    return await _apiService.upsertPostReaction(postId, emojiReactions);
  }

  /// Remove a user's reaction from a post
  Future<ApiResult<bool>> removePostReaction(String postId) async {
    return await _apiService.removePostReaction(postId);
  }

  /// Get the current user's reaction for a specific post
  Future<ApiResult<PostReaction?>> getUserReactionForPost(String postId) async {
    return await _apiService.getUserReactionForPost(postId);
  }

  /// Check if current user has reacted to a specific post
  Future<ApiResult<bool>> hasUserReactedToPost(String postId) async {
    return await _apiService.hasUserReactedToPost(postId);
  }

  // ============================================================================
  // FCM TOKEN METHODS
  // ============================================================================

  /// Store FCM token for the current user
  Future<ApiResult<bool>> storeFCMToken(String token) async {
    return await _apiService.storeFCMToken(token);
  }

  /// Remove FCM token for the current user
  Future<ApiResult<bool>> removeFCMToken(String token) async {
    return await _apiService.removeFCMToken(token);
  }

  /// Get all FCM tokens for users following a specific channel
  Future<ApiResult<List<String>>> getFCMTokensForChannel(
    String channelId,
  ) async {
    return await _apiService.getFCMTokensForChannel(channelId);
  }

  /// Update FCM token for the current user
  Future<ApiResult<bool>> updateFCMToken(
    String oldToken,
    String newToken,
  ) async {
    return await _apiService.updateFCMToken(oldToken, newToken);
  }

  // ============================================================================
  // FEATURE FLAGS METHODS
  // ============================================================================

  /// Get feature flags from the database
  Future<ApiResult<FeatureFlags>> getFeatureFlags() async {
    return await _apiService.getFeatureFlags();
  }

  // ============================================================================
  // POST VIEWS METHODS
  // ============================================================================

  /// Batch insert post views for multiple posts
  /// This is more efficient than inserting views one by one
  Future<ApiResult<bool>> batchInsertPostViews(List<String> postIds) async {
    return await _apiService.batchInsertPostViews(postIds);
  }

  // ============================================================================
  // DIRECT MESSAGES METHODS
  // ============================================================================

  /// Get all direct message conversations for a user
  Future<ApiResult<List<DirectMessageConversation>>> getDirectMessageConversations(
    String userId,
  ) async {
    return await _apiService.getDirectMessageConversations(userId);
  }

  /// Create or get an existing direct message conversation with an organization
  Future<ApiResult<DirectMessageConversation>> createOrGetDirectMessageConversation(
    String userId,
    String organizationId,
  ) async {
    return await _apiService.createOrGetDirectMessageConversation(
      userId,
      organizationId,
    );
  }

  /// Get all messages for a specific conversation
  Future<ApiResult<List<DirectMessageItem>>> getDirectMessages(
    String conversationId, {
    int? limit,
    int? offset,
  }) async {
    return await _apiService.getDirectMessages(
      conversationId,
      limit: limit,
      offset: offset,
    );
  }

  /// Send a direct message in a conversation
  Future<ApiResult<DirectMessageItem>> sendDirectMessage(
    String conversationId,
    String content, {
    String messageType = 'text',
    String? fileUrl,
  }) async {
    return await _apiService.sendDirectMessage(
      conversationId,
      content,
      messageType: messageType,
      fileUrl: fileUrl,
    );
  }

  /// Mark messages as read in a conversation
  Future<ApiResult<bool>> markDirectMessagesAsRead(
    String conversationId,
    String userId,
  ) async {
    return await _apiService.markDirectMessagesAsRead(conversationId, userId);
  }

  /// Stream messages for a specific conversation (real-time updates)
  Stream<List<DirectMessageItem>> streamDirectMessages(String conversationId) {
    return _apiService.streamDirectMessages(conversationId);
  }

  /// Stream conversations for a user (real-time updates)
  Stream<List<DirectMessageConversation>> streamDirectMessageConversations(
    String userId,
  ) {
    return _apiService.streamDirectMessageConversations(userId);
  }

  /// Get all direct message conversations for organizations managed by an admin
  Future<ApiResult<List<DirectMessageConversation>>> getDirectMessageConversationsByOrganizations(
    List<String> organizationIds,
  ) async {
    return await _apiService.getDirectMessageConversationsByOrganizations(organizationIds);
  }

  /// Stream conversations for organizations managed by an admin (real-time updates)
  Stream<List<DirectMessageConversation>> streamDirectMessageConversationsByOrganizations(
    List<String> organizationIds,
  ) {
    return _apiService.streamDirectMessageConversationsByOrganizations(organizationIds);
  }

  Future<dynamic> getAllOrganizations({required String orderBy, required bool ascending}) async {
    return _apiService.getAllOrganizations(orderBy: orderBy, ascending: ascending);
  }

  // ============================================================================
  // VEHICLE INQUIRY METHODS
  // ============================================================================

  Future<ApiResult<VehicleInquiryConversation>> createOrGetVehicleInquiry(
    String vehicleId,
  ) async {
    return await _apiService.createOrGetVehicleInquiry(vehicleId);
  }

  Future<ApiResult<VehicleInquiryConversation>> createOrGetDealerInquiry(
    VehicleListing listing,
  ) async {
    return await _apiService.createOrGetDealerInquiry(listing);
  }

  Future<ApiResult<VehicleInquiryConversation>> createOrGetMarketItemInquiry(
    String itemId,
  ) async {
    return await _apiService.createOrGetMarketItemInquiry(itemId);
  }

  Future<ApiResult<List<VehicleInquiryConversation>>> getListingInquiries() async {
    return await _apiService.getListingInquiries();
  }

  Future<ApiResult<List<VehicleInquiryConversation>>>
      getVehicleInquiriesForListing(String vehicleId) async {
    return await _apiService.getVehicleInquiriesForListing(vehicleId);
  }

  Future<ApiResult<List<VehicleInquiryConversation>>> getMarketItemInquiries(
    String itemId,
  ) async {
    return await _apiService.getMarketItemInquiries(itemId);
  }

  Future<ApiResult<VehicleInquiryConversation>> getVehicleInquiryById(
    String conversationId,
  ) async {
    return await _apiService.getVehicleInquiryById(conversationId);
  }

  Future<ApiResult<List<DirectMessageItem>>> getVehicleInquiryMessages(
    String conversationId, {
    int? limit,
    int? offset,
  }) async {
    return await _apiService.getVehicleInquiryMessages(
      conversationId,
      limit: limit,
      offset: offset,
    );
  }

  Future<ApiResult<DirectMessageItem>> sendVehicleInquiryMessage(
    String conversationId,
    String content, {
    String messageType = 'text',
    String? fileUrl,
  }) async {
    return await _apiService.sendVehicleInquiryMessage(
      conversationId,
      content,
      messageType: messageType,
      fileUrl: fileUrl,
    );
  }

  Future<ApiResult<bool>> markVehicleInquiryMessagesAsRead(
    String conversationId,
    String userId,
  ) async {
    return await _apiService.markVehicleInquiryMessagesAsRead(
        conversationId, userId);
  }

  Stream<List<DirectMessageItem>> streamVehicleInquiryMessages(
    String conversationId,
  ) {
    return _apiService.streamVehicleInquiryMessages(conversationId);
  }

  // ============================================================================
  // FEEDBACK METHODS
  // ============================================================================

  /// Submit feedback (issue or suggestion) with optional screenshot
  Future<ApiResult<Map<String, dynamic>>> submitFeedback({
    required String userId,
    required String feedbackType,
    required String description,
    String? screenshotUrl,
  }) async {
    return await _apiService.submitFeedback(
      userId: userId,
      feedbackType: feedbackType,
      description: description,
      screenshotUrl: screenshotUrl,
    );
  }
}

// Result classes for API responses
class ApiResult<T> {
  final T? data;
  final String? error;
  final bool isSuccess;

  const ApiResult.success(this.data) : error = null, isSuccess = true;
  const ApiResult.error(this.error) : data = null, isSuccess = false;
}

class AuthResult {
  final String? userId;
  final String? email;
  final String? error;
  final bool isSuccess;
  final String? message;
  final Map<String, dynamic>? userData;
  final bool isPendingEmailConfirmation;

  const AuthResult._({
    required this.isSuccess,
    this.userId,
    this.email,
    this.error,
    this.message,
    this.userData,
    this.isPendingEmailConfirmation = false,
  });

  const AuthResult.success({
    required String userId,
    String? email,
    String? message,
    Map<String, dynamic>? userData,
  }) : this._(
         isSuccess: true,
         error: null,
         userId: userId,
         email: email,
         message: message,
         userData: userData,
       );

  const AuthResult.error(String message)
    : this._(isSuccess: false, message: message);

  const AuthResult.pendingEmailConfirmation({
    required String email,
    String? message,
  }) : this._(
         isSuccess: false,
         email: email,
         message: message,
         isPendingEmailConfirmation: true,
       );
}

// Enum for user roles
enum UserRole {
  regular('regular'),
  admin('admin'),
  superadmin('superadmin');

  const UserRole(this.value);
  final String value;

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (role) => role.value == value,
      orElse: () => UserRole.regular,
    );
  }

  // Helper methods for role checking
  bool get isRegular => this == UserRole.regular;
  bool get isAdmin => this == UserRole.admin;
  bool get isSuperAdmin => this == UserRole.superadmin;
  bool get isAdminOrSuperAdmin =>
      this == UserRole.admin || this == UserRole.superadmin;
}

// Updated UserProfile class with role
class UserProfile {
  final String id;
  final String email;
  final String? username;
  final String? fullName;
  final String? profilePictureUrl;
  final String? phoneNumber;
  final String? bio;
  final UserRole role;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? verifiedAt;

  UserProfile({
    required this.id,
    required this.email,
    this.username,
    this.fullName,
    this.profilePictureUrl,
    this.phoneNumber,
    this.bio,
    required this.role,
    required this.createdAt,
    required this.updatedAt,
    this.verifiedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    print("USER PROFILE : ${json.toString()}");
    return UserProfile(
      id: json['id'],
      email: json['email'],
      username: json['username'],
      fullName: json['full_name'],
      profilePictureUrl: json['profile_picture_url'],
      phoneNumber: json['phone_number'],
      bio: json['bio'],
      role: UserRole.fromString(json['role'] ?? 'regular'),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      // If the key is absent the column doesn't exist yet (migration 057 not
      // run). Treat those rows as already verified so existing users are never
      // incorrectly sent to the verification screen.
      verifiedAt: !json.containsKey('verified_at')
          ? DateTime(2000)
          : (json['verified_at'] != null
              ? DateTime.parse(json['verified_at'])
              : null),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'full_name': fullName,
      'profile_picture_url': profilePictureUrl,
      'phone_number': phoneNumber,
      'bio': bio,
      'role': role.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Helper methods for role checking
  bool get isRegular => role.isRegular;
  bool get isAdmin => role.isAdmin;
  bool get isSuperAdmin => role.isSuperAdmin;
  bool get isAdminOrSuperAdmin => role.isAdminOrSuperAdmin;

  // Create a copy with updated fields
  UserProfile copyWith({
    String? email,
    String? username,
    String? fullName,
    String? profilePictureUrl,
    String? phoneNumber,
    String? bio,
    UserRole? role,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id,
      email: email ?? this.email,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      bio: bio ?? this.bio,
      role: role ?? this.role,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
