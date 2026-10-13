// verification_method_choice_screen.dart
// Screen for choosing between email and phone/SMS verification

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/flavour_config.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/models/feature_flags.dart';

class VerificationMethodChoiceScreen extends StatefulWidget {
  final String email;

  const VerificationMethodChoiceScreen({
    super.key,
    required this.email,
  });

  @override
  State<VerificationMethodChoiceScreen> createState() =>
      _VerificationMethodChoiceScreenState();
}

class _VerificationMethodChoiceScreenState
    extends State<VerificationMethodChoiceScreen> {
  FeatureFlags _featureFlags = FeatureFlags();

  @override
  void initState() {
    super.initState();
    _loadFeatureFlags();
  }

  Future<void> _loadFeatureFlags() async {
    try {
      final result = await context.read<ApiRepository>().getFeatureFlags();
      if (result.isSuccess && result.data != null && mounted) {
        setState(() {
          _featureFlags = result.data!;
        });
      }
    } catch (e) {
      // Flags stay at safe defaults (smsVerificationEnabled = false).
    }
  }

  void _chooseEmail() {
    context.read<AuthBloc>().add(
      ChooseEmailVerificationEvent(email: widget.email),
    );
  }

  void _showPhoneBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return BlocProvider.value(
          value: context.read<AuthBloc>(),
          child: _PhoneInputBottomSheet(email: widget.email),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cardGreyBackground,
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthVerificationMethodChoiceState &&
              state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        builder: (context, state) {
          final isLoading = state is AuthVerificationMethodChoiceState &&
              state.isLoading;
          final successMessage =
              state is AuthVerificationMethodChoiceState
                  ? state.successMessage
                  : null;

          return SafeArea(
            child: Padding(
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

                  const SizedBox(height: 24),

                  // Icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.accentPrimary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified_user_outlined,
                      size: 40,
                      color: AppTheme.accentPrimary,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Title
                  const Text(
                    'Verify Your Account',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.black,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Choose how you want to verify your account',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 12),

                  // Success message
                  if (successMessage != null)
                    Container(
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

                  const SizedBox(height: 8),

                  // Email verification option
                  _buildOptionCard(
                    icon: Icons.mail_outline,
                    title: 'Verify via Email',
                    subtitle: 'Send a code to ${widget.email}',
                    onTap: isLoading ? null : _chooseEmail,
                  ),

                  const SizedBox(height: 16),

                  // Phone verification option - opens bottom sheet
                  _buildOptionCard(
                    icon: Icons.sms_outlined,
                    title: 'Verify via Text Message',
                    subtitle: 'Receive a text message with a verification code',
                    onTap:
                        isLoading || !_featureFlags.smsVerificationEnabled
                            ? null
                            : _showPhoneBottomSheet,
                    comingSoon: !_featureFlags.smsVerificationEnabled,
                  ),

                  const Spacer(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool isSelected = false,
    bool comingSoon = false,
  }) {
    final iconColor =
        comingSoon ? Colors.grey[400]! : AppTheme.accentPrimary;
    final iconBg =
        comingSoon ? Colors.grey[100]! : AppTheme.accentPrimary.withOpacity(0.1);

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: comingSoon ? 0.55 : 1.0,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accentPrimary.withOpacity(0.05)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppTheme.accentPrimary : Colors.grey[300]!,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 24, color: iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: comingSoon ? Colors.grey[500] : AppTheme.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      comingSoon ? 'Coming soon' : subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              if (comingSoon)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Soon',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[500],
                    ),
                  ),
                )
              else
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.arrow_forward_ios,
                  color: isSelected ? AppTheme.accentPrimary : Colors.grey[400],
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet widget for phone number input.
/// Floats above the keyboard so the field is always visible.
class _PhoneInputBottomSheet extends StatefulWidget {
  final String email;

  const _PhoneInputBottomSheet({required this.email});

  @override
  State<_PhoneInputBottomSheet> createState() => _PhoneInputBottomSheetState();
}

class _PhoneInputBottomSheetState extends State<_PhoneInputBottomSheet> {
  late final TextEditingController _phoneController;
  final FocusNode _focusNode = FocusNode();

  // Production-only: tracks the raw 10 digits entered
  String _digits = '';

  bool get _isProd => FlavorConfig.isProduction;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    if (_isProd) {
      _phoneController.addListener(_onDigitsChanged);
    }
  }

  void _onDigitsChanged() {
    final raw = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final capped = raw.length > 10 ? raw.substring(0, 10) : raw;
    // Keep controller clean (digits only, max 10)
    if (_phoneController.text != capped) {
      _phoneController.value = TextEditingValue(
        text: capped,
        selection: TextSelection.collapsed(offset: capped.length),
      );
      return;
    }
    if (mounted && _digits != capped) {
      setState(() => _digits = capped);
    }
  }

  @override
  void dispose() {
    if (_isProd) {
      _phoneController.removeListener(_onDigitsChanged);
    }
    _focusNode.unfocus();
    _focusNode.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String get _phonePayload =>
      _isProd ? '+1$_digits' : _phoneController.text.trim();

  bool get _canSend => _isProd ? _digits.length == 10 : true;

  // ---------------------------------------------------------------------------
  // Production UI – PIN-code style digit input
  // ---------------------------------------------------------------------------

  Widget _buildProdPhoneInput(bool enabled) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => _focusNode.requestFocus() : null,
      child: Column(
        children: [
          // Hidden field that captures keyboard input
          SizedBox(
            height: 0,
            child: TextField(
              controller: _phoneController,
              focusNode: _focusNode,
              autofocus: true,
              enabled: enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 10,
              showCursor: false,
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
              ),
              style: const TextStyle(fontSize: 1),
            ),
          ),

          // Visual display: +1  (XXX) XXX-XXXX
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // +1 prefix chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.accentPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '+1',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accentPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildPunct('('),
              _buildDigitGroup(0, 3),
              _buildPunct(')'),
              const SizedBox(width: 5),
              _buildDigitGroup(3, 6),
              _buildPunct('-'),
              _buildDigitGroup(6, 10),
            ],
          ),

          const SizedBox(height: 10),
          Text(
            'Tap above to type your phone number',
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPunct(String char) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        char,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w400,
          color: Colors.grey[400],
        ),
      ),
    );
  }

  Widget _buildDigitGroup(int start, int end) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(end - start, (i) {
        final index = start + i;
        final hasDigit = index < _digits.length;
        final isActive = index == _digits.length;
        final digit = hasDigit ? _digits[index] : '';

        return Container(
          width: 22,
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive
                    ? AppTheme.accentPrimary
                    : (hasDigit ? AppTheme.black : Colors.grey[300]!),
                width: isActive ? 2.5 : 1.5,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            digit,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppTheme.black,
            ),
          ),
        );
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // QA UI – plain text field (original behaviour)
  // ---------------------------------------------------------------------------

  Widget _buildQaPhoneInput(bool enabled) {
    return TextField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      autofocus: true,
      enabled: enabled,
      decoration: InputDecoration(
        hintText: '+1 234 567 8900',
        labelText: 'Phone Number',
        prefixIcon: const Icon(
          Icons.phone,
          color: AppTheme.accentPrimary,
        ),
        filled: true,
        fillColor: Colors.grey[50],
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
      style: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 16,
      ),
    );
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        // Close the bottom sheet when we move to phone verification state
        if (state is AuthPendingPhoneVerificationState) {
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) {
        final isLoading =
            state is AuthVerificationMethodChoiceState && state.isLoading;
        final errorMessage = state is AuthVerificationMethodChoiceState
            ? state.errorMessage
            : null;

        return Padding(
          // Push the sheet above the keyboard
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.accentPrimary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.sms_outlined,
                        size: 20,
                        color: AppTheme.accentPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Enter Your Phone Number',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.black,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                Text(
                  _isProd
                      ? 'We\'ll send a verification code to your phone.'
                      : 'Enter your phone number in international format to receive a verification code.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),

                const SizedBox(height: 20),

                // Error message
                if (errorMessage != null)
                  Container(
                    width: double.infinity,
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
                    ),
                  ),

                // Phone input — differs by flavor
                _isProd
                    ? _buildProdPhoneInput(!isLoading)
                    : _buildQaPhoneInput(!isLoading),

                const SizedBox(height: 24),

                // Send code button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isLoading || !_canSend
                        ? null
                        : () {
                            context.read<AuthBloc>().add(
                              ChoosePhoneVerificationEvent(
                                email: widget.email,
                                phoneNumber: _phonePayload,
                              ),
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentPrimary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
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
                            'Send Code',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
