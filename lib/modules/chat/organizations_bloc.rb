// // lib/bloc/organizations/organizations_bloc.dart

// import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:mvc_app/services/api_repository.dart';
// import 'package:mvc_app/services/api_service.dart';
// import 'package:mvc_app/services/api/supabase_api_service.dart';
// import 'package:mvc_app/modules/chat/models/organization_event.dart';
// import 'package:mvc_app/modules/chat/models/organization_model.dart';

// class OrganizationsBloc extends Bloc<OrganizationsEvent, OrganizationsState> {
//   final ApiService _apiService = SupabaseApiService.instance;

//   OrganizationsBloc() : super(OrganizationsInitial()) {
//     on<LoadOrganizationsByCategory>(_onLoadOrganizationsByCategory);
//     on<LoadPreloadedOrganizations>(_onLoadPreloadedOrganizations);
//     on<FollowOrganization>(_onFollowOrganization);
//     on<UnfollowOrganization>(_onUnfollowOrganization);
//     on<RefreshOrganizations>(_onRefreshOrganizations);
//   }

//   Future<void> _onLoadOrganizationsByCategory(
//     LoadOrganizationsByCategory event,
//     Emitter<OrganizationsState> emit,
//   ) async {
//     print("_onLoadOrganizationsByCategory");
//     emit(OrganizationsLoading());

//     try {
//       // Get organizations that belong to the selected category
//       final result = await _getOrganizationsByCategory(event.categoryId);

//       if (result.isSuccess) {
//         emit(
//           OrganizationsLoaded(
//             organizations: result.data!,
//             categoryId: event.categoryId,
//             categoryName: event.categoryName,
//           ),
//         );
//       } else {
//         emit(OrganizationsError(message: result.error!));
//       }
//     } catch (e) {
//       emit(OrganizationsError(message: 'Failed to load organizations: $e'));
//     }
//   }

//   Future<void> _onLoadPreloadedOrganizations(
//     LoadPreloadedOrganizations event,
//     Emitter<OrganizationsState> emit,
//   ) async {
//     // Immediately emit the loaded state with the preloaded organizations
//     emit(
//       OrganizationsLoaded(
//         organizations: event.organizations,
//         categoryId: event.categoryId,
//         categoryName: event.categoryName,
//       ),
//     );

//     // Optionally: You could still refresh the data in the background
//     // to ensure it's up-to-date
//     try {
//       final result = await _getOrganizationsWithFollowStatus(
//         event.categoryId,
//         null,
//       );

//       if (result.isSuccess) {
//         emit(
//           OrganizationsLoaded(
//             organizations: result.data!,
//             categoryId: event.categoryId,
//             categoryName: event.categoryName,
//           ),
//         );
//       }
//       // If there's an error, we keep showing the preloaded data
//     } catch (e) {
//       // Silently fail or log the error, but don't show to user
//       print('Failed to refresh preloaded organizations: $e');
//     }
//   }

//   Future<void> _onFollowOrganization(
//     FollowOrganization event,
//     Emitter<OrganizationsState> emit,
//   ) async {
//     print("_onFollowOrganization");
//     final currentState = state;
//     if (currentState is OrganizationsLoaded) {
//       // Show loading state for specific organization
//       emit(
//         OrganizationFollowLoading(
//           organizations: currentState.organizations,
//           categoryName: currentState.categoryName,
//           loadingOrganizationId: event.organizationId,
//         ),
//       );

//       try {
//         // Get current user
//         final userResult = await _apiService.getCurrentUser();
//         if (userResult == null || !userResult.isSuccess) {
//           emit(OrganizationsError(message: 'User not authenticated'));
//           return;
//         }

//         // Create follow relationship
//         final followData = {
//           'user_id': userResult.userId,
//           'organization_id': event.organizationId,
//         };

//         final result = await _apiService.create('user_follows', followData);

