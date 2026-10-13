import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';

/// Explicit terminal screen for a reset-password link that could not be used:
/// expired, already used, tampered, or belonging to a different account than
/// the one signed in (DL-103/DL-104/DL-105/DL-106 — the error must be clear,
/// never a silent bounce to another screen).
class ResetLinkErrorScreen extends StatelessWidget {
  final String message;

  const ResetLinkErrorScreen({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cardGreyBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.link_off, size: 72, color: Colors.redAccent),
              const SizedBox(height: 24),
              Text(
                'Reset Link Problem',
                style: AppTheme.chatTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(fontSize: 16, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'You can request a new link from the login screen using '
                '"Forgot Password?".',
                style: TextStyle(fontSize: 14, color: Colors.black45),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: () => context.read<AuthBloc>().add(
                  PasswordResetFlowCompleteEvent(),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentPrimary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppTheme.actionButtonRadius,
                    ),
                  ),
                ),
                child: const Text(
                  'CONTINUE',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
