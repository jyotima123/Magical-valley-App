// auth_state.dart
// Holds Login and SignUp Status

import 'package:equatable/equatable.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthWelcomeState extends AuthState {
  final bool isKeyboardVisible;

  const AuthWelcomeState({this.isKeyboardVisible = false});

  @override
  List<Object?> get props => [isKeyboardVisible];
}

class AuthLoginFormState extends AuthState {
  final bool isLoading;
  final String? errorMessage;
  final bool isKeyboardVisible;

  const AuthLoginFormState({
    this.isLoading = false,
    this.errorMessage,
    this.isKeyboardVisible = false,
  });

  AuthLoginFormState copyWith({
    bool? isLoading,
    String? errorMessage,
    bool? isKeyboardVisible,
  }) {
    return AuthLoginFormState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      isKeyboardVisible: isKeyboardVisible ?? this.isKeyboardVisible,
    );
  }

  @override
  List<Object?> get props => [isLoading, errorMessage, isKeyboardVisible];
}

class AuthSignupFormState extends AuthState {
  final bool isLoading;
  final String? errorMessage;
  final bool isKeyboardVisible;

  const AuthSignupFormState({
    this.isLoading = false,
    this.errorMessage,
    this.isKeyboardVisible = false,
  });

  AuthSignupFormState copyWith({
    bool? isLoading,
    String? errorMessage,
    bool? isKeyboardVisible,
  }) {
    return AuthSignupFormState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      isKeyboardVisible: isKeyboardVisible ?? this.isKeyboardVisible,
    );
  }

  @override
  List<Object?> get props => [isLoading, errorMessage, isKeyboardVisible];
}

// New state for pending email confirmation
class AuthPendingEmailConfirmationState extends AuthState {
  final String email;
  final String? successMessage;
  final String? errorMessage;
  final bool isLoading;
  final String otpType;

  const AuthPendingEmailConfirmationState({
    required this.email,
    this.successMessage,
    this.errorMessage,
    this.isLoading = false,
    this.otpType = 'signup',
  });

  AuthPendingEmailConfirmationState copyWith({
    String? email,
    String? successMessage,
    String? errorMessage,
    bool? isLoading,
    String? otpType,
  }) {
    return AuthPendingEmailConfirmationState(
      email: email ?? this.email,
      successMessage: successMessage,
      errorMessage: errorMessage,
      isLoading: isLoading ?? this.isLoading,
      otpType: otpType ?? this.otpType,
    );
  }

  @override
  List<Object?> get props => [
    email,
    successMessage,
    errorMessage,
    isLoading,
    otpType,
  ];
}

// State for verification method choice screen (email vs phone)
class AuthVerificationMethodChoiceState extends AuthState {
  final String email;
  final String? successMessage;
  final String? errorMessage;
  final bool isLoading;

  const AuthVerificationMethodChoiceState({
    required this.email,
    this.successMessage,
    this.errorMessage,
    this.isLoading = false,
  });

  AuthVerificationMethodChoiceState copyWith({
    String? email,
    String? successMessage,
    String? errorMessage,
    bool? isLoading,
  }) {
    return AuthVerificationMethodChoiceState(
      email: email ?? this.email,
      successMessage: successMessage,
      errorMessage: errorMessage,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [email, successMessage, errorMessage, isLoading];
}

// State for pending phone/SMS verification
class AuthPendingPhoneVerificationState extends AuthState {
  final String phoneNumber;
  final String email;
  final String? successMessage;
  final String? errorMessage;
  final bool isLoading;

  const AuthPendingPhoneVerificationState({
    required this.phoneNumber,
    required this.email,
    this.successMessage,
    this.errorMessage,
    this.isLoading = false,
  });

  AuthPendingPhoneVerificationState copyWith({
    String? phoneNumber,
    String? email,
    String? successMessage,
    String? errorMessage,
    bool? isLoading,
  }) {
    return AuthPendingPhoneVerificationState(
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      successMessage: successMessage,
      errorMessage: errorMessage,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [
    phoneNumber,
    email,
    successMessage,
    errorMessage,
    isLoading,
  ];
}

class AuthLoadingState extends AuthState {}

class AuthSuccessState extends AuthState {
  final String message;

  const AuthSuccessState(this.message);

  @override
  List<Object> get props => [message];
}

class AuthErrorState extends AuthState {
  final String message;

  const AuthErrorState(this.message);

  @override
  List<Object> get props => [message];
}

// In your auth_state.dart file

class AuthAuthenticatedState extends AuthState {
  final String userId;
  final String email;
  final Map<String, dynamic>? userData;
  final UserProfile? userProfile;
  final List<Organization> managedOrganizations;
  final bool shouldNavigateToHome; // Used for OAuth successful login handling

  const AuthAuthenticatedState({
    required this.userId,
    required this.email,
    this.userData,
    this.userProfile,
    this.managedOrganizations = const [],
    this.shouldNavigateToHome = false, // Default to false
  });

  AuthAuthenticatedState copyWith({
    String? userId,
    String? email,
    Map<String, dynamic>? userData,
    UserProfile? userProfile,
    List<Organization>? managedOrganizations,
    bool? shouldNavigateToHome,
  }) {
    return AuthAuthenticatedState(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      userData: userData ?? this.userData,
      userProfile: userProfile ?? this.userProfile,
      managedOrganizations: managedOrganizations ?? this.managedOrganizations,
      shouldNavigateToHome: shouldNavigateToHome ?? this.shouldNavigateToHome,
    );
  }

  @override
  List<Object?> get props => [
    userId,
    email,
    userData,
    userProfile,
    managedOrganizations,
    shouldNavigateToHome,
  ];
}

// Terminal state for a reset-password link that could not be used (expired,
// already used, tampered, or belonging to a different account than the one
// signed in). Routes to an explicit error screen instead of the reset form.
class AuthPasswordResetLinkErrorState extends AuthState {
  final String message;

  const AuthPasswordResetLinkErrorState(this.message);

  @override
  List<Object> get props => [message];
}

// State for when password reset link is processed and ready for navigation
class AuthPasswordResetState extends AuthState {
  final String resetToken;
  final Uri uri;
  final String? successMessage;
  final String? errorMessage;
  final bool isLoading;

  const AuthPasswordResetState({
    required this.resetToken,
    required this.uri,
    this.successMessage,
    this.errorMessage,
    this.isLoading = false,
  });

  AuthPasswordResetState copyWith({
    String? resetToken,
    Uri? uri,
    String? successMessage,
    String? errorMessage,
    bool? isLoading,
  }) {
    return AuthPasswordResetState(
      resetToken: resetToken ?? this.resetToken,
      uri: uri ?? this.uri,
      successMessage: successMessage ?? this.successMessage,
      errorMessage: errorMessage ?? this.errorMessage,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [
    resetToken,
    uri,
    successMessage,
    errorMessage,
    isLoading,
  ];
}
