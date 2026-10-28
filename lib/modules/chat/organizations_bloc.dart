// lib/bloc/organizations/organizations_bloc.dart

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/modules/chat/chat_service.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/api_service.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/modules/chat/models/organization_event.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';
import 'package:mvc_app/services/local_cache_service.dart';

class OrganizationsBloc extends Bloc<OrganizationsEvent, OrganizationsState> {
  final ApiService _apiService = SupabaseApiService.instance;

  // Store current category info for refresh functionality
  String? _currentCategoryId;
  String? _currentCategoryName;

  OrganizationsBloc() : super(OrganizationsInitial()) {
    on<LoadOrganizationsByCategory>(_onLoadOrganizationsByCategory);
    on<FollowOrganization>(_onFollowOrganization);
    on<UnfollowOrganization>(_onUnfollowOrganization);
    on<RefreshOrganizations>(_onRefreshOrganizations);
  }

  Future<void> _onLoadOrganizationsByCategory(
    LoadOrganizationsByCategory event,
    Emitter<OrganizationsState> emit,
  ) async {
    emit(OrganizationsLoading());

    _currentCategoryId = event.categoryId;
    _currentCategoryName = event.categoryName;

    try {
      // 1) Fetch current counts map once and pick this category's count
      final countsResult = await _apiService.getCategoryCountsMap();
      int currentCountForCategory = 0;
      if (countsResult.isSuccess) {
        final countsMap = countsResult.data!;
        if (event.categoryId == null) {
          // All category: sum all counts
          currentCountForCategory = countsMap.values.fold(0, (a, b) => a + b);
        } else {
          currentCountForCategory = countsMap[event.categoryId] ?? 0;
        }
      }

      // 2) Check cache (skip if forceRefresh is true)
      final cache = LocalCacheService.instance;
      final cachedCount = await cache.getCachedOrganizationsCountForCategory(
        event.categoryId,
      );
      final cachedOrgs = await cache.getOrganizationsForCategory(
        event.categoryId,
      );

      // Check if cache is older than 1 day
      final cacheUpdatedAt = await cache.getOrganizationsUpdatedAt(
        event.categoryId,
      );
      final isCacheExpired =
          cacheUpdatedAt == null ||
          DateTime.now().difference(cacheUpdatedAt).inHours >= 24;

      final bool canServeFromCache =
          !event.forceRefresh &&
          !isCacheExpired &&
          cachedOrgs != null &&
          cachedCount != null &&
          currentCountForCategory <= cachedCount;

      if (canServeFromCache) {
        // Sync follow status from API to ensure cache is accurate
        final userResult = await _apiService.getCurrentUser();
        if (userResult != null && userResult.isSuccess) {
          String? userProfileId;
          // Get the user profile ID
          final userProfileResult = await _apiService
              .getAll<Map<String, dynamic>>(
                'user_profiles',
                filters: {'auth_user_id': userResult.userId},
                limit: 1,
              );

          if (userProfileResult.isSuccess &&
              userProfileResult.data!.isNotEmpty) {
            userProfileId = userProfileResult.data!.first['id'] as String;
          }

          // Get current follow status from API
          if (userProfileId != null) {
            final followedIdsResult = await _apiService
                .getUserFollowedOrganizationIds(userId: userProfileId);

            if (followedIdsResult.isSuccess) {
              final followedIds = followedIdsResult.data!.toSet();

              // Update cached organizations with current follow status
              final updatedOrgs = cachedOrgs.map((org) {
                final isFollowing = followedIds.contains(org.id);
                if (org.isFollowing != isFollowing) {
                  return org.copyWith(isFollowing: isFollowing);
                }
                return org;
              }).toList();

              // Update cache with synced follow status
              await cache.updateFollowStatusInCache(event.categoryId, {
                for (final org in updatedOrgs) org.id: org.isFollowing,
              });

              emit(
                OrganizationsLoaded(
                  organizations: updatedOrgs,
                  categoryName: event.categoryName,
                  filteredCategoryId: event.categoryId,
                ),
              );
              return;
            }
          }
        }

        emit(
          OrganizationsLoaded(
            organizations: cachedOrgs,
            categoryName: event.categoryName,
            filteredCategoryId: event.categoryId,
          ),
        );
        return;
      }

      // 3) Network fetch if missing or count increased
      final result = await _getOrganizationsByCategory(event.categoryId);

      if (result.isSuccess) {
        final orgs = result.data!;
        // Persist to cache with the latest observed count
        await cache.setOrganizationsForCategory(
          event.categoryId,
          orgs,
          currentCountForCategory,
        );

        emit(
          OrganizationsLoaded(
            organizations: orgs,
            categoryName: event.categoryName,
            filteredCategoryId: event.categoryId,
          ),
        );
      } else {
        // Fall back to cache if available even on error
        if (cachedOrgs != null && cachedOrgs.isNotEmpty) {
          emit(
            OrganizationsLoaded(
              organizations: cachedOrgs,
              categoryName: event.categoryName,
              filteredCategoryId: event.categoryId,
            ),
          );
        } else {
          emit(OrganizationsError(message: result.error!));
        }
      }
    } catch (e) {
      emit(
        OrganizationsError(
          message: 'Failed to load organizations: ${e.toString()}',
        ),
      );
    }
  }

