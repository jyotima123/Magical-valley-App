// lib/modules/chat/models/organizations_event.dart

import 'package:mvc_app/modules/chat/models/organization_model.dart';

abstract class OrganizationsEvent {}

class LoadOrganizationsByCategory extends OrganizationsEvent {
  final String? categoryId;
  final String categoryName;
  final bool forceRefresh;

  LoadOrganizationsByCategory({
    required this.categoryId,
    required this.categoryName,
    this.forceRefresh = false,
  });
}

class FollowOrganization extends OrganizationsEvent {
  final String organizationId;

  FollowOrganization({required this.organizationId});
}

class UnfollowOrganization extends OrganizationsEvent {
  final String organizationId;

  UnfollowOrganization({required this.organizationId});
}

class RefreshOrganizations extends OrganizationsEvent {}

// lib/bloc/organizations/organizations_state.dart
abstract class OrganizationsState {}

class OrganizationsInitial extends OrganizationsState {}

class OrganizationsLoading extends OrganizationsState {}

class OrganizationsLoaded extends OrganizationsState {
  final List<Organization> organizations;
  final String? filteredCategoryId; // If it's null, return all categories
  final String categoryName;

  OrganizationsLoaded({
    required this.organizations,
    required this.categoryName,
    required this.filteredCategoryId,
  });
}

class OrganizationsError extends OrganizationsState {
  final String message;

  OrganizationsError({required this.message});
}

class OrganizationFollowLoading extends OrganizationsState {
  final List<Organization> organizations;
  final String categoryName;
  final String loadingOrganizationId;

  OrganizationFollowLoading({
    required this.organizations,
    required this.categoryName,
    required this.loadingOrganizationId,
  });
}
