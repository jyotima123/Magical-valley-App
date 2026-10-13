// ignore_for_file: unused_import

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/main.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/auth_pending_otp_service.dart';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthApiException;

class ResetPasswordScreen extends StatefulWidget {
  final String resetToken;
  final Uri uri;

  const ResetPasswordScreen({
    super.key,
    required this.resetToken,
    required this.uri,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final FocusNode _newPasswordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _newPasswordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  String _validatePasswords() {
    if (_newPasswordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      return 'Please fill in all fields';
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      return 'Passwords do not match';
    }

    if (_newPasswordController.text.length < 6) {
      return 'Password must be at least 6 characters';
    }

    // Additional password strength validation
    if (!_newPasswordController.text.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }

    if (!_newPasswordController.text.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter';
    }

    if (!_newPasswordController.text.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }

    return ''; // Valid password
  }

  Future<void> _resetPassword() async {
    // Validate passwords first
    final validationError = _validatePasswords();
    if (validationError.isNotEmpty) {
      _showErrorDialog(validationError);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // The recovery token was already verified — and consumed — when the
      // deep link was processed (see _onPasswordResetLinkReceived). The
      // recovery session it created is all that's needed to set the new
      // password here.
      if (SupabaseApiService.auth.currentSession == null) {
        _showErrorDialog(
          'Your password reset session has expired. Please request a new '
          'reset link.',
        );
        return;
      }

      await SupabaseApiService.instance.setNewPassword(
        _newPasswordController.text,
      );

      // Invalidate the recovery session so it cannot be reused and so the
      // user is not silently left signed-in as the password-reset target
      // account (BUG-007).
      try {
        await SupabaseApiService.instance.signOut();
      } catch (_) {}
      await AuthPendingOtpService.instance.clearRecoveryPending();

      _showSuccessDialog();
    } on AuthApiException catch (e) {
      _showErrorDialog(e.message);
    } catch (e) {
      print('Error during password reset: $e');
      _showErrorDialog(
        'An unexpected error occurred. Please check your internet connection and try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorDialog(String message) {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.error,
      animType: AnimType.scale,
      title: 'Error',
      desc: message,
      btnOkOnPress: () {},
      btnOkColor: Colors.red,
      btnOkText: 'OK',
      dismissOnTouchOutside: true,
      headerAnimationLoop: false,
      showCloseIcon: true,
    ).show();
  }

  void _showSuccessDialog() {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.success,
      animType: AnimType.scale,
      title: 'Success!',
      desc: 'Your password has been updated successfully! Please sign in with your new password.',
      btnOkOnPress: () {
        // The recovery session was already signed out in _resetPassword.
        // PasswordResetFlowCompleteEvent clears the link-flow guard and
        // re-routes (no session left -> welcome/login screen).
        context.read<AuthBloc>().add(PasswordResetFlowCompleteEvent());
      },
      btnOkColor: AppTheme.accentPrimary,
      btnOkText: 'Sign In',
      dismissOnTouchOutside: false,
      dismissOnBackKeyPress: false,
      headerAnimationLoop: false,
      showCloseIcon: false,
    ).show();
  }

  void _showConfirmationDialog() {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.question,
      animType: AnimType.scale,
      title: 'Confirm Password Reset',
      desc: 'Are you sure you want to update your password?',
      btnOkOnPress: () {
        _resetPassword();
      },
      btnCancelOnPress: () {},
      btnOkText: 'Yes, Update',
      btnCancelText: 'Cancel',
      btnOkColor: AppTheme.accentPrimary,
      btnCancelColor: Colors.grey,
      dismissOnTouchOutside: true,
      headerAnimationLoop: false,
      showCloseIcon: true,
    ).show();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cardGreyBackground,
      appBar: AppBar(
        title: Container(),
        backgroundColor: AppTheme.cardGreyBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            // GoBackEvent discards the recovery session and returns to the
            // welcome screen (see AuthBloc._onGoBack).
            context.read<AuthBloc>().add(GoBackEvent());
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            Text(
              'Create New Password',
              style: AppTheme.chatTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter your new password below',
              style: TextStyle(fontSize: 16, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Password requirements info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Password Requirements:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• At least 6 characters\n• One uppercase letter\n• One lowercase letter\n• One number',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPasswordField(
                    'New Password',
                    'Enter new password',
                    _newPasswordController,
                    _newPasswordFocusNode,
                    _confirmPasswordFocusNode,
                    isFirstField: true,
                  ),
                  const SizedBox(height: 24),
                  _buildPasswordField(
                    'Confirm Password',
                    'Confirm new password',
                    _confirmPasswordController,
                    _confirmPasswordFocusNode,
                    null,
                    isFirstField: false,
                    onSubmitted: _isLoading ? null : _showConfirmationDialog,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: _isLoading ? null : _showConfirmationDialog,
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
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'UPDATE PASSWORD',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordField(
    String label,
    String hint,
    TextEditingController controller,
    FocusNode focusNode,
    FocusNode? nextFocusNode,
    {
    required bool isFirstField,
    VoidCallback? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.black,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: true,
          textInputAction: isFirstField ? TextInputAction.next : TextInputAction.done,
          onSubmitted: isFirstField
              ? (_) {
                  nextFocusNode?.requestFocus();
                }
              : (_) {
                  if (onSubmitted != null && !_isLoading) {
                    onSubmitted();
                  }
                },
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400]),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppTheme.accentPrimary,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
