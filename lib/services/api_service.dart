// lib/services/api/api_service.dart
// Abstract API service interface for backend-agnostic operations

import 'dart:typed_data' show Uint8List;

import 'package:mvc_app/modules/cars/vehicle_inquiry_conversation.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:mvc_app/modules/chat/models/direct_message_conversation.dart';
import 'package:mvc_app/modules/chat/models/direct_message_item.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';
import 'package:mvc_app/modules/chat/models/post_reactions_model.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart'
    show AdminAssignmentResult;
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/models/feature_flags.dart';

abstract class ApiService {
  // Authentication methods
  Future<AuthResult> signIn(String email, String password);
  Future<AuthResult> signUp(String email, String password, String fullName);
  Future<AuthResult> signInWithProvider(String provider);
  Future<void> signOut();
  Future<AuthResult?> getCurrentUser();

  // User management
  Future<ApiResult<UserProfile>> getUserProfile(String userId);
  Future<ApiResult<UserProfile>> updateUserProfile(
    String userId,
    Map<String, dynamic> data,
  );

  // New user role and organization management methods
  Future<ApiResult<UserRole>> getUserRole(String userId);
  Future<ApiResult<List<Organization>>> getUserManagedOrganizations(
    String userId,
  );

  // Generic CRUD operations
  Future<ApiResult<List<T>>> getAll<T>(
    String table, {
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
    int? limit,
    int? offset,
  });

  Future<ApiResult<T>> getById<T>(String table, String id);

  Future<ApiResult<T>> create<T>(String table, Map<String, dynamic> data);

  Future<ApiResult<T>> update<T>(
    String table,
    String id,
    Map<String, dynamic> data,
  );

  Future<ApiResult<bool>> delete(String table, String id);

  /// Email OTP methods
  Future<AuthResult> sendEmailOtp(String email);
  Future<AuthResult> resendOtp(String email, String otpType);
  Future<AuthResult> verifyOtp(String email, String otpCode, String otpType);

  /// Phone/SMS OTP methods
  Future<AuthResult> sendPhoneOtp(String phoneNumber);
  Future<AuthResult> verifyPhoneOtp(String phoneNumber, String otpCode);
  Future<AuthResult> resendPhoneOtp(String phoneNumber);

  Future<AuthResult> requestPasswordReset(String email);
  Future<AuthResult> resetPassword(String newPassword);

  // Category counts methods
  Future<ApiResult<List<CategoryCount>>> getCategoryOrganizationCounts();
  Future<ApiResult<Map<String, int>>> getCategoryCountsMap();

  // Streams for real-time updates
  Stream<List<CategoryCount>> streamCategoryOrganizationCounts();
  Future<AuthResult> verifyPasswordResetTokenTwo(String token);
  Future<AuthResult> changePassword(String currentPassword, String newPassword);

  Future<ApiResult<bool>> deleteOrganization(String id);

  Future<ApiResult<List<Organization>>> getAllOrganizations({
    Map<String, dynamic>? filters,
    required String? orderBy,
    bool ascending = true,
    int? limit,
    int? offset,
  });

  Future<ApiResult<List<UserProfile>>> getOrganizationManagers(
    String organizationId,
  );

  /// Admin Management Methods

  /// Assigns a user as an admin to an organization
  /// Promotes regular users to admin role and assigns them to the organization
  Future<ApiResult<bool>> assignUserAsOrganizationAdmin(
    String userEmail,
    String organizationId,
  );

  /// Assigns a user as an admin to an organization by organization name
  Future<ApiResult<bool>> assignUserAsOrganizationAdminByName(
    String userEmail,
    String organizationName,
  );

  /// Removes an admin from an organization
  /// If this is the admin's last organization, they will be demoted to regular user
  Future<ApiResult<bool>> removeAdminFromOrganization(
    String userEmail,
    String organizationId,
  );

  /// Gets all admins for a specific organization
  Future<ApiResult<List<UserProfile>>> getOrganizationAdmins(
    String organizationId,
  );

  /// Gets all organizations that a user is admin of
  Future<ApiResult<List<Organization>>> getUserAdminOrganizations(
    String userId,
  );