  Future<void> _onFollowOrganization(
    FollowOrganization event,
    Emitter<OrganizationsState> emit,
  ) async {
    final currentState = state;
    if (currentState is OrganizationsLoaded) {
      // Show loading state for specific organization
      emit(
        OrganizationFollowLoading(
          organizations: currentState.organizations,
          categoryName: currentState.categoryName,
          loadingOrganizationId: event.organizationId,
        ),
      );

      try {
        // Get current auth user
        final userResult = await _apiService.getCurrentUser();
        if (userResult == null || !userResult.isSuccess) {
          emit(OrganizationsError(message: 'User not authenticated'));
          return;
        }

        // Get the user profile ID from the user_profiles table
        final userProfileResult = await _apiService
            .getAll<Map<String, dynamic>>(
              'user_profiles',
              filters: {'id': userResult.userId},
              limit: 1,
            );

        if (!userProfileResult.isSuccess || userProfileResult.data!.isEmpty) {
          emit(OrganizationsError(message: 'User profile not found'));
          return;
        }

        final userProfileId = userProfileResult.data!.first['id'] as String;

        // Create follow relationship using the user_profiles.id
        final followData = {
          'user_id': userProfileId,
          'organization_id': event.organizationId,
        };

        final result = await _apiService.create('user_follows', followData);

        if (result.isSuccess) {
          // Get updated follower count from the view
          final updatedFollowerCount = await _getOrganizationFollowerCount(
            event.organizationId,
          );

          // Update the organization's follow status and follower count
          final updatedOrganizations = currentState.organizations.map((org) {
            if (org.id == event.organizationId) {
              return org.copyWith(
                isFollowing: true,
                followerCount: updatedFollowerCount ?? (org.followerCount + 1),
              );
            }
            return org;
          }).toList();

          // Update cache with new follow status
          final cache = LocalCacheService.instance;
          final followStatusMap = {
            for (final org in updatedOrganizations) org.id: org.isFollowing,
          };
          await cache.updateFollowStatusInCache(
            currentState.filteredCategoryId,
            followStatusMap,
          );

          // Also update the cache with the full updated list
          final countsResult = await _apiService.getCategoryCountsMap();
          int currentCountForCategory = 0;
          if (countsResult.isSuccess) {
            final countsMap = countsResult.data!;
            if (currentState.filteredCategoryId == null) {
              currentCountForCategory = countsMap.values.fold(
                0,
                (a, b) => a + b,
              );
            } else {
              currentCountForCategory =
                  countsMap[currentState.filteredCategoryId] ?? 0;
            }
          }
          await cache.setOrganizationsForCategory(
            currentState.filteredCategoryId,
            updatedOrganizations,
            currentCountForCategory,
          );

          // Refresh channels and update notification badge after unfollow
          try {
            await ChatService.refreshChannelsAndUpdateBadge(userProfileId);
          } catch (e) {
            print('Failed to refresh channels after unfollow: $e');
          }

          emit(
            OrganizationsLoaded(
              organizations: updatedOrganizations,
              categoryName: currentState.categoryName,
              filteredCategoryId: currentState.filteredCategoryId,
            ),
          );
        } else {
          emit(OrganizationsError(message: result.error!));
          // Revert to previous state after showing error briefly
          Future.delayed(Duration(seconds: 2), () {
            if (!emit.isDone) {
              emit(
                OrganizationsLoaded(
                  organizations: currentState.organizations,
                  categoryName: currentState.categoryName,
                  filteredCategoryId: currentState.filteredCategoryId,
                ),
              );
            }
          });
        }
      } catch (e) {
        emit(OrganizationsError(message: 'Failed to follow organization: $e'));
        // Revert to previous state after showing error briefly
        Future.delayed(Duration(seconds: 2), () {
          if (!emit.isDone) {
            emit(
              OrganizationsLoaded(
                organizations: currentState.organizations,
                categoryName: currentState.categoryName,
                filteredCategoryId: currentState.filteredCategoryId,
              ),
            );
          }
        });
      }
    }
  }