//         if (result.isSuccess) {
//           // Update the organization's follow status and follower count
//           final updatedOrganizations = currentState.organizations.map((org) {
//             if (org.id == event.organizationId) {
//               return org.copyWith(
//                 isFollowing: true,
//                 followerCount: org.followerCount + 1,
//               );
//             }
//             return org;
//           }).toList();

//           emit(
//             OrganizationsLoaded(
//               organizations: updatedOrganizations,
//               categoryId: currentState.categoryId,
//               categoryName: currentState.categoryName,
//             ),
//           );
//         } else {
//           emit(OrganizationsError(message: result.error!));
//           // Revert to previous state after showing error briefly
//           Future.delayed(Duration(seconds: 2), () {
//             if (!emit.isDone) {
//               emit(
//                 OrganizationsLoaded(
//                   organizations: currentState.organizations,
//                   categoryId: currentState.categoryId,
//                   categoryName: currentState.categoryName,
//                 ),
//               );
//             }
//           });
//         }
//       } catch (e) {
//         emit(OrganizationsError(message: 'Failed to follow organization: $e'));
//         // Revert to previous state after showing error briefly
//         Future.delayed(Duration(seconds: 2), () {
//           if (!emit.isDone) {
//             emit(
//               OrganizationsLoaded(
//                 organizations: currentState.organizations,
//                 categoryId: currentState.categoryId,
//                 categoryName: currentState.categoryName,
//               ),
//             );
//           }
//         });
//       }
//     }
//   }

//   Future<void> _onUnfollowOrganization(
//     UnfollowOrganization event,
//     Emitter<OrganizationsState> emit,
//   ) async {
//     print("_onUnfollowOrganization");
//     final currentState = state;
//     if (currentState is OrganizationsLoaded) {
//       // Show loading state for specific organization
//       emit(
//         OrganizationFollowLoading(
//           organizations: currentState.organizations,
//           categoryName: currentState.categoryName,
//           loadingOrganizationId: event.organizationId,
//         ),
//       );

//       try {
//         // Get current user
//         final userResult = await _apiService.getCurrentUser();
//         if (userResult == null || !userResult.isSuccess) {
//           emit(OrganizationsError(message: 'User not authenticated'));
//           return;
//         }

//         // Delete follow relationship
//         // Note: You'll need to implement a custom method in your API service for this
//         final result = await _deleteUserFollow(
//           userResult.userId!,
//           event.organizationId,
//         );

//         if (result.isSuccess) {
//           // Update the organization's follow status and follower count
//           final updatedOrganizations = currentState.organizations.map((org) {
//             if (org.id == event.organizationId) {
//               return org.copyWith(
//                 isFollowing: false,
//                 followerCount: org.followerCount - 1,
//               );
//             }
//             return org;
//           }).toList();

//           emit(
//             OrganizationsLoaded(
//               organizations: updatedOrganizations,
//               categoryId: currentState.categoryId,
//               categoryName: currentState.categoryName,
//             ),
//           );
//         } else {
//           emit(OrganizationsError(message: result.error!));
//           // Revert to previous state after showing error briefly
//           Future.delayed(Duration(seconds: 2), () {
//             if (!emit.isDone) {
//               emit(
//                 OrganizationsLoaded(
//                   organizations: currentState.organizations,
//                   categoryId: currentState.categoryId,
//                   categoryName: currentState.categoryName,
//                 ),
//               );
//             }
//           });
//         }
//       } catch (e) {
//         emit(
//           OrganizationsError(message: 'Failed to unfollow organization: $e'),
//         );
//         // Revert to previous state after showing error briefly
//         Future.delayed(Duration(seconds: 2), () {
//           if (!emit.isDone) {
//             emit(
//               OrganizationsLoaded(
//                 organizations: currentState.organizations,
//                 categoryId: currentState.categoryId,
//                 categoryName: currentState.categoryName,
//               ),
//             );
//           }
//         });
//       }
//     }
//   }

