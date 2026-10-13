// lib/modules/auth/auth_bloc.dart
// Authentication functions

import 'dart:async';

import 'package:email_validator/email_validator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/services/api/api_service_factory.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart'
    show SupabaseApiService;
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/auth_pending_otp_service.dart';
import 'package:mvc_app/modules/auth/chain/handlers/flow_guard_handler.dart';
import 'package:mvc_app/modules/auth/restoration/auth_restoration_chain.dart';
import 'package:mvc_app/modules/auth/restoration/restoration_context.dart';
import 'package:mvc_app/modules/auth/restoration/steps/interrupted_recovery_restoration_step.dart';
import 'package:mvc_app/modules/auth/restoration/steps/unauthenticated_restoration_step.dart';
import 'package:mvc_app/modules/auth/restoration/steps/verified_session_restoration_step.dart';
import 'package:mvc_app/modules/auth/restoration/steps/pending_email_otp_restoration_step.dart';
import 'package:mvc_app/modules/auth/restoration/steps/pending_phone_otp_restoration_step.dart';
import 'package:mvc_app/modules/auth/restoration/steps/verification_choice_restoration_step.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final ApiRepository _apiRepository;
  final AuthRestorationChain _restorationChain = AuthRestorationChain([
    InterruptedRecoveryRestorationStep(),
    UnauthenticatedRestorationStep(),
    VerifiedSessionRestorationStep(),
    PendingEmailOtpRestorationStep(),
    PendingPhoneOtpRestorationStep(),
    VerificationChoiceRestorationStep(),
  ]);

  AuthBloc({ApiRepository? apiRepository})
    : _apiRepository =
          apiRepository ??
          ApiRepository(
            ApiServiceFactory.createApiService(ApiProvider.supabase),
          ),
      super(const AuthWelcomeState()) {
    on<ShowLoginFormEvent>(_onShowLoginForm);
    on<ShowSignupFormEvent>(_onShowSignupForm);
    on<GoBackEvent>(_onGoBack);
    on<LoginSubmittedEvent>(_onLoginSubmitted);
    on<SignupSubmittedEvent>(_onSignupSubmitted);
    on<SocialLoginEvent>(_onSocialLogin);
    on<KeyboardVisibilityChangedEvent>(_onKeyboardVisibilityChanged);
    on<LogoutEvent>(_onLogout);
    on<CheckAuthStatusEvent>(_onCheckAuthStatus);
    on<ResendOtpEvent>(_onResendOtp);
    on<VerifyOtpEvent>(_onVerifyOtp);
    on<ShowOtpVerificationEvent>(_onShowOtpVerification);
    on<PasswordResetLinkReceivedEvent>(_onPasswordResetLinkReceived);
    on<PasswordResetFlowCompleteEvent>(_onPasswordResetFlowComplete);
    on<SessionLinkReceivedEvent>(_onSessionLinkReceived);
    on<LoadManagedOrganizationsEvent>(_onLoadManagedOrganizations);
    on<AppleWebLoginEvent>(_onAppleWebLogin);
    on<NavigateToHomeEvent>(_onNavigateToHome);
    on<ShowWelcomeEvent>(_onShowWelcome);
    on<ChooseEmailVerificationEvent>(_onChooseEmailVerification);
    on<ChoosePhoneVerificationEvent>(_onChoosePhoneVerification);
    on<VerifyPhoneOtpEvent>(_onVerifyPhoneOtp);
    on<ResendPhoneOtpEvent>(_onResendPhoneOtp);
    on<OAuthLoginSuccessEvent>((event, emit) async {
      try {
        print(
          '🎉 Processing OAuth login success for: ${event.session.user.email}',
        );

        // Store user session or perform any additional setup
        // The user is already authenticated in Supabase at this point

        emit(
          AuthSuccessState(
            'Successfully signed in with Apple ID',
            // user: event.session.user,
          ),
        );
      } catch (e) {
        print('❌ Error processing OAuth success: $e');
        emit(AuthErrorState('Failed to complete OAuth login: ${e.toString()}'));
      }
    });
  }

  @override
  void onChange(Change<AuthState> change) {
    super.onChange(change);
    // Safety net: the reset-link flow guard must never outlive the flow's
    // states, or ambient Supabase signals (OAuth sign-in, logout, ...) would
    // be swallowed forever.
    final next = change.nextState;
    if (FlowGuardHandler.linkFlowActive &&
        next is! AuthLoadingState &&
        next is! AuthPasswordResetState &&
        next is! AuthPasswordResetLinkErrorState) {
      FlowGuardHandler.linkFlowActive = false;
    }
  }

  void _onShowLoginForm(ShowLoginFormEvent event, Emitter<AuthState> emit) {
    print("Showing Login Form");
    emit(const AuthLoginFormState());
  }

  void _onShowSignupForm(ShowSignupFormEvent event, Emitter<AuthState> emit) {
    emit(const AuthSignupFormState());
  }

  Future<void> _onGoBack(GoBackEvent event, Emitter<AuthState> emit) async {
    // Handle going back from different states
    if (state is AuthPasswordResetState) {
      // Backing out of the reset screen: the recovery session created when
      // the link was verified must be discarded so it can't be reused to
      // change the password later (BUG-007 / DL-108).
      try {
        await _apiRepository.logout();
      } catch (_) {}
      await AuthPendingOtpService.instance.clearRecoveryPending();
      emit(const AuthWelcomeState());
    } else if (state is AuthPendingPhoneVerificationState) {
      final phoneState = state as AuthPendingPhoneVerificationState;
      emit(AuthVerificationMethodChoiceState(email: phoneState.email));
    } else if (state is AuthVerificationMethodChoiceState) {
      emit(const AuthWelcomeState());
    } else if (state is AuthPendingEmailConfirmationState) {
      emit(const AuthWelcomeState());
    } else {
      emit(const AuthWelcomeState());
    }
  }

  void _onShowOtpVerification(
    ShowOtpVerificationEvent event,
    Emitter<AuthState> emit,
  ) {
    emit(
      AuthPendingEmailConfirmationState(
        email: event.email,
        otpType: 'signup',
        successMessage:
            'Account created! Please check your email for verification code.',
      ),
    );
  }

  // New handler for loading managed organizations
  Future<void> _onLoadManagedOrganizations(
    LoadManagedOrganizationsEvent event,
    Emitter<AuthState> emit,
  ) async {
    // Only proceed if we're in an authenticated state
    if (state is! AuthAuthenticatedState) {
      print('Cannot load managed organizations: User not authenticated');
      return;
    }

    final currentState = state as AuthAuthenticatedState;

    try {
      print('Loading managed organizations for user: ${event.userId}');

      // Call the API to get managed organizations
      final result = await _apiRepository.getUserManagedOrganizations(
        event.userId,
      );

      if (result.isSuccess) {
        print(
          'Successfully loaded ${result.data!.length} managed organizations',
        );

        // Update the state with the loaded organizations
        emit(currentState.copyWith(managedOrganizations: result.data!));
      } else {
        print('Failed to load managed organizations: ${result.error}');

        // You can choose to emit an error state or just keep the current state
        // For now, we'll keep the current state but with an empty list
        emit(currentState.copyWith(managedOrganizations: []));
      }
    } catch (e) {
      print('Error loading managed organizations: $e');

      // Keep current state but ensure managedOrganizations is empty
      emit(currentState.copyWith(managedOrganizations: []));
    }
  }

  Future<void> _onPasswordResetLinkReceived(
    PasswordResetLinkReceivedEvent event,
    Emitter<AuthState> emit,
  ) async {
    print('🔄 AuthBloc: Handling password reset link...');

    final token = event.uri.queryParameters['token'];
    if (token == null || token.isEmpty) {
      print('❌ No token found in password reset link');
      emit(
        const AuthPasswordResetLinkErrorState(
          'Invalid password reset link. Please request a new one.',
        ),
      );
      return;
    }

    // Guard the whole flow: verifying the token and signing out a mismatched
    // user fire ambient Supabase events (passwordRecovery/signedOut) that
    // would otherwise re-route the app mid-flow (the BUG-008/BUG-009
    // Welcome-screen bounce). Cleared by onChange when the flow's states end.
    FlowGuardHandler.linkFlowActive = true;

    try {
      emit(AuthLoadingState());

      // Who is using the app right now? Null when nobody is signed in.
      final previousUser = await _apiRepository.getCurrentUser();
      final previousUserId = previousUser?.userId;

      // Mark the recovery flow as in progress BEFORE verifying: verification
      // creates a real session for the link's account, and if the app is
      // killed mid-flow that session must not be restored as a login (DL-108).
      await AuthPendingOtpService.instance.saveRecoveryPending();

      // Verify the single-use token NOW instead of at submit time, so
      // expired, already-used, or tampered links fail with an explicit error
      // before any reset screen is shown (BUG-008/DL-104, BUG-009/DL-105,
      // DL-106). On failure the previous user's session is left untouched.
      final result = await SupabaseApiService.instance.verifyRecoveryToken(
        token,
      );

      if (!result.isSuccess) {
        print('❌ Recovery token rejected: ${result.message}');
        await AuthPendingOtpService.instance.clearRecoveryPending();
        emit(
          AuthPasswordResetLinkErrorState(
            result.message ??
                'This password reset link is invalid, has expired, or was '
                    'already used. Please request a new one.',
          ),
        );
        return;
      }

      // The link belongs to a different account than the one signed in:
      // refuse to continue and kill the recovery session so the link owner's
      // password cannot be changed from this device (BUG-007 / DL-103).
      if (previousUserId != null &&
          previousUserId.isNotEmpty &&
          previousUserId != result.userId) {
        print('🚫 Reset link account mismatch — aborting reset flow');
        await _apiRepository.logout();
        await AuthPendingOtpService.instance.clearRecoveryPending();
        emit(
          const AuthPasswordResetLinkErrorState(
            'This password reset link belongs to a different account. For '
            'security you have been signed out and no password was changed. '
            'Please request a reset link for your own account.',
          ),
        );
        return;
      }

      print('✅ Recovery token verified for ${result.email}');
      emit(
        AuthPasswordResetState(
          resetToken: token,
          uri: event.uri,
          successMessage:
              'Password reset link verified. You can now reset your password.',
        ),
      );
    } catch (e) {
      print('🚨 Error handling password reset link: $e');
      await AuthPendingOtpService.instance.clearRecoveryPending();
      emit(
        const AuthPasswordResetLinkErrorState(
          'An error occurred while processing the password reset link. '
          'Please request a new one.',
        ),
      );
    }
  }

  /// The reset flow is fully finished (success dialog confirmed or the
  /// link-error screen dismissed): drop the guard and route based on
  /// whatever session is — or isn't — left.
  Future<void> _onPasswordResetFlowComplete(
    PasswordResetFlowCompleteEvent event,
    Emitter<AuthState> emit,
  ) async {
    FlowGuardHandler.linkFlowActive = false;
    await AuthPendingOtpService.instance.clearRecoveryPending();
    add(CheckAuthStatusEvent());
  }

  Future<void> _onSessionLinkReceived(
    SessionLinkReceivedEvent event,
    Emitter<AuthState> emit,
  ) async {
    print('🔗 AuthBloc: Handling session link (${event.uri.host})...');

    // A different link flow is taking over — drop any abandoned reset-link
    // guard so the CheckAuthStatusEvent below isn't skipped, and sign out a
    // lingering recovery session so it can't outlive its flow.
    FlowGuardHandler.linkFlowActive = false;
    if (await AuthPendingOtpService.instance.isRecoveryPending()) {
      try {
        await _apiRepository.logout();
      } catch (_) {}
      await AuthPendingOtpService.instance.clearRecoveryPending();
    }

    try {
      // Extract the code from the URI
      final code = event.uri.queryParameters['code'];

      if (code == null || code.isEmpty) {
        print('❌ No code found in session link');
        emit(AuthErrorState('Invalid link. Please try again.'));
        return;
      }

      // Show loading state
      emit(AuthLoadingState());

      // Exchange the code for a session using the API repository
      var result = await SupabaseApiService.instance.exchangeCodeForSession(
        event.uri.toString(),
      );

      // Maybe trying again will work?
      if (!result.isSuccess) {
        result = await SupabaseApiService.instance.exchangeCodeForSession(
          event.uri.toString(),
        );
      }

      if (result.isSuccess) {
        print('✅ Session link exchange successful');
        // Let CheckAuthStatusEvent (via AuthRestorationChain) decide where to
        // route the user based on the resulting session.
        add(CheckAuthStatusEvent());
      } else {
        print('❌ Failed to exchange session link: ${result.error}');
        emit(
          AuthErrorState(
            result.error ?? 'Failed to confirm. Please try again.',
          ),
        );
      }
    } catch (e) {
      print('🚨 Error handling session link: $e');
      emit(AuthErrorState('An error occurred while confirming your session.'));
    }
  }

  Future<void> _onLoginSubmitted(
    LoginSubmittedEvent event,
    Emitter<AuthState> emit,
  ) async {
    if (state is AuthLoginFormState) {
      final currentState = state as AuthLoginFormState;
      emit(currentState.copyWith(isLoading: true, errorMessage: null));

      try {
        // Validate input
        if (event.email.isEmpty || event.password.isEmpty) {
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: 'Please fill in all fields',
            ),
          );
          return;
        }

        if (!_isValidEmail(event.email)) {
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: 'Please enter a valid email',
            ),
          );
          return;
        }

        if (event.password.length < 6) {
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: 'Password must be at least 6 characters',
            ),
          );
          return;
        }

        // Call API
        final result = await _apiRepository.login(event.email, event.password);

        if (result.isSuccess) {
          emit(const AuthSuccessState('Login successful!'));
        } else if (result.isPendingEmailConfirmation) {
          // User exists but email not confirmed - redirect to email confirmation
          emit(
            AuthPendingEmailConfirmationState(
              email: result.email ?? event.email,
              errorMessage:
                  result.message ??
                  'Please confirm your email address to continue',
            ),
          );
        } else {
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: result.message ?? 'Login failed',
            ),
          );
        }
      } catch (e) {
        emit(
          currentState.copyWith(
            isLoading: false,
            errorMessage: 'An unexpected error occurred. Please try again.',
          ),
        );
      }
    }
  }

  Future<void> _onSignupSubmitted(
    SignupSubmittedEvent event,
    Emitter<AuthState> emit,
  ) async {
    if (state is AuthSignupFormState) {
      final currentState = state as AuthSignupFormState;
      emit(currentState.copyWith(isLoading: true, errorMessage: null));

      try {
        // Validate input
        if (event.fullName.isEmpty ||
            event.email.isEmpty ||
            event.password.isEmpty ||
            event.confirmPassword.isEmpty) {
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: 'Please fill in all fields',
            ),
          );
          return;
        }

        if (!_isValidEmail(event.email)) {
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: 'Please enter a valid email',
            ),
          );
          return;
        }

        if (event.password.length < 6) {
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: 'Password must be at least 6 characters',
            ),
          );
          return;
        }

        if (event.password != event.confirmPassword) {
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: 'Passwords do not match',
            ),
          );
          return;
        }

        // Call API
        final result = await _apiRepository.register(
          event.email,
          event.password,
          event.fullName,
        );

        if (result.isPendingEmailConfirmation) {
          // Navigate to verification method choice screen
          emit(
            AuthVerificationMethodChoiceState(
              email: event.email,
              successMessage:
                  'Account created! Choose how you want to verify your account.',
            ),
          );
        } else {
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: result.message ?? 'Account creation failed',
            ),
          );
        }
      } catch (e) {
        emit(
          currentState.copyWith(
            isLoading: false,
            errorMessage: 'An unexpected error occurred. Please try again.',
          ),
        );
      }
    }
  }

  Future<void> _onVerifyOtp(
    VerifyOtpEvent event,
    Emitter<AuthState> emit,
  ) async {
    if (state is AuthPendingEmailConfirmationState) {
      final currentState = state as AuthPendingEmailConfirmationState;
      emit(
        currentState.copyWith(
          isLoading: true,
          errorMessage: null,
          successMessage: null,
        ),
      );

      try {
        // Validate input
        if (event.otpCode.isEmpty) {
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: 'Please enter the verification code',
            ),
          );
          return;
        }

        if (event.otpCode.length != 6) {
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: 'Verification code must be 6 digits',
            ),
          );
          return;
        }

        // Call API to verify OTP
        final result = await _apiRepository.verifyOtp(
          event.email,
          event.otpCode,
          event.otpType,
        );

        if (result.isSuccess) {
          // Mark the user as verified before navigating home so that any
          // concurrent CheckAuthStatusEvent sees verified_at and doesn't
          // bounce the user back to the choice screen.
          try {
            final userId = result.userId;
            if (userId != null && userId.isNotEmpty) {
              await _apiRepository.updateUserProfile(userId, {
                'verified_at': DateTime.now().toUtc().toIso8601String(),
              });
            }
          } catch (e) {
            print('Warning: Failed to set verified_at: $e');
          }

          // OTP flow completed — no longer needed on restart
          await AuthPendingOtpService.instance.clear();

          emit(const AuthSuccessState('Email verified successfully!'));
          add(
            NavigateToHomeEvent(successMessage: 'Email verified successfully!'),
          );
        } else {
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: result.error ?? 'Invalid verification code',
            ),
          );
        }
      } catch (e) {
        emit(
          currentState.copyWith(
            isLoading: false,
            errorMessage: 'An unexpected error occurred. Please try again.',
          ),
        );
      }
    }
  }

  Future<void> _onSocialLogin(
    SocialLoginEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoadingState());

    try {
      // TODO: The QA is different, we need to get the flavour!
      final result = await _apiRepository.socialLogin(event.provider);

      if (result.isSuccess) {
        // After successful social login, ensure user profile exists
        await _ensureUserProfileExists(result.userData);

        print('✅ Social login successful with profile creation');
        emit(AuthSuccessState('${event.provider} login successful!'));
      } else {
        emit(
          AuthErrorState(
            result.error ?? '${event.provider} login failed. Please try again.',
          ),
        );
      }
    } catch (e) {
      print('🚨 Social login error: $e');
      emit(AuthErrorState('${event.provider} login failed. Please try again.'));
    }
  }

  // New helper method to ensure user profile exists
  Future<void> _ensureUserProfileExists(Map<String, dynamic>? userData) async {
    if (userData == null) return;

    try {
      final userId = userData['id'] as String?;
      final email = userData['email'] as String?;
      final fullName =
          userData['user_metadata']?['full_name'] as String? ??
          userData['user_metadata']?['name'] as String? ??
          email?.split('@').first ??
          'User';

      if (userId == null || email == null) {
        print('⚠️ Missing required user data for profile creation');
        return;
      }

      // Check if profile already exists
      final existingProfile = await _apiRepository.getUserProfile(userId);

      if (!existingProfile.isSuccess) {
        // Profile doesn't exist, create it
        print('📝 Creating user profile for Apple login user');

        // Generate username from email or fallback
        String username = email.split('@').first;

        // You'll need to add this method to your ApiRepository
        final createResult = await _apiRepository.createUserProfile(
          userId: userId,
          username: username,
          fullName: fullName,
          email: email,
          role: 'regular',
        );

        if (createResult.isSuccess) {
          print('✅ User profile created successfully');
        } else {
          print('❌ Failed to create user profile: ${createResult.error}');
        }
      } else {
        print('✅ User profile already exists');
      }
    } catch (e) {
      print('🚨 Error ensuring user profile exists: $e');
    }
  }

  void _onShowWelcome(ShowWelcomeEvent event, Emitter<AuthState> emit) {
    emit(const AuthWelcomeState());
  }

  void _onAppleWebLogin(
    AppleWebLoginEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoadingState());

    try {
      print('🍎 Initiating web-based Apple login...');

      // Use the existing social login method but force web-based flow
      final result = await _apiRepository.socialLogin('apple');

      if (result.isSuccess) {
        // After successful social login, ensure user profile exists
        await _ensureUserProfileExists(result.userData);

        print('✅ Web Apple login successful with profile creation');
        emit(AuthSuccessState('Apple login successful!'));
      } else {
        emit(
          AuthErrorState(
            result.error ?? 'Apple login failed. Please try again.',
          ),
        );
      }
    } catch (e) {
      print('🚨 Web Apple login error: $e');
      emit(AuthErrorState('Apple login failed. Please try again.'));
    }
  }

  Future<void> _onLogout(LogoutEvent event, Emitter<AuthState> emit) async {
    try {
      await _apiRepository.logout();
      emit(const AuthWelcomeState());
    } catch (e) {
      emit(AuthErrorState('Logout failed. Please try again.'));
    }
  }

  Future<void> _onCheckAuthStatus(
    CheckAuthStatusEvent event,
    Emitter<AuthState> emit,
  ) async {
    // A reset-password link is being processed (or its screen is showing):
    // re-running restoration now would bounce the user off the flow — e.g.
    // the appStart check racing a cold-start deep link (BUG-008/BUG-009
    // "1st attempt goes to Welcome"). The flow ends with an explicit
    // PasswordResetFlowCompleteEvent, which re-runs this check.
    if (FlowGuardHandler.linkFlowActive) {
      print('⏭️ Skipping CheckAuthStatus: reset-link flow in progress');
      return;
    }

    try {
      final ctx = await RestorationContext.build(_apiRepository);
      emit(await _restorationChain.resolve(ctx));
    } catch (e) {
      print('Error checking auth status: $e');
      emit(const AuthWelcomeState());
    }
  }

  Future<void> _onResendOtp(
    ResendOtpEvent event,
    Emitter<AuthState> emit,
  ) async {
    if (state is AuthPendingEmailConfirmationState) {
      final currentState = state as AuthPendingEmailConfirmationState;
      emit(
        currentState.copyWith(
          isLoading: true,
          errorMessage: null,
          successMessage: null,
        ),
      );

      try {
        // Validate email
        if (event.email.isEmpty || !_isValidEmail(event.email)) {
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: 'Please provide a valid email address',
            ),
          );
          return;
        }

        // Call API to resend OTP
        final result = await _apiRepository.resendOtp(
          event.email,
          event.otpType,
        );

        if (result.isSuccess) {
          // Re-save so a fresh app restart knows the user is still in OTP flow
          // (covers BUG-003: close right after Resend → no longer goes to login)
          await AuthPendingOtpService.instance.save(event.email, event.otpType);
          emit(
            currentState.copyWith(
              isLoading: false,
              successMessage:
                  'Verification code sent successfully to ${event.email}',
            ),
          );
        } else {
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage:
                  result.error ??
                  'Failed to resend verification code. Please try again.',
            ),
          );
        }
      } catch (e) {
        emit(
          currentState.copyWith(
            isLoading: false,
            errorMessage:
                'An unexpected error occurred while resending verification code. Please try again.',
          ),
        );
      }
    } else {
      // Handle resend OTP from other states (like from login screen for testing)
      emit(AuthLoadingState());

      try {
        // Validate email
        if (event.email.isEmpty || !_isValidEmail(event.email)) {
          emit(AuthErrorState('Please provide a valid email address'));
          return;
        }

        // Call API to resend OTP
        final result = await _apiRepository.resendOtp(
          event.email,
          event.otpType,
        );

        if (result.isSuccess) {
          emit(
            AuthSuccessState(
              'Verification code sent successfully to ${event.email}',
            ),
          );
        } else {
          emit(
            AuthErrorState(
              result.error ??
                  'Failed to resend verification code. Please try again.',
            ),
          );
        }
      } catch (e) {
        emit(
          AuthErrorState(
            'An unexpected error occurred while resending verification code. Please try again.',
          ),
        );
      }
    }
  }

  void _onKeyboardVisibilityChanged(
    KeyboardVisibilityChangedEvent event,
    Emitter<AuthState> emit,
  ) {
    if (state is AuthLoginFormState) {
      final currentState = state as AuthLoginFormState;
      emit(currentState.copyWith(isKeyboardVisible: event.isVisible));
    } else if (state is AuthSignupFormState) {
      final currentState = state as AuthSignupFormState;
      emit(currentState.copyWith(isKeyboardVisible: event.isVisible));
    } else if (state is AuthWelcomeState) {
      emit(AuthWelcomeState(isKeyboardVisible: event.isVisible));
    }
  }

  Future<AuthAuthenticatedState?> refreshUserProfileAfterLogin() async {
    if (state is AuthAuthenticatedState) {
      final currentState = state as AuthAuthenticatedState;

      try {
        // Fetch the latest user profile
        final profileResult = await _apiRepository.getUserProfile(
          currentState.userId,
        );

        if (profileResult.isSuccess) {
          // Return the updated state instead of emitting directly
          print('✅ Refreshed user profile after login');
          return currentState.copyWith(userProfile: profileResult.data);
        }
      } catch (e) {
        print('⚠️ Warning: Failed to refresh user profile: $e');
      }
    }
    return null;
  }

  bool _isValidEmail(String email) => EmailValidator.validate(email);

  String _formatPhone(String phone) {
    if (phone.startsWith('+1') && phone.length == 12) {
      final d = phone.substring(2);
      return '+1 (${d.substring(0, 3)}) ${d.substring(3, 6)}-${d.substring(6)}';
    }
    return phone;
  }

  UserProfile? getUserProfile() {
    if (state is AuthAuthenticatedState) {
      return (state as AuthAuthenticatedState).userProfile;
    }
    // In case the user is not authenticated
    return null;
  }

  // TODO why on earth this doesnt work?
  Future<UserProfile?> getUserProfileAsync() async {
    if (state is AuthAuthenticatedState) {
      final authState = state as AuthAuthenticatedState;

      // If profile exists, return it
      if (authState.userProfile != null) {
        return authState.userProfile;
      }

      // If profile is null, try to fetch it
      try {
        final profileResult = await _apiRepository.getUserProfile(
          authState.userId,
        );
        if (profileResult.isSuccess) {
          return profileResult.data;
        }
      } catch (e) {
        print('Error fetching user profile: $e');
      }
    }
    return null;
  }

  Future<void> _onChooseEmailVerification(
    ChooseEmailVerificationEvent event,
    Emitter<AuthState> emit,
  ) async {
    if (state is AuthVerificationMethodChoiceState) {
      final currentState = state as AuthVerificationMethodChoiceState;
      emit(currentState.copyWith(isLoading: true, errorMessage: null));

      final result = await _apiRepository.sendEmailOtp(event.email);

      if (result.isSuccess) {
        await AuthPendingOtpService.instance.save(event.email, 'email');
        emit(
          AuthPendingEmailConfirmationState(
            email: event.email,
            otpType: 'email',
            successMessage: 'Verification code sent to ${event.email}',
          ),
        );
      } else {
        emit(
          currentState.copyWith(
            isLoading: false,
            errorMessage: result.error ?? result.message ?? 'Failed to send verification email',
          ),
        );
      }
    }
  }

  Future<void> _onChoosePhoneVerification(
    ChoosePhoneVerificationEvent event,
    Emitter<AuthState> emit,
  ) async {
    if (state is AuthVerificationMethodChoiceState) {
      final currentState = state as AuthVerificationMethodChoiceState;

      // Normalise to E.164: keep the leading '+' then strip every non-digit.
      final raw = event.phoneNumber.trim();
      final phone =
          raw.startsWith('+')
              ? '+${raw.substring(1).replaceAll(RegExp(r'[^\d]'), '')}'
              : raw.replaceAll(RegExp(r'[^\d]'), '');

      print('[SMS] sendPhoneOtp — raw input: "$raw"  normalised: "$phone"  length: ${phone.length}');

      if (phone.isEmpty || !phone.startsWith('+') || phone.length < 8) {
        print('[SMS] sendPhoneOtp — validation failed: empty=${phone.isEmpty}  startsWithPlus=${phone.startsWith('+')}  length=${phone.length}');
        emit(
          currentState.copyWith(
            isLoading: false,
            errorMessage:
                'Please enter a valid phone number in international format (e.g. +1234567890)',
          ),
        );
        return;
      }

      emit(currentState.copyWith(isLoading: true, errorMessage: null));

      try {
        print('[SMS] sendPhoneOtp — calling API with phone: "$phone"');
        final result = await _apiRepository.sendPhoneOtp(phone);
        print('[SMS] sendPhoneOtp — result: isSuccess=${result.isSuccess}  message="${result.message}"  error="${result.error}"');

        if (result.isSuccess) {
          print('[SMS] sendPhoneOtp — success, transitioning to AuthPendingPhoneVerificationState');
          // Persist so the SMS OTP screen survives app kill (BUG-004 / BUG-005).
          await AuthPendingOtpService.instance.savePhone(phone, event.email);
          emit(
            AuthPendingPhoneVerificationState(
              phoneNumber: phone,
              email: event.email,
              successMessage: 'Text message code sent to ${_formatPhone(phone)}',
            ),
          );
        } else {
          print('[SMS] sendPhoneOtp — failed: ${result.message}');
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: result.message ?? 'Failed to send SMS code',
            ),
          );
        }
      } catch (e) {
        print('[SMS] sendPhoneOtp — exception: $e');
        emit(
          currentState.copyWith(
            isLoading: false,
            errorMessage: 'An unexpected error occurred. Please try again.',
          ),
        );
      }
    }
  }

  Future<void> _onVerifyPhoneOtp(
    VerifyPhoneOtpEvent event,
    Emitter<AuthState> emit,
  ) async {
    if (state is AuthPendingPhoneVerificationState) {
      final currentState = state as AuthPendingPhoneVerificationState;

      // Guard against duplicate submissions (e.g. button tapped multiple times)
      if (currentState.isLoading) return;

      emit(
        currentState.copyWith(
          isLoading: true,
          errorMessage: null,
          successMessage: null,
        ),
      );

      try {
        if (event.otpCode.isEmpty) {
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: 'Please enter the verification code',
            ),
          );
          return;
        }

        if (event.otpCode.length != 6) {
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: 'Verification code must be 6 digits',
            ),
          );
          return;
        }

        print('[SMS] verifyPhoneOtp — calling API with phone: "${event.phoneNumber}"  otpCode length: ${event.otpCode.length}');
        final result = await _apiRepository.verifyPhoneOtp(
          event.phoneNumber,
          event.otpCode,
        );
        print('[SMS] verifyPhoneOtp — result: isSuccess=${result.isSuccess}  userId="${result.userId}"  message="${result.message}"  error="${result.error}"');

        if (result.isSuccess) {
          // Clear persisted SMS OTP state now that verification succeeded.
          await AuthPendingOtpService.instance.clearPhone();

          // Save phone number and mark user as verified in a single update.
          try {
            final userId = result.userId;
            print('[SMS] verifyPhoneOtp — updating profile: userId="$userId"  phone="${event.phoneNumber}"');
            if (userId != null && userId.isNotEmpty) {
              await _apiRepository.updateUserProfile(userId, {
                'phone_number': event.phoneNumber,
                'verified_at': DateTime.now().toUtc().toIso8601String(),
              });
              print('[SMS] verifyPhoneOtp — profile updated successfully');
            } else {
              print('[SMS] verifyPhoneOtp — skipped profile update: userId is null or empty');
            }
          } catch (e) {
            print('[SMS] verifyPhoneOtp — warning: failed to save phone/verified_at: $e');
          }

          emit(const AuthSuccessState('Phone verified successfully!'));
          add(
            NavigateToHomeEvent(
              successMessage: 'Phone verified successfully!',
            ),
          );
        } else {
          print('[SMS] verifyPhoneOtp — failed: ${result.message}');
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage: result.message ?? 'Invalid verification code',
            ),
          );
        }
      } catch (e) {
        print('[SMS] verifyPhoneOtp — exception: $e');
        emit(
          currentState.copyWith(
            isLoading: false,
            errorMessage: 'An unexpected error occurred. Please try again.',
          ),
        );
      }
    }
  }

  Future<void> _onResendPhoneOtp(
    ResendPhoneOtpEvent event,
    Emitter<AuthState> emit,
  ) async {
    if (state is AuthPendingPhoneVerificationState) {
      final currentState = state as AuthPendingPhoneVerificationState;
      emit(
        currentState.copyWith(
          isLoading: true,
          errorMessage: null,
          successMessage: null,
        ),
      );

      try {
        print('[SMS] resendPhoneOtp — calling API with phone: "${event.phoneNumber}"');
        final result = await _apiRepository.resendPhoneOtp(event.phoneNumber);
        print('[SMS] resendPhoneOtp — result: isSuccess=${result.isSuccess}  message="${result.message}"  error="${result.error}"');

        if (result.isSuccess) {
          emit(
            currentState.copyWith(
              isLoading: false,
              successMessage:
                  'Verification code resent to ${event.phoneNumber}',
            ),
          );
        } else {
          print('[SMS] resendPhoneOtp — failed: ${result.message}');
          emit(
            currentState.copyWith(
              isLoading: false,
              errorMessage:
                  result.message ??
                  'Failed to resend SMS code. Please try again.',
            ),
          );
        }
      } catch (e) {
        print('[SMS] resendPhoneOtp — exception: $e');
        emit(
          currentState.copyWith(
            isLoading: false,
            errorMessage: 'An unexpected error occurred. Please try again.',
          ),
        );
      }
    }
  }

  Future<void> _onNavigateToHome(
    NavigateToHomeEvent event,
    Emitter<AuthState> emit,
  ) async {
    try {
      print('🏠 Processing navigation to home screen...');

      // Check if user is authenticated first
      final user = await _apiRepository.getCurrentUser();

      if (user != null && user.isSuccess) {
        // Fetch user profile including role
        UserProfile? userProfile;
        try {
          final profileResult = await _apiRepository.getUserProfile(
            user.userId!,
          );
          if (profileResult.isSuccess) {
            userProfile = profileResult.data;
          }
        } catch (e) {
          print('Error fetching user profile: $e');
        }

        print(
          '✅ Successfully authenticated, emitting AuthAuthenticatedState with shouldNavigateToHome: true',
        );

        // Emit authenticated state which will trigger navigation - ONLY ONCE
        emit(
          AuthAuthenticatedState(
            userId: user.userId ?? '',
            email: user.email ?? '',
            userData: user.userData,
            userProfile: userProfile,
            managedOrganizations: const [],
            shouldNavigateToHome: true, // This is the key flag
          ),
        );
      } else {
        // User not authenticated, redirect to welcome
        print('❌ User not authenticated, redirecting to welcome');
        emit(const AuthWelcomeState());
      }
    } catch (e) {
      print('🚨 Error during home navigation: $e');
      emit(AuthErrorState('Failed to authenticate user: ${e.toString()}'));
    }
  }
}