  Future<void> _onUnfollowOrganization(
    UnfollowOrganization event,
    Emitter<OrganizationsState> emit,
  ) async {
    print('DEBUG: Starting unfollow for organization ${event.organizationId}');

    final currentState = state;
    if (currentState is OrganizationsLoaded) {
      print('DEBUG: Current state is OrganizationsLoaded');

      // Show loading state for specific organization
      emit(
        OrganizationFollowLoading(
          organizations: currentState.organizations,
          categoryName: currentState.categoryName,
          loadingOrganizationId: event.organizationId,
        ),
      );

      try {
        print('DEBUG: Getting current user...');
        // Get current auth user
        final userResult = await _apiService.getCurrentUser();
        if (userResult == null || !userResult.isSuccess) {
          print('DEBUG: User not authenticated');
          emit(OrganizationsError(message: 'User not authenticated'));
          return;
        }

        print('DEBUG: User authenticated, getting user profile...');
        // Get the user profile ID from the user_profiles table
        final userProfileResult = await _apiService
            .getAll<Map<String, dynamic>>(
              'user_profiles',
              filters: {'id': userResult.userId},
              limit: 1,
            );

        if (!userProfileResult.isSuccess || userProfileResult.data!.isEmpty) {
          print('DEBUG: User profile not found');
          emit(OrganizationsError(message: 'User profile not found'));
          return;
        }

        final userProfileId = userProfileResult.data!.first['id'] as String;
        print('DEBUG: User profile ID: $userProfileId');

        print('DEBUG: Deleting follow relationship...');
        // Delete follow relationship using the user_profiles.id
        final result = await _deleteUserFollow(
          userProfileId,
          event.organizationId,
        );

        if (result.isSuccess) {
          print('DEBUG: Follow relationship deleted successfully');

          // Get updated follower count from the view
          final updatedFollowerCount = await _getOrganizationFollowerCount(
            event.organizationId,
          );

          print('DEBUG: Updated follower count: $updatedFollowerCount');

          // Update the organization's follow status and follower count
          final updatedOrganizations = currentState.organizations.map((org) {
            if (org.id == event.organizationId) {
              return org.copyWith(
                isFollowing: false,
                followerCount: updatedFollowerCount ?? (org.followerCount - 1),
              );
            }
            return org;
          }).toList();

          // Update cache with new follow status
          final cache = LocalCacheService.instance;
          final followStatusMap = {
            for (final org in updatedOrganizations) org.id: org.isFollowing,
          };
          await cache.updateFollowStatusInCache(
            currentState.filteredCategoryId,
            followStatusMap,
          );

          // Also update the cache with the full updated list
          final countsResult = await _apiService.getCategoryCountsMap();
          int currentCountForCategory = 0;
          if (countsResult.isSuccess) {
            final countsMap = countsResult.data!;
            if (currentState.filteredCategoryId == null) {
              currentCountForCategory = countsMap.values.fold(
                0,
                (a, b) => a + b,
              );
            } else {
              currentCountForCategory =
                  countsMap[currentState.filteredCategoryId] ?? 0;
            }
          }
          await cache.setOrganizationsForCategory(
            currentState.filteredCategoryId,
            updatedOrganizations,
            currentCountForCategory,
          );

          print('DEBUG: Emitting OrganizationsLoaded state');
          emit(
            OrganizationsLoaded(
              organizations: updatedOrganizations,
              categoryName: currentState.categoryName,
              filteredCategoryId: currentState.filteredCategoryId,
            ),
          );
        } else {
          print('DEBUG: Failed to delete follow relationship: ${result.error}');
          emit(OrganizationsError(message: result.error!));
        }
      } catch (e) {
        print('DEBUG: Exception occurred: $e');
        emit(
          OrganizationsError(message: 'Failed to unfollow organization: $e'),
        );
      }
    } else {
      print(
        'DEBUG: Current state is not OrganizationsLoaded: ${currentState.runtimeType}',
      );
    }
  }

  Future<void> _onRefreshOrganizations(
    RefreshOrganizations event,
    Emitter<OrganizationsState> emit,
  ) async {
    // Always clear cache for the current category to force fresh data
    // This works even when categoryId is null (for "All" category)
    if (_currentCategoryName != null) {
      final cache = LocalCacheService.instance;
      await cache.clearOrganizationsCacheForCategory(_currentCategoryId);

      // Re-trigger the load for the current category with forceRefresh=true
      // This bypasses cache check and fetches fresh data from the network
      add(
        LoadOrganizationsByCategory(
          categoryId: _currentCategoryId,
          categoryName: _currentCategoryName!,
          forceRefresh: true, // Force network fetch, bypass cache
        ),
      );
    }
  }

