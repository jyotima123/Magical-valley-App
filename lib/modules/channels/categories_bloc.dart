// lib/bloc/categories/categories_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/api_service.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';
import 'package:mvc_app/services/local_cache_service.dart';

// Events
abstract class CategoriesEvent {}

class LoadAllOrganizations extends CategoriesEvent {}

class RefreshAllOrganizations extends CategoriesEvent {}

class LoadCategoriesWithStatus extends CategoriesEvent {
  final bool forceRefresh;

  LoadCategoriesWithStatus({this.forceRefresh = false});
}

class RefreshCategoriesWithStatus extends CategoriesEvent {}

// States
abstract class CategoriesState {}

class CategoriesInitial extends CategoriesState {}

class CategoriesLoading extends CategoriesState {}

class CategoriesLoaded extends CategoriesState {
  final List<Organization> allOrganizations;

  CategoriesLoaded({required this.allOrganizations});
}

class CategoriesWithStatusLoaded extends CategoriesState {
  final List<Map<String, dynamic>> categoriesWithStatus;

  CategoriesWithStatusLoaded({required this.categoriesWithStatus});
}

class CategoriesError extends CategoriesState {
  final String message;

  CategoriesError({required this.message});
}

class CategoriesBloc extends Bloc<CategoriesEvent, CategoriesState> {
  final ApiService _apiService = SupabaseApiService.instance;

  CategoriesBloc() : super(CategoriesInitial()) {
    on<LoadAllOrganizations>(_onLoadAllOrganizations);
    on<RefreshAllOrganizations>(_onRefreshAllOrganizations);
    on<LoadCategoriesWithStatus>(_onLoadCategoriesWithStatus);
    on<RefreshCategoriesWithStatus>(_onRefreshCategoriesWithStatus);
  }

  Future<void> _onLoadAllOrganizations(
    LoadAllOrganizations event,
    Emitter<CategoriesState> emit,
  ) async {
    print("_onLoadAllOrganizations");
    emit(CategoriesLoading());

    try {
      final result = await _getAllOrganizationsWithFollowStatus();

      if (result.isSuccess) {
        emit(CategoriesLoaded(allOrganizations: result.data!));
      } else {
        emit(CategoriesError(message: result.error!));
      }
    } catch (e) {
      emit(CategoriesError(message: 'Failed to load organizations: $e'));
    }
  }

  Future<void> _onRefreshAllOrganizations(
    RefreshAllOrganizations event,
    Emitter<CategoriesState> emit,
  ) async {
    print("_onRefreshAllOrganizations");

    try {
      final result = await _getAllOrganizationsWithFollowStatus();

      if (result.isSuccess) {
        emit(CategoriesLoaded(allOrganizations: result.data!));
      } else {
        emit(CategoriesError(message: result.error!));
      }
    } catch (e) {
      emit(CategoriesError(message: 'Failed to refresh organizations: $e'));
    }
  }

  Future<void> _onLoadCategoriesWithStatus(
    LoadCategoriesWithStatus event,
    Emitter<CategoriesState> emit,
  ) async {
    print("_onLoadCategoriesWithStatus");
    emit(CategoriesLoading());

    try {
      // Clear cache if force refresh is requested
      if (event.forceRefresh) {
        await LocalCacheService.instance.clearAllOrganizationsCache();
      }

      final result = await _getCategoriesWithOrganizationStatus();

      if (result.isSuccess) {
        // Also persist counts to local cache for quick access
        final countsMap = <String, int>{};
        for (final item in result.data!) {
          final id = item['id'];
          final count = item['organization_count'] ?? 0;
          if (id != null) {
            countsMap[id.toString()] = count is int ? count : int.tryParse('$count') ?? 0;
          }
        }
        await LocalCacheService.instance.setCategoryCountsMap(countsMap);

        emit(CategoriesWithStatusLoaded(categoriesWithStatus: result.data!));
      } else {
        emit(CategoriesError(message: result.error!));
      }
    } catch (e) {
      emit(
        CategoriesError(message: 'Failed to load categories with status: $e'),
      );
    }
  }

  Future<void> _onRefreshCategoriesWithStatus(
    RefreshCategoriesWithStatus event,
    Emitter<CategoriesState> emit,
  ) async {
    print("_onRefreshCategoriesWithStatus");
    emit(CategoriesLoading());
    
    try {
      // Clear all organization caches to force fresh data
      await LocalCacheService.instance.clearAllOrganizationsCache();
      
      // Fetch fresh data
      final result = await _getCategoriesWithOrganizationStatus();

      if (result.isSuccess) {
        // Also persist counts to local cache for quick access
        final countsMap = <String, int>{};
        for (final item in result.data!) {
          final id = item['id'];
          final count = item['organization_count'] ?? 0;
          if (id != null) {
            countsMap[id.toString()] = count is int ? count : int.tryParse('$count') ?? 0;
          }
        }
        await LocalCacheService.instance.setCategoryCountsMap(countsMap);

        emit(CategoriesWithStatusLoaded(categoriesWithStatus: result.data!));
      } else {
        emit(CategoriesError(message: result.error!));
      }
    } catch (e) {
      emit(
        CategoriesError(message: 'Failed to refresh categories with status: $e'),
      );
    }
  }

  // Get all organizations with follow status.
  // Delegates to getAllOrganizations which queries organizations_overview —
  // a view that computes live follower_count and is_following in one query.
  Future<ApiResult<List<Organization>>>
  _getAllOrganizationsWithFollowStatus() async {
    print("_getAllOrganizationsWithFollowStatus");
    return _apiService.getAllOrganizations(orderBy: null);
  }

  // Get categories with organization count and status using efficient API method
  Future<ApiResult<List<Map<String, dynamic>>>>
  _getCategoriesWithOrganizationStatus() async {
    print("_getCategoriesWithOrganizationStatus");
    try {
      // Use the new efficient category counts method
      final categoryCountsResult = await _apiService
          .getCategoryOrganizationCounts();

      if (!categoryCountsResult.isSuccess) {
        return ApiResult.error(categoryCountsResult.error!);
      }

      // Convert CategoryCount objects to the expected format
      final categoriesWithStatus = categoryCountsResult.data!.map((
        categoryCount,
      ) {
        return {
          'id': categoryCount.categoryId,
          'name': categoryCount.categoryName,
          'description': categoryCount.categoryDescription,
          'organization_count': categoryCount.organizationCount,
          'isSelected':
              categoryCount.organizationCount >
              0, // true if has organizations, false if empty
        };
      }).toList();

      return ApiResult.success(categoriesWithStatus);
    } catch (e) {
      return ApiResult.error(
        'Failed to fetch categories with organization status: $e',
      );
    }
  }
}