//   Future<void> _onRefreshOrganizations(
//     RefreshOrganizations event,
//     Emitter<OrganizationsState> emit,
//   ) async {
//     print("_onRefreshOrganizations");
//     final currentState = state;
//     if (currentState is OrganizationsLoaded) {
//       // Re-trigger the load for the current category
//       // You'll need to store the current category ID to make this work
//       // For now, just emit the current state
//       emit(currentState);
//     }
//   }

//   // Helper method to get organizations by category with follow status
//   Future<ApiResult<List<Organization>>> _getOrganizationsByCategory(
//     String categoryId,
//   ) async {
//     print("_getOrganizationsByCategory");
//     try {
//       // Get current user for follow status
//       final userResult = await _apiService.getCurrentUser();
//       final currentUserId = userResult?.userId;

//       // Query organizations with category filter and follow status
//       // This is a complex query that you might need to implement as a custom API method
//       final result = await _getOrganizationsWithFollowStatus(
//         categoryId,
//         currentUserId,
//       );

//       return result;
//     } catch (e) {
//       return ApiResult.error('Failed to fetch organizations: $e');
//     }
//   }

//   // ! TODO: How to filter this?
//   // Custom method to get organizations with follow status
//   Future<ApiResult<List<Organization>>> _getOrganizationsWithFollowStatus(
//     String categoryId,
//     String? userId,
//   ) async {
//     print("_getOrganizationsWithFollowStatus");
//     try {
//       // This would need to be implemented in your SupabaseApiService
//       // For now, using a basic approach with multiple queries

//       // 1. Get organizations that belong to the category
//       final orgResult = await _apiService.getAll<Map<String, dynamic>>(
//         'organizations',
//         // You'll need to join with organization_categories table
//         // This is a simplified version - you might need a custom query
//       );

//       if (!orgResult.isSuccess) {
//         return ApiResult.error(orgResult.error!);
//       }

//       final organizations = <Organization>[];

//       for (final orgData in orgResult.data!) {
//         // Check if user follows this organization
//         bool isFollowing = false;
//         if (userId != null) {
//           final followResult = await _apiService.getAll<Map<String, dynamic>>(
//             'user_follows',
//             filters: {'user_id': userId, 'organization_id': orgData['id']},
//             limit: 1,
//           );
//           isFollowing = followResult.isSuccess && followResult.data!.isNotEmpty;
//         }

//         // Add follow status to organization data
//         final orgDataWithFollow = Map<String, dynamic>.from(orgData);
//         orgDataWithFollow['is_following'] = isFollowing;

//         organizations.add(Organization.fromJson(orgDataWithFollow));
//       }

//       return ApiResult.success(organizations);
//     } catch (e) {
//       return ApiResult.error(
//         'Failed to fetch organizations with follow status: $e',
//       );
//     }
//   }

//   // Custom method to delete user follow relationship
//   Future<ApiResult<bool>> _deleteUserFollow(
//     String userId,
//     String organizationId,
//   ) async {
//     print("_deleteUserFollow");
//     try {
//       // This would need to be implemented in your SupabaseApiService
//       // as a custom method to delete by composite key

//       // For now, using a workaround
//       final followResult = await _apiService.getAll<Map<String, dynamic>>(
//         'user_follows',
//         filters: {'user_id': userId, 'organization_id': organizationId},
//         limit: 1,
//       );

//       if (followResult.isSuccess && followResult.data!.isNotEmpty) {
//         final followRecord = followResult.data!.first;
//         // Assuming there's an ID field in the follow record
//         if (followRecord.containsKey('id')) {
//           return await _apiService.delete('user_follows', followRecord['id']);
//         } else {
//           // If no ID field, you'll need to implement a custom delete method
//           return ApiResult.error('Unable to delete follow relationship');
//         }
//       }

//       return ApiResult.success(true);
//     } catch (e) {
//       return ApiResult.error('Failed to unfollow organization: $e');
//     }
//   }
// }
