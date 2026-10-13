// sms_otp_verification_screen.dart
// Screen for entering and verifying the 6-digit SMS OTP code

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';

class SmsOtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String email;

  const SmsOtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.email,
  });

  @override
  State<SmsOtpVerificationScreen> createState() =>
      _SmsOtpVerificationScreenState();
}

class _SmsOtpVerificationScreenState extends State<SmsOtpVerificationScreen>
    with TickerProviderStateMixin {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());

  // Hidden controller for iOS autofill
  final TextEditingController _hiddenController = TextEditingController();
  final FocusNode _hiddenFocusNode = FocusNode();

  late AnimationController _keyboardAnimationController;
  late AnimationController _bounceAnimationController;
  late Animation<double> _keyboardAnimation;
  late Animation<double> _bounceAnimation;

  bool _isKeyboardVisible = false;

  String get otpCode => _controllers.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();

    _keyboardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _bounceAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _keyboardAnimation = CurvedAnimation(
      parent: _keyboardAnimationController,
      curve: Curves.easeInOut,
    );

    _bounceAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(
        parent: _bounceAnimationController,
        curve: Curves.elasticOut,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupKeyboardListener();
    });

    _hiddenController.addListener(_onHiddenTextChanged);
  }

  void _setupKeyboardListener() {
    final mediaQuery = MediaQuery.of(context);
    final keyboardHeight = mediaQuery.viewInsets.bottom;

    if (keyboardHeight > 0 && !_isKeyboardVisible) {
      _isKeyboardVisible = true;
      _keyboardAnimationController.forward();
    } else if (keyboardHeight == 0 && _isKeyboardVisible) {
      _isKeyboardVisible = false;
      _keyboardAnimationController.reverse();
    }
  }

  void _onHiddenTextChanged() {
    final text = _hiddenController.text;
    if (text.length <= 6) {
      for (int i = 0; i < 6; i++) {
        _controllers[i].text = i < text.length ? text[i] : '';
      }

      if (text.length == 6) {
        _triggerBounceAnimation();
        _verifyOtp();
      }
    }
  }

  void _triggerBounceAnimation() {
    _bounceAnimationController.forward().then((_) {
      _bounceAnimationController.reverse();
    });
  }

  @override
  void dispose() {
    _keyboardAnimationController.dispose();
    _bounceAnimationController.dispose();
    _hiddenController.dispose();
    _hiddenFocusNode.dispose();

    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _onOtpChanged(String value, int index) {
    final currentOtp = otpCode;
    if (currentOtp != _hiddenController.text) {
      _hiddenController.text = currentOtp;
    }

    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    if (otpCode.length == 6) {
      _triggerBounceAnimation();
      _verifyOtp();
    }
  }

  void _verifyOtp() {
    if (otpCode.length == 6) {
      context.read<AuthBloc>().add(
        VerifyPhoneOtpEvent(
          phoneNumber: widget.phoneNumber,
          otpCode: otpCode,
          email: widget.email,
        ),
      );
    }
  }

  void _resendOtp() {
    context.read<AuthBloc>().add(
      ResendPhoneOtpEvent(phoneNumber: widget.phoneNumber),
    );
  }

  String _formatPhone(String phone) {
    if (phone.startsWith('+1') && phone.length == 12) {
      final d = phone.substring(2);
      return '+1 (${d.substring(0, 3)}) ${d.substring(3, 6)}-${d.substring(6)}';
    }
    return phone;
  }

  void _clearOtp() {
    for (var controller in _controllers) {
      controller.clear();
    }
    _hiddenController.clear();
    _focusNodes[0].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupKeyboardListener();
    });

    return Scaffold(
      backgroundColor: AppTheme.cardGreyBackground,
      resizeToAvoidBottomInset: false,
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthSuccessState) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        builder: (context, state) {
          final isLoading =
              state is AuthPendingPhoneVerificationState && state.isLoading;
          final errorMessage = state is AuthPendingPhoneVerificationState
              ? state.errorMessage
              : null;
          final successMessage = state is AuthPendingPhoneVerificationState
              ? state.successMessage
              : null;

          return Stack(
            children: [
              // Hidden text field for iOS autofill
              Positioned(
                left: -1000,
                top: -1000,
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: TextField(
                    controller: _hiddenController,
                    focusNode: _hiddenFocusNode,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
              ),

              // Main content
              SafeArea(
                child: AnimatedBuilder(
                  animation: _keyboardAnimation,
                  builder: (context, child) {
                    return Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Back button
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              onPressed: () {
                                context.read<AuthBloc>().add(GoBackEvent());
                              },
                              icon: const Icon(
                                Icons.arrow_back,
                                color: AppTheme.black,
                              ),
                            ),
                          ),

                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: _isKeyboardVisible ? 20 : 40,
                            curve: Curves.easeInOut,
                          ),

                          // SMS icon
                          AnimatedScale(
                            scale: _isKeyboardVisible ? 0.8 : 1.0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color:
                                    AppTheme.accentPrimary.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.sms_outlined,
                                size: 40,
                                color: AppTheme.accentPrimary,
                              ),
                            ),
                          ),

                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: _isKeyboardVisible ? 16 : 32,
                            curve: Curves.easeInOut,
                          ),

                          // Title
                          AnimatedOpacity(
                            opacity: _isKeyboardVisible ? 0.8 : 1.0,
                            duration: const Duration(milliseconds: 300),
                            child: Text(
                              'Verify Your Phone',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: _isKeyboardVisible ? 24 : 28,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.black,
                              ),
                            ),
                          ),

                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: _isKeyboardVisible ? 6 : 12,
                            curve: Curves.easeInOut,
                          ),

                          // Subtitle
                          AnimatedOpacity(
                            opacity: _isKeyboardVisible ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 300),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              height: _isKeyboardVisible ? 0 : null,
                              child: !_isKeyboardVisible
                                  ? Column(
                                      children: [
                                        Text(
                                          'We\'ve sent a 6-digit verification code to',
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.grey[600],
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatPhone(widget.phoneNumber),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.accentPrimary,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),

                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: _isKeyboardVisible ? 20 : 40,
                            curve: Curves.easeInOut,
                          ),

                          // Success message
                          if (successMessage != null)
                            AnimatedSlide(
                              offset: const Offset(0, 0),
                              duration: const Duration(milliseconds: 300),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.green.withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  successMessage,
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),

                          // Error message
                          if (errorMessage != null)
                            AnimatedSlide(
                              offset: const Offset(0, 0),
                              duration: const Duration(milliseconds: 300),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.red.withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  errorMessage,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),

                          // OTP input fields
                          AnimatedBuilder(
                            animation: _bounceAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _bounceAnimation.value,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: List.generate(6, (index) {
                                    return SizedBox(
                                      width: 45,
                                      height: 55,
                                      child: TextField(
                                        controller: _controllers[index],
                                        focusNode: _focusNodes[index],
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        maxLength: 1,
                                        enabled: !isLoading,
                                        autofillHints: const [
                                          AutofillHints.oneTimeCode,
                                        ],
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        decoration: InputDecoration(
                                          counterText: '',
                                          filled: true,
                                          fillColor: Colors.grey[100],
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                              color: Colors.grey[300]!,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                              color: Colors.grey[300]!,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: const BorderSide(
                                              color: AppTheme.accentPrimary,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        onChanged: (value) =>
                                            _onOtpChanged(value, index),
                                        onTap: () {
                                          _hiddenFocusNode.requestFocus();
                                          Future.delayed(
                                            const Duration(milliseconds: 100),
                                            () {
                                              _focusNodes[index]
                                                  .requestFocus();
                                            },
                                          );
                                        },
                                      ),
                                    );
                                  }),
                                ),
                              );
                            },
                          ),

                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: _isKeyboardVisible ? 20 : 40,
                            curve: Curves.easeInOut,
                          ),

                          // Verify button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: isLoading || otpCode.length != 6
                                  ? null
                                  : _verifyOtp,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accentPrimary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Verify Code',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),

                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: _isKeyboardVisible ? 12 : 24,
                            curve: Curves.easeInOut,
                          ),

                          // Clear OTP button
                          AnimatedOpacity(
                            opacity: _isKeyboardVisible ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 300),
                            child: TextButton(
                              onPressed: isLoading ? null : _clearOtp,
                              child: Text(
                                'Clear Code',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),

                          const Spacer(),

                          // Resend code section
                          AnimatedOpacity(
                            opacity: _isKeyboardVisible ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 300),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              height: _isKeyboardVisible ? 0 : null,
                              child: !_isKeyboardVisible
                                  ? Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Didn\'t receive the SMS? ',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 14,
                                          ),
                                        ),
                                        TextButton(
                                          onPressed:
                                              isLoading ? null : _resendOtp,
                                          child: const Text(
                                            'Resend',
                                            style: TextStyle(
                                              color: AppTheme.accentPrimary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),

                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: _isKeyboardVisible ? 0 : 20,
                            curve: Curves.easeInOut,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