  /// Assigns multiple users as admins to an organization
  Future<ApiResult<List<AdminAssignmentResult>>> assignMultipleUsersAsAdmins(
    List<String> userEmails,
    String organizationId,
  );

  /// Checks if a user is an admin of a specific organization
  Future<ApiResult<bool>> isUserAdminOfOrganization(
    String userId,
    String organizationId,
  );

  /// Storage methods
  Future<ApiResult<String>> uploadFile({
    required String bucketName,
    required String filePath,
    required Uint8List fileBytes,
    String? contentType,
  });

  Future<ApiResult<String>> uploadProfilePicture(
    Uint8List imageBytes, {
    required String userId,
    required Uint8List fileBytes,
    required String fileName,
    String? contentType,
  });

  Future<ApiResult<String>> uploadOrganizationLogo({
    required String organizationId,
    required Uint8List fileBytes,
    required String fileName,
    String? contentType,
  });

  Future<ApiResult<bool>> deleteFile({
    required String bucketName,
    required String filePath,
  });

  Future<ApiResult> processAppleLogin({
    required String authorizationCode,
    String? state,
  });

  Future updateOrganization(Organization updatedOrg) async {}

  Future<ApiResult<UserProfile>> createUserProfile({
    required String userId,
    required String username,
    required String fullName,
    required String email,
    required String role,
  });

  Future<ApiResult<List<Organization>>> getUserFollowedOrganizations({
    required String userId,
  });
  Future<ApiResult<List<UserProfile>>> getOrganizationFollowers(
    String organizationId,
  );
  Future<ApiResult<List<String>>> getUserFollowedOrganizationIds({
    required String userId,
  });

  /// Checks if a user follows a specific organization
  Future<ApiResult<bool>> isUserFollowingOrganization(
    String userId,
    String organizationId,
  );

  // Post Reactions
  Future<ApiResult<List<PostReaction>>> getPostReactions(String postId);
  Future<ApiResult<PostReaction>> upsertPostReaction(
    String postId,
    List<String> emojiReactions,
  );
  Future<ApiResult<bool>> removePostReaction(String postId);
  Future<ApiResult<PostReactionSummary>> getPostReactionSummary(String postId);
  Future<ApiResult<List<EmojiCount>>> getPostEmojiCounts(String postId);
  Future<ApiResult<PostReaction?>> getUserReactionForPost(String postId);
  Future<ApiResult<bool>> hasUserReactedToPost(String postId);
  Future<ApiResult<int>> getPostReactionCount(String postId);

  // Batch operations
  Future<ApiResult<Map<String, List<PostReaction>>>> getMultiplePostReactions(
    List<String> postIds,
  );
  Future<ApiResult<Map<String, PostReactionSummary>>>
  getMultiplePostReactionSummaries(List<String> postIds);

  // Streams
  Stream<List<PostReaction>> streamPostReactions(String postId);

  Future<ApiResult<bool>> unfollowOrganization(
    String id,
    String organizationId,
  );

  // ============================================================================
  // FCM TOKEN METHODS
  // ============================================================================

  /// Store FCM token for the current user
  Future<ApiResult<bool>> storeFCMToken(String token);

  /// Remove FCM token for the current user
  Future<ApiResult<bool>> removeFCMToken(String token);

  /// Get all FCM tokens for users following a specific channel
  Future<ApiResult<List<String>>> getFCMTokensForChannel(String channelId);

  /// Update FCM token for the current user
  Future<ApiResult<bool>> updateFCMToken(String oldToken, String newToken);

  // Feature flags
  Future<ApiResult<FeatureFlags>> getFeatureFlags();

  // ============================================================================
  // POST VIEWS METHODS
  // ============================================================================

  /// Batch insert post views for multiple posts
  /// This is more efficient than inserting views one by one
  Future<ApiResult<bool>> batchInsertPostViews(List<String> postIds);

  // ============================================================================
  // DIRECT MESSAGES METHODS
  // ============================================================================

  /// Get all direct message conversations for the current user
  Future<ApiResult<List<DirectMessageConversation>>> getDirectMessageConversations(String userId);

