import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/profile/profile_onboarding_screen.dart';
import 'package:mvc_app/services/api_repository.dart';

class ProfileUtils {
  /// Checks if the user's profile needs completion
  /// Returns true if full_name contains '@privaterelay.appleid.com' (indicating it's an Apple private relay email)
  static bool needsProfileCompletion(UserProfile? profile) {
    if (profile == null) return false;

    final fullName = profile.fullName;
    if (fullName == null || fullName.isEmpty) return true;

    // Check if full_name contains '@privaterelay.appleid.com' (Apple private relay email)
    return fullName.contains('@privaterelay.appleid.com');
  }

  /// Shows the profile onboarding screen if the profile needs completion
  /// Returns true if onboarding was shown, false otherwise
  static Future<bool> showOnboardingIfNeeded(BuildContext context) async {
    final authState = context.read<AuthBloc>().state;

    if (authState is AuthAuthenticatedState) {
      final userProfile = authState.userProfile;

      if (needsProfileCompletion(userProfile)) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ProfileOnboardingScreen(),
          ),
        );
        return true;
      }
    }

    return false;
  }

  /// Checks if profile needs completion and shows a dialog if needed
  /// Returns true if the action should continue, false if blocked
  static Future<bool> checkProfileCompletionWithDialog(
    BuildContext context, {
    String? customMessage,
  }) async {
    final authState = context.read<AuthBloc>().state;

    if (authState is AuthAuthenticatedState) {
      final userProfile = authState.userProfile;

      if (needsProfileCompletion(userProfile)) {
        final shouldContinue = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Complete Your Profile'),
            content: Text(
              customMessage ??
                  'Please complete your profile setup before accessing this feature.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Later'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop(true);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfileOnboardingScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF28C6A),
                ),
                child: const Text(
                  'Complete Profile',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );

        return shouldContinue ?? false;
      }
    }

    return true; // Profile is complete, continue with action
  }

  /// Shows a bottom sheet with profile completion prompt
  /// Returns true if user chose to complete profile, false otherwise
  static Future<bool> showProfileCompletionBottomSheet(
    BuildContext context, {
    String? message,
  }) async {
    // Force refresh the auth state to get the latest profile from database
    final authBloc = context.read<AuthBloc>();
    authBloc.add(CheckAuthStatusEvent());

    // Wait for the auth state to update
    await authBloc.stream.firstWhere(
      (state) => state is AuthAuthenticatedState || state is AuthWelcomeState,
      orElse: () => authBloc.state,
    ).timeout(
      const Duration(seconds: 2),
      onTimeout: () => authBloc.state,
    );

    // Check if profile actually needs completion after refresh
    final authState = authBloc.state;
    if (authState is AuthAuthenticatedState) {
      final userProfile = authState.userProfile;

      // If profile is complete, just return true without showing the modal
      if (!needsProfileCompletion(userProfile)) {
        return true;
      }
    }

    final result = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => PopScope(
        canPop: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_outline,
                size: 60,
                color: Color(0xFFF28C6A),
              ),
              const SizedBox(height: 20),
              const Text(
                'Complete Your Profile',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message ??
                    'To access channels and explore content, please complete your profile setup first.',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF28C6A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text(
                    'Complete Profile Now',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              // const SizedBox(height: 12),
              // TextButton(
              //   onPressed: () => Navigator.pop(context, false),
              //   child: Text(
              //     'Maybe Later',
              //     style: TextStyle(
              //       color: Colors.grey[600],
              //       fontSize: 16,
              //     ),
              //   ),
              // ),
            ],
          ),
        ),
      ),
    );

    if (result == true) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ProfileOnboardingScreen(),
        ),
      );
      return true;
    }

    return false;
  }
}
