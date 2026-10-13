// app_router.dart - Handles all authentication UI and animations
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mvc_app/widgets/app_dialog.dart';

import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/flavour_config.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/last_login_method_service.dart';
import 'package:mvc_app/services/models/feature_flags.dart';
import 'package:flutter/foundation.dart';
import 'package:mvc_app/testability/screen_state.dart';
import 'package:mvc_app/testability/screen_state_registry.dart';

class AuthFlowScreen extends StatefulWidget {
  const AuthFlowScreen({super.key});

  @override
  State<AuthFlowScreen> createState() => _AuthFlowScreenState();
}

class _AuthFlowScreenState extends State<AuthFlowScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _blackSectionAnimation;
  late Animation<double> _formOpacity;
  late Animation<double> _backButtonOpacity;
  late Animation<double> _logoOpacity;
  late Animation<double> _authButtonsOpacity;

  // Form controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Focus nodes
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _nameFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();

  bool _showPasswordRequirements = false;
  final _passwordRequirementsKey = GlobalKey();
  int? _focusedFieldIndex; // 0=name, 1=email, 2=password, 3=confirmPassword
  // Highest field index the user has focused so far. Never decrements.
  // Used to decide which fields to reveal: all up to _maxVisitedIndex+1 are shown.
  int _maxVisitedIndex = -1;

  // Tracks which password requirements have been satisfied long enough to dismiss
  final Set<int> _dismissedRequirements = {};
  final Map<int, Timer?> _requirementTimers = {0: null, 1: null, 2: null, 3: null};

  // Scroll controller for the sign-up form — allows us to manually reset to
  // offset 0 on every focus change so collapsed labels above never leave the
  // viewport and remain tappable.
  final ScrollController _signupScrollController = ScrollController();
  bool _showEmailLoginForm = false;
  String? _lastUsedLoginMethod;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Feature flags - default: only email enabled until flags are loaded
  FeatureFlags _featureFlags = FeatureFlags();

  // Testability: GlobalKeys so the server can resolve on-screen bounds.
  // Only meaningful in debug/profile builds.
  final _loginBtnKey = GlobalKey();
  final _emailLoginBtnKey = GlobalKey();
  final _emailFieldKey = GlobalKey();
  final _passwordFieldKey = GlobalKey();
  final _loginSubmitKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _setupFocusListeners();
    _loadLastLoginMethod();
    _loadFeatureFlags();
  }

  Future<void> _loadFeatureFlags() async {
    try {
      final apiRepository = context.read<ApiRepository>();
      final result = await apiRepository.getFeatureFlags();
      if (result.isSuccess && result.data != null && mounted) {
        setState(() {
          _featureFlags = result.data!;
        });
      }
    } catch (e) {
      print('Failed to load feature flags: $e');
    }
  }

  Future<void> _loadLastLoginMethod() async {
    final lastMethod = await LastLoginMethodService.instance
        .getLastLoginMethod();
    if (mounted) {
      setState(() {
        _lastUsedLoginMethod = lastMethod;
      });
    }
  }

  Future<void> _saveLastLoginMethod(String method) async {
    await LastLoginMethodService.instance.saveLastLoginMethod(method);
    if (mounted) {
      setState(() {
        _lastUsedLoginMethod = method.toLowerCase();
      });
    }
  }

  @override
  void dispose() {
    for (final timer in _requirementTimers.values) {
      timer?.cancel();
    }
    _signupScrollController.dispose();
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _confirmPasswordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _nameFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _blackSectionAnimation = Tween<double>(begin: 0.4, end: 0.7).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOutCubic,
      ),
    );

    _formOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeInOutCubic),
      ),
    );

    _backButtonOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.7, 1.0, curve: Curves.easeInOutCubic),
      ),
    );

    _logoOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInCirc),
      ),
    );

    _authButtonsOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeInCirc),
      ),
    );
  }

  void _setupFocusListeners() {
    _emailFocusNode.addListener(_handleFocusChange);
    _passwordFocusNode.addListener(_handlePasswordFocusChange);
    _nameFocusNode.addListener(_handleFocusChange);
    _confirmPasswordFocusNode.addListener(_handleFocusChange);

    _nameFocusNode.addListener(_updateFocusedField);
    _emailFocusNode.addListener(_updateFocusedField);
    _passwordFocusNode.addListener(_updateFocusedField);
    _confirmPasswordFocusNode.addListener(_updateFocusedField);
  }

  void _updateFocusedField() {
    final index = _nameFocusNode.hasFocus
        ? 0
        : _emailFocusNode.hasFocus
        ? 1
        : _passwordFocusNode.hasFocus
        ? 2
        : _confirmPasswordFocusNode.hasFocus
        ? 3
        : null;
    if (index != _focusedFieldIndex) {
      setState(() {
        _focusedFieldIndex = index;
        if (index != null && index > _maxVisitedIndex) {
          _maxVisitedIndex = index;
        }
      });
    }
  }

  bool _isFieldInputVisible(int index) {
    // Before any field has been focused, show everything.
    if (_maxVisitedIndex < 0) return true;
    // Show all fields the user has already visited, plus the next unvisited one.
    // Fields beyond that are hidden until the user advances to them.
    return index <= _maxVisitedIndex + 1;
  }

  void _onPasswordChanged() {
    final password = _passwordController.text;
    final satisfied = [
      password.length >= 6,
      password.contains(RegExp(r'[A-Z]')),
      password.contains(RegExp(r'[a-z]')),
      password.contains(RegExp(r'[0-9]')),
    ];

    bool needsRebuild = false;
    for (int i = 0; i < satisfied.length; i++) {
      if (satisfied[i] && !_dismissedRequirements.contains(i)) {
        // Satisfied — start a timer to dismiss after 0.5 s (if not already pending)
        _requirementTimers[i] ??= Timer(const Duration(milliseconds: 500), () {
          if (mounted) setState(() => _dismissedRequirements.add(i));
          _requirementTimers[i] = null;
        });
      } else if (!satisfied[i]) {
        // No longer satisfied — cancel pending timer and restore if already dismissed
        _requirementTimers[i]?.cancel();
        _requirementTimers[i] = null;
        if (_dismissedRequirements.remove(i)) needsRebuild = true;
      }
    }
    if (needsRebuild) setState(() {});
  }

  void _handlePasswordFocusChange() {
    setState(() {
      _showPasswordRequirements = _passwordFocusNode.hasFocus;
    });
    _handleFocusChange();

  }

  void _handleFocusChange() {
    final isKeyboardVisible =
        _emailFocusNode.hasFocus ||
        _passwordFocusNode.hasFocus ||
        _nameFocusNode.hasFocus ||
        _confirmPasswordFocusNode.hasFocus;

    context.read<AuthBloc>().add(
      KeyboardVisibilityChangedEvent(isKeyboardVisible),
    );
  }

  bool _getKeyboardVisibility(AuthState state) {
    if (state is AuthLoginFormState) return state.isKeyboardVisible;
    if (state is AuthSignupFormState) return state.isKeyboardVisible;
    if (state is AuthWelcomeState) return state.isKeyboardVisible;
    return false;
  }

  void _clearControllers() {
    _emailController.clear();
    _passwordController.clear();
    _nameController.clear();
    _confirmPasswordController.clear();
    _maxVisitedIndex = -1;
    _focusedFieldIndex = null;
    _dismissedRequirements.clear();
    _showPasswordRequirements = false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final hasFocus = _nameFocusNode.hasFocus ||
            _emailFocusNode.hasFocus ||
            _passwordFocusNode.hasFocus ||
            _confirmPasswordFocusNode.hasFocus;
        if (hasFocus) {
          FocusScope.of(context).unfocus();
        } else {
          context.read<AuthBloc>().add(GoBackEvent());
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.cardGreyBackground,
        resizeToAvoidBottomInset: false,
        body: BlocConsumer<AuthBloc, AuthState>(
        listener: _handleStateChanges,
        builder: (context, state) {
          return AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              final isKeyboardVisible = _getKeyboardVisibility(state);
              final blackSectionHeight = isKeyboardVisible
                  ? MediaQuery.of(context).size.height * 0.95
                  : MediaQuery.of(context).size.height *
                        _blackSectionAnimation.value;

              return Stack(
                children: [
                  _buildTopSection(blackSectionHeight),
                  _buildBottomSection(state, blackSectionHeight),
                  if (_shouldShowBackButton(state, isKeyboardVisible))
                    _buildBackButton(state),
                ],
              );
            },
          );
        },
      ),
    ),
    );
  }

  // ── Testability (debug/profile only) ──────────────────────────────────────

  ElementBounds? _getBounds(GlobalKey key) {
    if (kReleaseMode) return null;
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    final pos = box.localToGlobal(Offset.zero);
    return ElementBounds(
      x1: pos.dx,
      y1: pos.dy,
      x2: pos.dx + box.size.width,
      y2: pos.dy + box.size.height,
    );
  }

  /// Schedule a screen-state report for the next frame so that layout
  /// has completed and GlobalKey bounds are accurate.
  void _scheduleScreenReport() {
    if (kReleaseMode) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AuthBloc>().state;
      _doReportScreenState(state);
    });
  }

  void _doReportScreenState(AuthState state) {
    if (kReleaseMode) return;
    final elements = <ScreenElement>[];

    if (state is AuthWelcomeState) {
      elements.add(ScreenElement(
        id: 'login_btn',
        label: 'LOGIN',
        type: 'button',
        bounds: _getBounds(_loginBtnKey),
      ));
      ScreenStateRegistry.instance.update(ScreenState(
        screen: 'AuthFlowScreen',
        subState: 'welcome',
        elements: elements,
        metadata: const {},
      ));
    } else if (state is AuthLoginFormState) {
      if (!_showEmailLoginForm) {
        elements.add(ScreenElement(
          id: 'email_login_btn',
          label: 'CONTINUE WITH EMAIL',
          type: 'button',
          bounds: _getBounds(_emailLoginBtnKey),
          enabled: !state.isLoading,
        ));
      } else {
        elements.addAll([
          ScreenElement(
            id: 'email_field',
            label: 'EMAIL',
            type: 'text_field',
            bounds: _getBounds(_emailFieldKey),
          ),
          ScreenElement(
            id: 'password_field',
            label: 'PASSWORD',
            type: 'text_field',
            bounds: _getBounds(_passwordFieldKey),
          ),
          ScreenElement(
            id: 'login_submit_btn',
            label: 'LOGIN',
            type: 'button',
            bounds: _getBounds(_loginSubmitKey),
            enabled: !state.isLoading,
          ),
        ]);
      }
      ScreenStateRegistry.instance.update(ScreenState(
        screen: 'AuthFlowScreen',
        subState: 'login_form',
        elements: elements,
        metadata: {
          'email_form_visible': _showEmailLoginForm,
          'is_loading': state.isLoading,
          'error_message': state.errorMessage,
        },
      ));
    } else if (state is AuthSignupFormState) {
      ScreenStateRegistry.instance.update(ScreenState(
        screen: 'AuthFlowScreen',
        subState: 'signup_form',
        elements: elements,
        metadata: {
          'is_loading': state.isLoading,
          'error_message': state.errorMessage,
        },
      ));
    }
  }

  // ── End testability ────────────────────────────────────────────────────────

  void _handleStateChanges(BuildContext context, AuthState state) {
    if (state is AuthLoginFormState || state is AuthSignupFormState) {
      _animationController.forward();
      if (state is AuthSignupFormState && _showEmailLoginForm) {
        setState(() => _showEmailLoginForm = false);
      }
    } else if (state is AuthWelcomeState) {
      _animationController.reverse();
      _clearControllers();
      if (_showEmailLoginForm) {
        setState(() => _showEmailLoginForm = false);
      }
    } else if (state is AuthErrorState) {
      _showErrorDialog(state.message);
    }
    // Don't handle success states here - let the router handle navigation
    _scheduleScreenReport();
  }

  void _showErrorDialog(String message) {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.error,
      animType: AnimType.scale,
      title: "Error",
      desc: message,
      btnOkOnPress: () => context.read<AuthBloc>().add(GoBackEvent()),
    ).show();
  }

  void _showValidationError(String message) {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.error,
      animType: AnimType.scale,
      title: "Error",
      desc: message,
      btnOkOnPress: () {},
    ).show();
  }

  bool _shouldShowBackButton(AuthState state, bool isKeyboardVisible) {
    return (state is AuthLoginFormState || state is AuthSignupFormState) &&
        !isKeyboardVisible;
  }

  Widget _buildTopSection(double blackSectionHeight) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: MediaQuery.of(context).size.height - blackSectionHeight,
      child: Opacity(
        opacity: _logoOpacity.value,
        child: Center(
          child: Image.asset(
            'assets/MainScreenLogo.png',
            width: 300,
            height: 300,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSection(AuthState state, double blackSectionHeight) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        constraints: BoxConstraints(
          minHeight: blackSectionHeight + (state is AuthSignupFormState ? 48 : 0),
        ),
        decoration: const BoxDecoration(
          color: AppTheme.black,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(42),
            topRight: Radius.circular(42),
          ),
        ),
        child: Stack(
          children: [
            SizedBox(height: 24),
            if (state is AuthWelcomeState || state is AuthErrorState)
              Opacity(
                opacity: state is AuthWelcomeState
                    ? _authButtonsOpacity.value
                    : 1.0,
                child: _buildAuthButtons(),
              ),
            if (state is AuthLoginFormState)
              Opacity(
                opacity: _formOpacity.value,
                child: _buildLoginForm(state),
              ),
            if (state is AuthSignupFormState)
              Opacity(
                opacity: _formOpacity.value,
                child: _buildSignupForm(state),
              ),
            if (_shouldShowLoading(state)) _buildLoadingOverlay(),
          ],
        ),
      ),
    );
  }

  bool _shouldShowLoading(AuthState state) {
    return state is AuthLoadingState ||
        (state is AuthLoginFormState && state.isLoading) ||
        (state is AuthSignupFormState && state.isLoading);
  }

  Widget _buildBackButton(AuthState state) {
    return Positioned(
      top: -40,
      left: -60,
      child: Opacity(
        opacity: _backButtonOpacity.value,
        child: GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
            context.read<AuthBloc>().add(GoBackEvent());
          },
          child: Container(
            padding: const EdgeInsets.all(80),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accentPrimary,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.arrow_back, color: Colors.white),
                    const Text(
                      " Back",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
                  child: Text(
                    state is AuthLoginFormState ? "Login" : "Sign Up",
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black54,
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentPrimary),
        ),
      ),
    );
  }

  Widget _buildAuthButtons() {
    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton(
              key: _loginBtnKey,
              onPressed: () =>
                  context.read<AuthBloc>().add(ShowLoginFormEvent()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentPrimary,
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AppTheme.actionButtonRadius,
                  ),
                ),
              ),
              child: const Text(
                'LOGIN',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton(
              onPressed: _showSignUpBottomSheet,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.black,
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                  side: const BorderSide(color: Colors.white, width: 2),
                ),
              ),
              child: const Text(
                'SIGN UP',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          // QA Quick Login Buttons
          if (FlavorConfig.supabaseEnvironment == 'qa') ...[
            const SizedBox(height: 40),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(child: Divider(color: Colors.white24)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'QA TEST USERS',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.white24)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildQALoginButtons(),
          ],
        ],
      ),
    );
  }

  Widget _buildQALoginButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildQALoginButton(
            label: 'Super Admin',
            email: 'qa-superadmin@test.local',
            icon: Icons.workspace_premium_outlined,
            color: Colors.purple,
          ),
          const SizedBox(height: 12),
          _buildQALoginButton(
            label: 'Regular User',
            email: 'qa-regular@test.local',
            icon: Icons.person_outline,
            color: Colors.grey,
          ),
          const SizedBox(height: 12),
          _buildQALoginButton(
            label: 'Admin (Art Test)',
            email: 'qa-admin-art@test.local',
            icon: Icons.manage_accounts_outlined,
            color: Colors.blue,
          ),
          const SizedBox(height: 12),
          _buildQALoginButton(
            label: 'Admin (QA Test)',
            email: 'qa-admin-qa@test.local',
            icon: Icons.manage_accounts_outlined,
            color: Colors.blue,
          ),

          const SizedBox(height: 32),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildQALoginButton({
    required String label,
    required String email,
    required IconData icon,
    required Color color,
  }) {
    return ElevatedButton(
      onPressed: () async {
        print('QA Login button pressed: $email');

        // Directly login using the API service
        try {
          final result = await SupabaseApiService.instance.signIn(
            email,
            'TestPass123!',
          );

          if (result.isSuccess && mounted) {
            print('QA Login successful for: $email');
            // Trigger auth check to update state
            context.read<AuthBloc>().add(CheckAuthStatusEvent());
          } else {
            print('QA Login failed for: $email - ${result.error}');
            if (mounted) {
              // The error message from API service is already user-friendly
              final errorMessage = result.error ?? 'Login failed. Please try again.';
              _showErrorDialog(errorMessage);
            }
          }
        } catch (e) {
          print('QA Login exception: $e');
          if (mounted) {
            // Check if it's a network error
            final errorString = e.toString().toLowerCase();
            if (errorString.contains('socketexception') ||
                errorString.contains('timeoutexception') ||
                errorString.contains('failed host lookup') ||
                errorString.contains('network')) {
              _showErrorDialog(
                'Unable to connect to the server. Please check your internet connection and try again.',
              );
            } else {
              _showErrorDialog(
                'Login failed: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}',
              );
            }
          }
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.2),
        foregroundColor: Colors.white,
        minimumSize: const Size(200, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color, width: 1.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showSignUpBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: const BoxDecoration(
            color: AppTheme.black,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(42),
              topRight: Radius.circular(42),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 30.0,
              vertical: 40.0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Header
                Text(
                  'Sign Up',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'choose how you want to join',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 40),

                // Social login buttons
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_featureFlags.loginAppleEnabled) ...[
                      _buildSocialActionButton(
                        iconPath: 'assets/social_icons/apple_logo.svg',
                        label: 'CONTINUE WITH APPLE',
                        onPressed: () async {
                          await _saveLastLoginMethod('apple');
                          try {
                            final result = await SupabaseApiService.instance
                                .initiateAppleLogin();
                            if (result.isSuccess && result.data != null) {
                              await launchUrl(Uri.parse(result.data!));
                            } else {
                              // Show the error message from the API service
                              final errorMessage = result.error ??
                                  'Failed to start Apple ID signup. Please try again.';
                              _showErrorDialog(errorMessage);
                            }
                          } catch (e) {
                            // Handle network and other errors
                            final errorString = e.toString().toLowerCase();
                            if (errorString.contains('socketexception') ||
                                errorString.contains('timeoutexception') ||
                                errorString.contains('failed host lookup') ||
                                errorString.contains('network')) {
                              _showErrorDialog(
                                'Unable to connect to the server. Please check your internet connection and try again.',
                              );
                            } else {
                              _showErrorDialog(
                                'Apple signup failed: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}',
                              );
                            }
                          }
                          Navigator.pop(context);
                        },
                        showLastUsedBadge: _lastUsedLoginMethod == 'apple',
                      ),
                    ],
                    if (_featureFlags.loginFacebookEnabled) ...[
                      if (_featureFlags.loginAppleEnabled)
                        const SizedBox(height: 16),
                      _buildSocialActionButton(
                        iconPath: 'assets/social_icons/facebook_logo.svg',
                        label: 'CONTINUE WITH FACEBOOK',
                        onPressed: () {
                          _saveLastLoginMethod('facebook');
                          Navigator.pop(context);
                          context.read<AuthBloc>().add(
                            const SocialLoginEvent('Facebook'),
                          );
                        },
                        showLastUsedBadge: _lastUsedLoginMethod == 'facebook',
                      ),
                    ],
                  ],
                ),

                // Show divider only if there are social buttons above and email below
                if ((_featureFlags.loginAppleEnabled || _featureFlags.loginFacebookEnabled) &&
                    _featureFlags.loginEmailEnabled) ...[
                  const SizedBox(height: 40),
                  Row(
                    children: [
                      Expanded(
                        child: Container(height: 1, color: Colors.white24),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'or',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Container(height: 1, color: Colors.white24),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                ],

                // Email signup button
                if (_featureFlags.loginEmailEnabled) ...[
                  if (!_featureFlags.loginAppleEnabled && !_featureFlags.loginFacebookEnabled)
                    const SizedBox(height: 40),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _saveLastLoginMethod('email');
                            Navigator.pop(context);
                            context.read<AuthBloc>().add(ShowSignupFormEvent());
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentPrimary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(200, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.actionButtonRadius,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.email_outlined, size: 20),
                          label: const Text(
                            'CONTINUE WITH EMAIL',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      if (_lastUsedLoginMethod == 'email')
                        Positioned(
                          top: -8,
                          right: 8,
                          child: _buildLastUsedBadge(),
                        ),
                    ],
                  ),
                ],

                const SizedBox(height: 20),

                // Already have account link
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      context.read<AuthBloc>().add(ShowLoginFormEvent());
                    },
                    child: const Text(
                      'Already have an account? Login',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
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

  Widget _buildSocialActionButton({
    String? iconPath,
    Widget? leading,
    required String label,
    VoidCallback? onPressed,
    Color? backgroundColor,
    Color? foregroundColor,
    bool showLastUsedBadge = false,
    GlobalKey? buttonKey,
  }) {
    assert(
      iconPath != null || leading != null,
      'Either iconPath or leading must be provided',
    );

    final iconWidget =
        leading ?? SvgPicture.asset(iconPath!, width: 24, height: 24);

    // TODO: Here is where the last used badge is being shown. It is clipped in Login form
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            key: buttonKey,
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: backgroundColor ?? Colors.white,
              foregroundColor: foregroundColor ?? AppTheme.black,
              minimumSize: const Size(200, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppTheme.actionButtonRadius,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                iconWidget,
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showLastUsedBadge)
          Positioned(top: 14, right: 12, child: _buildLastUsedBadge()),
      ],
    );
  }

  Widget _buildLastUsedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accentPrimary,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Text(
        'Last Used',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLoginForm(AuthLoginFormState state) {
    final titleSpacing = state.isKeyboardVisible ? 0.0 : 36.0;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 30.0,
        vertical: state.isKeyboardVisible ? 20.0 : 0.0,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.isKeyboardVisible) const SizedBox(height: 20),
            _buildFormHeader(
              'Login',
              'connect with your community',
              state.isKeyboardVisible,
            ),
            SizedBox(height: titleSpacing),
            SizedBox(height: 40),
            _buildSocialLoginButtons(state),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: _showEmailLoginForm
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 24),
                        if (state.errorMessage != null)
                          _buildErrorContainer(state.errorMessage!),
                        _buildTextField(
                          'EMAIL',
                          'Enter your email',
                          false,
                          _emailFocusNode,
                          _emailController,
                          capitalization: TextCapitalization.none,
                          keyboardType: TextInputType.emailAddress,
                          forceLowercase: true,
                          textInputAction: TextInputAction.next,
                          onSubmitted: () => _passwordFocusNode.requestFocus(),
                          containerKey: _emailFieldKey,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          'PASSWORD',
                          'Enter your password',
                          true,
                          _passwordFocusNode,
                          _passwordController,
                          obscureText: _obscurePassword,
                          onToggleObscure: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                          textInputAction: TextInputAction.done,
                          containerKey: _passwordFieldKey,
                        ),
                        const SizedBox(height: 8),
                        _buildForgotPasswordButton(),
                        const SizedBox(height: 24),
                        _buildLoginButton(state),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            SizedBox(
              height: state.isKeyboardVisible
                  // ? MediaQuery.of(context).size.height * 0.12
                  ? 16.0
                  : 32.0,
            ),
            _buildSwitchToSignUpButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildForgotPasswordButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () async {
          final email = _emailController.text.trim().toLowerCase();
          if (email.isEmpty) {
            await AppDialog.show(
              context: context,
              icon: Icons.email_outlined,
              heading: 'Enter your email',
              subheading:
                  'Please type your email address first to recover your password.',
              dismissible: true,
            );
            return;
          }

          // Inform the user and auto-dismiss after 3 seconds
          await AppDialog.show(
            context: context,
            icon: Icons.mark_email_read,
            heading: 'Sending recovery email',
            subheading:
                'We\'ll send a recovery link to $email if it\'s associated with an account.',
            dismissible: false,
            autoCloseDuration: const Duration(seconds: 3),
          );

          final result = await SupabaseApiService.instance.requestPasswordReset(
            email,
          );
          if (!result.isSuccess) {
            // Show the error message from the API service (includes network errors)
            final errorMessage = result.error ??
                'Could not send reset email. Please try again.';
            _showErrorDialog(errorMessage);
          }
        },
        child: const Text(
          'Forgot password?',
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildLoginButton(AuthLoginFormState state) {
    return ElevatedButton(
      key: _loginSubmitKey,
      onPressed: state.isLoading
          ? null
          : () {
              _saveLastLoginMethod('email');
              context.read<AuthBloc>().add(
                LoginSubmittedEvent(
                  email: _emailController.text.trim().toLowerCase(),
                  password: _passwordController.text,
                ),
              );
            },
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.accentPrimary,
        foregroundColor: Colors.white,
        minimumSize: const Size(200, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.actionButtonRadius),
        ),
      ),
      child: state.isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Text(
              'LOGIN',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
    );
  }

  Widget _buildSocialLoginButtons(AuthLoginFormState state) {
    final buttons = <Widget>[];

    if (Platform.isIOS && _featureFlags.loginAppleEnabled) {
      buttons.add(
        _buildSocialActionButton(
          iconPath: 'assets/social_icons/apple_logo.svg',
          label: 'CONTINUE WITH APPLE',
          onPressed: state.isLoading
              ? null
              : () async {
                  await _saveLastLoginMethod('apple');
                  try {
                    final result = await SupabaseApiService.instance
                        .initiateAppleLogin();
                    if (result.isSuccess && result.data != null) {
                      await launchUrl(Uri.parse(result.data!));
                    } else {
                      // Show the error message from the API service
                      final errorMessage = result.error ??
                          'Failed to start Apple ID login. Please try again.';
                      _showErrorDialog(errorMessage);
                    }
                  } catch (e) {
                    // Handle network and other errors
                    final errorString = e.toString().toLowerCase();
                    if (errorString.contains('socketexception') ||
                        errorString.contains('timeoutexception') ||
                        errorString.contains('failed host lookup') ||
                        errorString.contains('network')) {
                      _showErrorDialog(
                        'Unable to connect to the server. Please check your internet connection and try again.',
                      );
                    } else {
                      _showErrorDialog(
                        'Apple login failed: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}',
                      );
                    }
                  }
                },
          backgroundColor: Colors.white,
          foregroundColor: AppTheme.black,
          showLastUsedBadge: _lastUsedLoginMethod == 'apple',
        ),
      );
      buttons.add(const SizedBox(height: 16));
    }

    if (_featureFlags.loginFacebookEnabled) {
      buttons.add(
        _buildSocialActionButton(
          iconPath: 'assets/social_icons/facebook_logo.svg',
          label: 'CONTINUE WITH FACEBOOK',
          onPressed: state.isLoading
              ? null
              : () {
                  _saveLastLoginMethod('facebook');
                  context.read<AuthBloc>().add(
                    const SocialLoginEvent('Facebook'),
                  );
                },
          backgroundColor: Colors.white,
          foregroundColor: AppTheme.black,
          showLastUsedBadge: _lastUsedLoginMethod == 'facebook',
        ),
      );
      buttons.add(const SizedBox(height: 16));
    }

    if (_featureFlags.loginEmailEnabled) {
      buttons.add(
        AnimatedCrossFade(
          firstChild: _buildSocialActionButton(
            leading: const Icon(
              Icons.email_outlined,
              color: Colors.white,
              size: 20,
            ),
            label: 'CONTINUE WITH EMAIL',
            onPressed: state.isLoading
                ? null
                : () {
                    if (_showEmailLoginForm) return;
                    _saveLastLoginMethod('email');
                    setState(() => _showEmailLoginForm = true);
                    _scheduleScreenReport();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _emailFocusNode.requestFocus();
                      }
                    });
                  },
            backgroundColor: AppTheme.accentPrimary,
            foregroundColor: Colors.white,
            showLastUsedBadge: _lastUsedLoginMethod == 'email',
            buttonKey: _emailLoginBtnKey,
          ),
          secondChild: const SizedBox.shrink(),
          crossFadeState: _showEmailLoginForm
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
          sizeCurve: Curves.easeInOutCubic,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: buttons,
      ),
    );
  }

  Widget _buildSwitchToSignUpButton() {
    return Center(
      child: TextButton(
        onPressed: () {
          FocusScope.of(context).unfocus();
          _showSignUpBottomSheet();
        },
        child: const Text(
          'New user? Sign Up',
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildSignupForm(AuthSignupFormState state) {
    final flexibleSpacing = state.isKeyboardVisible ? 10.0 : 20.0;
    final titleSpacing = state.isKeyboardVisible ? 20.0 : 56.0;

    // The form lives inside a Stack with unconstrained height, so
    // SingleChildScrollView can't scroll unless we give it a bounded height.
    // When the keyboard is open, constrain the scroll view to the visible
    // portion of the black section (95% of screen minus keyboard minus the
    // 40px of vertical padding this Padding widget adds).
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final scrollViewHeight = state.isKeyboardVisible
        ? screenHeight * 0.95 - keyboardHeight + 8.0
        : null;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 30.0,
        vertical: state.isKeyboardVisible ? 20.0 : 0.0,
      ),
      child: SizedBox(
        height: scrollViewHeight,
        child: SingleChildScrollView(
          controller: _signupScrollController,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.isKeyboardVisible) const SizedBox(height: 20),
              _buildFormHeader(
                ' Sign Up ',
                'join your community today',
                state.isKeyboardVisible,
              ),
              SizedBox(height: titleSpacing),
              if (state.errorMessage != null)
                _buildErrorContainer(state.errorMessage!),
              _buildTextField(
                'FULL NAME',
                'Enter your full name',
                false,
                _nameFocusNode,
                _nameController,
                showInput: _isFieldInputVisible(0),
                textInputAction: TextInputAction.next,
                onSubmitted: () => _emailFocusNode.requestFocus(),
              ),
              const SizedBox(height: 16),
              _buildTextField(
                'EMAIL',
                'Enter your email',
                false,
                _emailFocusNode,
                _emailController,
                showInput: _isFieldInputVisible(1),
                capitalization: TextCapitalization.none,
                keyboardType: TextInputType.emailAddress,
                forceLowercase: true,
                textInputAction: TextInputAction.next,
                onSubmitted: () => _passwordFocusNode.requestFocus(),
              ),
              const SizedBox(height: 16),
              _buildPasswordFieldWithValidation(
                'PASSWORD',
                'Enter your password',
                _passwordFocusNode,
                _passwordController,
                showInput: _isFieldInputVisible(2),
                textInputAction: TextInputAction.next,
                onSubmitted: () => _confirmPasswordFocusNode.requestFocus(),
              ),
              const SizedBox(height: 16),
              _buildPasswordRequirements(),
              SizedBox(height: _showPasswordRequirements ? 16 : 0),
              _buildTextField(
                'CONFIRM PASSWORD',
                'Confirm your password',
                true,
                _confirmPasswordFocusNode,
                _confirmPasswordController,
                showInput: _isFieldInputVisible(3),
                obscureText: _obscureConfirmPassword,
                onToggleObscure: () =>
                    setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 16),
              SizedBox(height: flexibleSpacing),
              _buildSignupActionButtons(state),
              SizedBox(
                height: state.isKeyboardVisible ? 16.0 : flexibleSpacing,
              ),
              _buildSwitchToLoginButton(),
              // const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _focusField(int index) {
    switch (index) {
      case 0:
        _nameFocusNode.requestFocus();
      case 1:
        _emailFocusNode.requestFocus();
      case 2:
        _passwordFocusNode.requestFocus();
      case 3:
        _confirmPasswordFocusNode.requestFocus();
    }
  }

  void _submitSignUp() {
    final validationError = _validatePasswords();
    if (validationError.isNotEmpty) {
      _showValidationError(validationError);
      return;
    }
    _saveLastLoginMethod('email');
    context.read<AuthBloc>().add(
      SignupSubmittedEvent(
        fullName: _nameController.text,
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text,
        confirmPassword: _confirmPasswordController.text,
      ),
    );
  }

  /// Shows the back + next/sign-up button row when the keyboard is open,
  /// or the plain Sign Up button when the keyboard is hidden.
  /// Tying visibility to isKeyboardVisible (not _focusedFieldIndex) ensures
  /// the buttons stay in the widget tree throughout the entire keyboard session,
  /// so onPressed always fires even when focus briefly transitions between fields.
  Widget _buildSignupActionButtons(AuthSignupFormState state) {
    if (!state.isKeyboardVisible) {
      return _buildSignUpButton(state);
    }

    // Use _focusedFieldIndex when available; fall back to _maxVisitedIndex
    // during the brief moment when focus transitions between fields.
    final currentIdx = _focusedFieldIndex ?? _maxVisitedIndex.clamp(0, 3);
    final isLast = currentIdx == 3;
    final hasPrev = currentIdx > 0;
    final prevIdx = hasPrev ? currentIdx - 1 : 0;
    final nextIdx = isLast ? 3 : currentIdx + 1;

    return Row(
      children: [
        // ── Back button (circular) ─────────────────────────────────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: hasPrev
              ? Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: state.isLoading
                          ? null
                          : () => _focusField(prevIdx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                        minimumSize: const Size(50, 50),
                        elevation: 0,
                      ),
                      child: const Icon(Icons.arrow_back, size: 20),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // ── Next / Sign Up button (fills remaining space) ──────────────────
        Expanded(
          child: ElevatedButton(
            onPressed: state.isLoading
                ? null
                : () {
                    if (isLast) {
                      _submitSignUp();
                    } else {
                      _focusField(nextIdx);
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPrimary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.actionButtonRadius),
              ),
            ),
            child: state.isLoading && isLast
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      isLast ? 'SIGN UP' : 'NEXT',
                      key: ValueKey(isLast),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignUpButton(AuthSignupFormState state) {
    return ElevatedButton(
      onPressed: state.isLoading ? null : _submitSignUp,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.accentPrimary,
        foregroundColor: Colors.white,
        minimumSize: const Size(200, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.actionButtonRadius),
        ),
      ),
      child: state.isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Text(
              'SIGN UP',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
    );
  }

  Widget _buildSwitchToLoginButton() {
    return Center(
      child: TextButton(
        onPressed: () {
          FocusScope.of(context).unfocus();
          context.read<AuthBloc>().add(ShowLoginFormEvent());
        },
        child: const Text(
          'Already have an account? Login',
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildFormHeader(
    String title,
    String subtitle,
    bool isKeyboardVisible,
  ) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: isKeyboardVisible ? 28 : 36,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorContainer(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.red, fontSize: 14),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildTextField(
    String label,
    String hint,
    bool isPassword,
    FocusNode focusNode,
    TextEditingController controller, {
    bool showInput = true,
    TextCapitalization capitalization = TextCapitalization.sentences,
    TextInputType keyboardType = TextInputType.text,
    bool? obscureText,
    VoidCallback? onToggleObscure,
    bool forceLowercase = false,
    TextInputAction textInputAction = TextInputAction.done,
    VoidCallback? onSubmitted,
    GlobalKey? containerKey,
  }) {
    final shouldObscure = obscureText ?? isPassword;

    return Column(
      key: containerKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: showInput
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: shouldObscure,
          textCapitalization: capitalization,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          scrollPadding: EdgeInsets.zero,
          onSubmitted: onSubmitted != null ? (_) => onSubmitted() : null,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: forceLowercase
              ? (value) {
                  final lowercased = value.toLowerCase();
                  if (value != lowercased) {
                    controller.value = controller.value.copyWith(
                      text: lowercased,
                      selection: TextSelection.collapsed(offset: lowercased.length),
                    );
                  }
                }
              : null,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.grey[800],
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 15,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.orange, width: 1),
            ),
            suffixIcon: isPassword && onToggleObscure != null
                ? IconButton(
                    icon: Icon(
                      shouldObscure ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white54,
                      size: 20,
                    ),
                    onPressed: onToggleObscure,
                  )
                : null,
          ),
          style: const TextStyle(color: Colors.white),
        ),
                  ],
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }

  Widget _buildPasswordFieldWithValidation(
    String label,
    String hint,
    FocusNode focusNode,
    TextEditingController controller, {
    bool showInput = true,
    TextInputAction textInputAction = TextInputAction.done,
    VoidCallback? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: showInput
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      focusNode: focusNode,
                      obscureText: _obscurePassword,
                      textInputAction: textInputAction,
                      scrollPadding: EdgeInsets.zero,
                      onSubmitted: onSubmitted != null ? (_) => onSubmitted() : null,
                      autocorrect: false,
                      enableSuggestions: false,
                      onChanged: (value) {
                        setState(() {});
                        _onPasswordChanged();
                      },
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.grey[800],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 15,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Colors.orange, width: 1),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: Colors.white54,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }

  Widget _buildPasswordRequirements() {
    if (!_showPasswordRequirements) return const SizedBox.shrink();

    final allDone = _dismissedRequirements.length == 4;
    final password = _passwordController.text;

    final requirements = [
      MapEntry('At least 6 characters', password.length >= 6),
      MapEntry('One uppercase letter', password.contains(RegExp(r'[A-Z]'))),
      MapEntry('One lowercase letter', password.contains(RegExp(r'[a-z]'))),
      MapEntry('One number', password.contains(RegExp(r'[0-9]'))),
    ];

    return AnimatedContainer(
      key: _passwordRequirementsKey,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: allDone
            ? Colors.green.withOpacity(0.1)
            : AppTheme.darkBorder,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: allDone
              ? Colors.green.withOpacity(0.4)
              : AppTheme.white.withOpacity(0.05),
        ),
      ),
      child: allDone
          ? const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text(
                  'Password looks good!',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Password Requirements:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accentPrimary,
                  ),
                ),
                for (int i = 0; i < requirements.length; i++)
                  // Wrap each row in a Row+Expanded so AnimatedSize only collapses height
                  Row(
                    children: [
                      Expanded(
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          child: _dismissedRequirements.contains(i)
                              ? const SizedBox(height: 0)
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(height: i == 0 ? 12 : 8),
                                    _buildRequirementRow(
                                      requirements[i].key,
                                      requirements[i].value,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
    );
  }

  Widget _buildRequirementRow(String requirement, bool isSatisfied) {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSatisfied ? Colors.green : Colors.transparent,
            border: Border.all(
              color: isSatisfied ? Colors.green : AppTheme.accentSecondary,
              width: 2,
            ),
          ),
          child: isSatisfied
              ? const Icon(Icons.check, color: Colors.white, size: 14)
              : null,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            requirement,
            style: TextStyle(
              fontSize: 14,
              color: isSatisfied ? Colors.green : AppTheme.accentSecondary,
              fontWeight: isSatisfied ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  String _validatePasswords() {
    if (_nameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      return 'Please fill in all fields';
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      return 'Passwords do not match';
    }

    if (_passwordController.text.length < 6) {
      return 'Password must be at least 6 characters';
    }

    if (!_passwordController.text.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }

    if (!_passwordController.text.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter';
    }

    if (!_passwordController.text.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }

    return '';
  }
}
