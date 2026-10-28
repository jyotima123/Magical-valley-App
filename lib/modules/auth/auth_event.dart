// auth_event.dart
// Login and SignUp event notifiers

import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class ShowLoginFormEvent extends AuthEvent {}

class ShowSignupFormEvent extends AuthEvent {}

class GoBackEvent extends AuthEvent {}

class LoginSubmittedEvent extends AuthEvent {
  final String email;
  final String password;

  const LoginSubmittedEvent({required this.email, required this.password});

  @override
  List<Object> get props => [email, password];
}

class SignupSubmittedEvent extends AuthEvent {
  final String fullName;
  final String email;
  final String password;
  final String confirmPassword;

  const SignupSubmittedEvent({
    required this.fullName,
    required this.email,
    required this.password,
    required this.confirmPassword,
  });

  @override
  List<Object> get props => [fullName, email, password, confirmPassword];
}

class SocialLoginEvent extends AuthEvent {
  final String provider;

  const SocialLoginEvent(this.provider);

  @override
  List<Object> get props => [provider];
}

class AppleWebLoginEvent extends AuthEvent {
  const AppleWebLoginEvent();

  @override
  List<Object> get props => [];
}

class KeyboardVisibilityChangedEvent extends AuthEvent {
  final bool isVisible;

  const KeyboardVisibilityChangedEvent(this.isVisible);

  @override
  List<Object> get props => [isVisible];
}

class LogoutEvent extends AuthEvent {}

class CheckAuthStatusEvent extends AuthEvent {}

class ResendOtpEvent extends AuthEvent {
  final String email;
  final String otpType;

  const ResendOtpEvent({required this.email, required this.otpType});

  @override
  List<Object> get props => [email, otpType];
}

class ShowOnboardingEvent extends AuthEvent {}

class ShowWelcomeEvent extends AuthEvent {}

// New event for OTP verification
class VerifyOtpEvent extends AuthEvent {
  final String email;
  final String otpCode;
  final String otpType;

  const VerifyOtpEvent({
    required this.email,
    required this.otpCode,
    required this.otpType,
  });

  @override
  List<Object> get props => [email, otpCode, otpType];
}

// Event to show OTP verification screen
class ShowOtpVerificationEvent extends AuthEvent {
  final String email;

  const ShowOtpVerificationEvent({required this.email});

  @override
  List<Object> get props => [email];
}

// Event for when a password reset link is received
class PasswordResetLinkReceivedEvent extends AuthEvent {
  final Uri uri;

  const PasswordResetLinkReceivedEvent({required this.uri});

  @override
  List<Object?> get props => [uri];
}

// Dispatched when the password-reset flow is fully finished — success dialog
// confirmed or link-error screen dismissed. Clears the link-flow guard and
// re-routes based on whatever session is (or isn't) left.
class PasswordResetFlowCompleteEvent extends AuthEvent {}

// Event for a deep link carrying a PKCE code to exchange for a session
// (email-confirmation magic link or OAuth login-callback).
class SessionLinkReceivedEvent extends AuthEvent {
  final Uri uri;

  const SessionLinkReceivedEvent({required this.uri});

  @override
  List<Object?> get props => [uri];
}

// New event for loading managed organizations
class LoadManagedOrganizationsEvent extends AuthEvent {
  final String userId;

  const LoadManagedOrganizationsEvent({required this.userId});

  @override
  List<Object> get props => [userId];
}

class OAuthLoginSuccessEvent extends AuthEvent {
  final Session session;

  const OAuthLoginSuccessEvent({required this.session});

  @override
  List<Object?> get props => [session];
}

class NavigateToHomeEvent extends AuthEvent {
  final String? successMessage;

  const NavigateToHomeEvent({this.successMessage});

  @override
  List<Object?> get props => [successMessage];
}

// Phone/SMS verification events
class ChooseEmailVerificationEvent extends AuthEvent {
  final String email;

  const ChooseEmailVerificationEvent({required this.email});

  @override
  List<Object> get props => [email];
}

class ChoosePhoneVerificationEvent extends AuthEvent {
  final String email;
  final String phoneNumber;

  const ChoosePhoneVerificationEvent({
    required this.email,
    required this.phoneNumber,
  });

  @override
  List<Object> get props => [email, phoneNumber];
}

class VerifyPhoneOtpEvent extends AuthEvent {
  final String phoneNumber;
  final String otpCode;
  final String email;

  const VerifyPhoneOtpEvent({
    required this.phoneNumber,
    required this.otpCode,
    required this.email,
  });

  @override
  List<Object> get props => [phoneNumber, otpCode, email];
}

class ResendPhoneOtpEvent extends AuthEvent {
  final String phoneNumber;

  const ResendPhoneOtpEvent({required this.phoneNumber});

  @override
  List<Object> get props => [phoneNumber];
}