  // Helper method to get follower count from the public view
  Future<int?> _getOrganizationFollowerCount(String organizationId) async {
    try {
      final result = await _apiService.getAll<Map<String, dynamic>>(
        'public_follower_counts',
        filters: {'organization_id': organizationId},
        limit: 1,
      );

      if (result.isSuccess && result.data!.isNotEmpty) {
        return result.data!.first['follower_count'] as int?;
      }
      return null;
    } catch (e) {
      print('Error fetching follower count: $e');
      return null;
    }
  }

  // Helper method to get organizations by category with follow status
  Future<ApiResult<List<Organization>>> _getOrganizationsByCategory(
    String? categoryId, // Changed to nullable
  ) async {
    try {
      // Get current user for follow status
      final userResult = await _apiService.getCurrentUser();
      String? currentUserProfileId;

      // ! This is redundant if the public.user_profile.id is now the same as auth.users.id
      if (userResult != null && userResult.isSuccess) {
        // Get the user profile ID from the user_profiles table
        final userProfileResult = await _apiService
            .getAll<Map<String, dynamic>>(
              'user_profiles',
              filters: {'auth_user_id': userResult.userId},
              limit: 1,
            );

        if (userProfileResult.isSuccess && userProfileResult.data!.isNotEmpty) {
          currentUserProfileId = userProfileResult.data!.first['id'] as String;
        }
      }

      // If categoryId is null, return all organizations
      if (categoryId == null) {
        final result = await _getAllOrganizationsWithFollowerCounts(
          currentUserProfileId,
        );
        return result;
      }

      // Use junction table approach with follower counts from view for specific category
      final result = await _getOrganizationsWithJunctionTableAndFollowerCounts(
        categoryId,
        currentUserProfileId,
      );

      return result;
    } catch (e) {
      return ApiResult.error('Failed to fetch organizations: $e');
    }
  }

  // Get all organizations with live follower counts and is_following.
  // Delegates to getAllOrganizations which queries organizations_overview.
  Future<ApiResult<List<Organization>>> _getAllOrganizationsWithFollowerCounts(
    String? userProfileId,
  ) async {
    return _apiService.getAllOrganizations(orderBy: null);
  }

  // Get organizations for a specific category with live follower counts.
  // Two queries: one for the category membership IDs, one to organizations_overview.
  Future<ApiResult<List<Organization>>>
  _getOrganizationsWithJunctionTableAndFollowerCounts(
    String categoryId,
    String? userProfileId,
  ) async {
    try {
      // 1. Get organization IDs that belong to this category.
      final categoryOrgResult = await _apiService.getAll<Map<String, dynamic>>(
        'organization_categories',
        filters: {'category_id': categoryId},
      );

      if (!categoryOrgResult.isSuccess) {
        return ApiResult.error(categoryOrgResult.error!);
      }

      final organizationIds = categoryOrgResult.data!
          .map((item) => item['organization_id'] as String)
          .toSet();

      if (organizationIds.isEmpty) {
        return ApiResult.success([]);
      }

      // 2. Fetch all orgs from the overview view and filter to this category.
      // organizations_overview provides live follower_count and is_following.
      final allOrgsResult = await _apiService.getAllOrganizations(orderBy: null);

      if (!allOrgsResult.isSuccess) {
        return ApiResult.error(allOrgsResult.error!);
      }

      final organizations = allOrgsResult.data!
          .where((org) => organizationIds.contains(org.id))
          .toList();

      return ApiResult.success(organizations);
    } catch (e) {
      return ApiResult.error(
        'Failed to fetch organizations with follower counts: $e',
      );
    }
  }

  // Custom method to delete user follow relationship
  Future<ApiResult<bool>> _deleteUserFollow(
    String userId,
    String organizationId,
  ) async {
    try {
      // Get the follow record first
      final followResult = await _apiService.getAll<Map<String, dynamic>>(
        'user_follows',
        filters: {'user_id': userId, 'organization_id': organizationId},
        limit: 1,
      );

      if (followResult.isSuccess && followResult.data!.isNotEmpty) {
        final followRecord = followResult.data!.first;
        // Assuming there's an ID field in the follow record
        if (followRecord.containsKey('id')) {
          return await _apiService.delete('user_follows', followRecord['id']);
        } else {
          return ApiResult.error('Unable to delete follow relationship');
        }
      }

      return ApiResult.success(true);
    } catch (e) {
      return ApiResult.error('Failed to unfollow organization: $e');
    }
  }
}