  /// Create or get an existing direct message conversation with an organization
  Future<ApiResult<DirectMessageConversation>> createOrGetDirectMessageConversation(
    String userId,
    String organizationId,
  );

  /// Get all messages for a specific conversation
  Future<ApiResult<List<DirectMessageItem>>> getDirectMessages(
    String conversationId, {
    int? limit,
    int? offset,
  });

  /// Send a direct message in a conversation
  Future<ApiResult<DirectMessageItem>> sendDirectMessage(
    String conversationId,
    String content, {
    String messageType = 'text',
    String? fileUrl,
  });

  /// Mark messages as read in a conversation
  Future<ApiResult<bool>> markDirectMessagesAsRead(
    String conversationId,
    String userId,
  );

  /// Stream messages for a specific conversation (real-time updates)
  Stream<List<DirectMessageItem>> streamDirectMessages(String conversationId);

  /// Stream conversations for a user (real-time updates)
  Stream<List<DirectMessageConversation>> streamDirectMessageConversations(String userId);

  /// Get all direct message conversations for organizations managed by an admin
  Future<ApiResult<List<DirectMessageConversation>>> getDirectMessageConversationsByOrganizations(
    List<String> organizationIds,
  );

  /// Stream conversations for organizations managed by an admin (real-time updates)
  Stream<List<DirectMessageConversation>> streamDirectMessageConversationsByOrganizations(
    List<String> organizationIds,
  );

  // ============================================================================
  // VEHICLE INQUIRY METHODS
  // ============================================================================

  /// Opens (or resumes) a buyer's conversation about a listing that already
  /// exists in `vehicle_listings`. The seller side is resolved server-side
  /// from the listing — a personal listing answers as its author, a dealer
  /// listing as the organization behind its feed — so the caller passes no
  /// seller id and cannot name one.
  Future<ApiResult<VehicleInquiryConversation>> createOrGetVehicleInquiry(
    String vehicleId,
  );

  /// Opens (or resumes) a buyer's conversation about a dealer-feed vehicle
  /// that may not have been mirrored into `vehicle_listings` yet.
  Future<ApiResult<VehicleInquiryConversation>> createOrGetDealerInquiry(
    VehicleListing listing,
  );

  /// Opens (or resumes) a buyer's conversation about a Market item. The
  /// seller is always the item's author, resolved server-side. Refused for a
  /// sold item unless the buyer already has a conversation about it.
  Future<ApiResult<VehicleInquiryConversation>> createOrGetMarketItemInquiry(
    String itemId,
  );

  /// Every Market inquiry the signed-in user takes part in — vehicles and
  /// items alike — as buyer, as a private seller, or as an admin of the
  /// dealership a conversation belongs to. Scoped server-side from the
  /// session, so it takes no user id.
  Future<ApiResult<List<VehicleInquiryConversation>>> getListingInquiries();

  Future<ApiResult<List<VehicleInquiryConversation>>> getVehicleInquiriesForListing(
    String vehicleId,
  );

  /// Every conversation about one Market item, for its seller.
  Future<ApiResult<List<VehicleInquiryConversation>>> getMarketItemInquiries(
    String itemId,
  );

  Future<ApiResult<VehicleInquiryConversation>> getVehicleInquiryById(
    String conversationId,
  );

  Future<ApiResult<List<DirectMessageItem>>> getVehicleInquiryMessages(
    String conversationId, {
    int? limit,
    int? offset,
  });

  Future<ApiResult<DirectMessageItem>> sendVehicleInquiryMessage(
    String conversationId,
    String content, {
    String messageType = 'text',
    String? fileUrl,
  });

  Future<ApiResult<bool>> markVehicleInquiryMessagesAsRead(
    String conversationId,
    String userId,
  );

  Stream<List<DirectMessageItem>> streamVehicleInquiryMessages(
    String conversationId,
  );

  // ============================================================================
  // FEEDBACK METHODS
  // ============================================================================

  /// Submit feedback (issue or suggestion) with optional screenshot
  Future<ApiResult<Map<String, dynamic>>> submitFeedback({
    required String userId,
    required String feedbackType,
    required String description,
    String? screenshotUrl,
  });
}
