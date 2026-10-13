// main.dart - ONLY handles initialization and routing
import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mvc_app/modules/auth/onboarding_screen.dart';
import 'package:mvc_app/modules/auth/otp_verification_screen.dart';
import 'package:mvc_app/modules/auth/reset_link_error_screen.dart';
import 'package:mvc_app/modules/auth/reset_password_screen.dart';
import 'package:mvc_app/modules/auth/verification_method_choice_screen.dart';
import 'package:mvc_app/modules/auth/sms_otp_verification_screen.dart';
import 'package:mvc_app/modules/auth/sign_up_otp_explanation_screen.dart';
import 'package:mvc_app/modules/chat/real_chat_scree.dart';
import 'package:mvc_app/modules/profile/profile_settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';
import 'package:app_links/app_links.dart';

import 'package:mvc_app/flavour_config.dart';
import 'package:mvc_app/qa_badge_widget.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal_chain.dart';
import 'package:mvc_app/modules/auth/chain/handlers/app_start_handler.dart';
import 'package:mvc_app/modules/auth/chain/handlers/flow_guard_handler.dart';
import 'package:mvc_app/modules/auth/chain/handlers/password_reset_link_handler.dart';
import 'package:mvc_app/modules/auth/chain/handlers/session_link_handler.dart';
import 'package:mvc_app/modules/auth/chain/handlers/supabase_signed_in_handler.dart';
import 'package:mvc_app/modules/auth/chain/handlers/supabase_signed_out_handler.dart';
import 'package:mvc_app/modules/auth/chain/handlers/vehicle_inquiry_link_handler.dart';
import 'package:mvc_app/modules/channels/categories_bloc.dart';
import 'package:mvc_app/modules/chat/chat_bloc.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/fcm_service.dart';
import 'package:mvc_app/services/notification_preferences_service.dart';
import 'package:mvc_app/app_router.dart';
import 'package:mvc_app/main_scaffold.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:upgrader/upgrader.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:mvc_app/firebase_options.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mvc_app/widgets/app_dialog.dart';
import 'package:mvc_app/utils/version_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:mvc_app/testability/testability_server.dart';
import 'package:mvc_app/services/amplitude_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _setupLogging();

  if (!kReleaseMode) {
    await TestabilityServer.start();
  }

  // 🔥 CRITICAL FIX: Initialize Firebase with platform-specific options
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Set background message handler for FCM
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Only report crashes from release/profile builds, not local debug runs.
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
    !kDebugMode,
  );
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  await SupabaseApiService.instance.initialize(
    environment: FlavorConfig.supabaseEnvironment,
  );

  await AmplitudeService.instance.initialize();

  runApp(const MyApp());
}

void _setupLogging() {
  hierarchicalLoggingEnabled = true;
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    final emoji = _getLogEmoji(record.level);
    print(
      '$emoji ${record.level.name}: ${record.time}: [${record.loggerName}] ${record.message}',
    );
  });
}

String _getLogEmoji(Level level) {
  switch (level.name) {
    case 'SEVERE':
      return '🔴';
    case 'WARNING':
      return '🟡';
    case 'INFO':
      return '🔵';
    case 'CONFIG':
      return '⚙️';
    default:
      return '📝';
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        Provider<ApiRepository>(
          create: (context) => ApiRepository(SupabaseApiService.instance),
        ),
        Provider<NotificationPreferencesService>(
          create: (context) => NotificationPreferencesService.instance,
        ),
        Provider<FCMService>(create: (context) => FCMService.instance),
        BlocProvider(
          create: (context) =>
              AuthBloc(apiRepository: context.read<ApiRepository>()),
        ),
        BlocProvider(
          create: (context) => ChatBloc(authBloc: context.read<AuthBloc>()),
        ),
        BlocProvider(create: (context) => CategoriesBloc()),
      ],
      child: UpgradeAlert(
        upgrader: Upgrader(
          debugLogging: true,
          debugDisplayAlways: false,
          debugDisplayOnce: false,
          durationUntilAlertAgain: const Duration(days: 3),
        ),
        showIgnore: true,
        showLater: true,
        showReleaseNotes: true,
        child: MaterialApp(
          title: 'MVC',
          theme: AppTheme.lightTheme,
          debugShowCheckedModeBanner: false,
          home: const QABadgeWrapper(child: AppRouter()),
          onGenerateRoute: AppRouter.generateRoute,
        ),
      ),
    );
  }
}

// Simple router that only handles navigation logic
class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();

  static Route<dynamic>? generateRoute(RouteSettings settings) {
    // Import your screens at the top of the file first

    switch (settings.name) {
      // case '/welcome':
      //   return MaterialPageRoute(
      //     builder: (context) => const QABadgeWrapper(child: WelcomeScreen()),
      //     settings: settings,
      //   );

      case '/home':
        final arguments = settings.arguments as Map<String, dynamic>?;
        final organizationId = arguments?['organizationId'] as String?;
        return MaterialPageRoute(
          builder: (context) => QABadgeWrapper(
            child: RealChatScreen(organizationId: organizationId),
          ),
          settings: settings,
        );

      case '/intro':
        return MaterialPageRoute(
          builder: (context) => const QABadgeWrapper(child: OnboardingScreen()),
          settings: settings,
        );

      case '/verification':
        return MaterialPageRoute(
          builder: (context) =>
              const QABadgeWrapper(child: SignUpOtpExplanationScreen()),
          settings: settings,
        );

      case '/profile':
        return MaterialPageRoute(
          builder: (context) => const QABadgeWrapper(child: SettingsScreen()),
          settings: settings,
        );

      // case '/reset-password':
      //   return MaterialPageRoute(
      //     builder: (context) => const QABadgeWrapper(child: ResetPasswordScreen()),
      //     settings: settings,
      //   );

      default:
        // Return null to let Flutter handle unknown routes
        return null;
    }
  }

  // }
}

class _AppRouterState extends State<AppRouter>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late AppLinks _appLinks;
  late AuthSignalChain _authSignalChain;
  bool _isInitialized = false;
  late AnimationController _overlayController;
  late Animation<double> _overlayOpacity;
  Future<void>? _overlayFadeInFuture;
  bool _showTransitionOverlay = false;
  bool _holdSolidCover = false;
  bool _overlayDismissScheduled = false;
  static const Duration _overlayFadeInDuration = Duration(milliseconds: 200);
  static const Duration _overlayFadeOutDuration = Duration(milliseconds: 220);
  static const Duration _overlayHoldDuration = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _overlayController = AnimationController(
      vsync: this,
      duration: _overlayFadeInDuration,
    );
    _overlayOpacity = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeInOut,
    );
    _authSignalChain = AuthSignalChain(
      authBloc: context.read<AuthBloc>(),
      handlers: [
        FlowGuardHandler(),
        PasswordResetLinkHandler(),
        SessionLinkHandler(),
        VehicleInquiryLinkHandler(),
        SupabaseSignedInHandler(),
        SupabaseSignedOutHandler(onSignedOut: _onSignedOut),
        AppStartHandler(),
      ],
    );
    _initializeStartupOverlayIfNeeded();
    _initializeApp();
    _setupAuthListener();
  }

  void _onSignedOut() {
    print('👋 User signed out');

    AmplitudeService.instance.logEvent('user_signed_out');
    AmplitudeService.instance.reset();

    // Clean up FCM when user signs out
    final fcmService = context.read<FCMService>();
    fcmService.cleanup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlayController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // App became active - clear notification badge
      _clearNotificationBadgeOnAppActive();
      // Check version requirements every time app resumes
      _checkVersionRequirements();
    }
  }

  Future<void> _clearNotificationBadgeOnAppActive() async {
    try {
      final fcmService = context.read<FCMService>();
      await fcmService.clearBadgeOnAppActive();
    } catch (e) {
      print('Failed to clear notification badge on app active: $e');
    }
  }

  Future<void> _initializeApp() async {
    await _setupDeepLinks();
    await _checkVersionRequirements();
    await _checkInitialAuthState();

    if (mounted) {
      setState(() => _isInitialized = true);
    }
  }

  Future<void> _openAppStore() async {
    final String url;
    if (Platform.isIOS) {
      url = 'https://apps.apple.com/us/app/magic-valley-central/id6748038305';
    } else if (Platform.isAndroid) {
      url =
          'https://play.google.com/store/apps/details?id=com.magicvalleycentral.mvc_app&pli=1';
    } else {
      return; // Unsupported platform
    }

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        print('⚠️ Could not launch app store URL: $url');
      }
    } catch (e) {
      print('⚠️ Error opening app store: $e');
    }
  }

  Future<void> _checkVersionRequirements() async {
    try {
      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = VersionUtils.extractMarketingVersion(
        packageInfo.version,
      );
      print(
        '📱 Current app version: ${packageInfo.version} (marketing: $currentVersion)',
      );

      // Fetch feature flags from database
      final apiRepository = context.read<ApiRepository>();
      final result = await apiRepository.getFeatureFlags();

      if (!result.isSuccess || result.data == null) {
        print('⚠️ Failed to fetch feature flags: ${result.error}');
        return;
      }

      final featureFlags = result.data!;
      final isAndroid = Platform.isAndroid;
      final isIOS = Platform.isIOS;
      print(
        '📱 Platform: ${isAndroid
            ? "Android"
            : isIOS
            ? "iOS"
            : "Unknown"}',
      );

      // Check required version first (most critical)
      String? requiredVersion;
      if (isAndroid) {
        requiredVersion = featureFlags.minRequiredVersionAndroid;
        print('📱 Required version (Android): $requiredVersion');
      } else if (isIOS) {
        requiredVersion = featureFlags.minRequiredVersionIos;
        print('📱 Required version (iOS): $requiredVersion');
      }

      if (requiredVersion != null && requiredVersion.isNotEmpty) {
        final isLessThanRequired = VersionUtils.isVersionLessThan(
          currentVersion,
          requiredVersion,
        );
        print(
          '📱 Version check (required): $currentVersion < $requiredVersion = $isLessThanRequired',
        );

        if (isLessThanRequired) {
          print('🔴 Showing REQUIRED update dialog');
          // Show non-dismissible dialog with 6000 second timeout
          if (mounted) {
            await AppDialog.show(
              context: context,
              icon: Icons.system_update,
              heading: 'Update Required',
              subheading:
                  'Please update to version $requiredVersion or later to continue using the app.',
              dismissible: false,
              autoCloseDuration: const Duration(seconds: 6000),
              onOkPressed: _openAppStore,
            );
            print('✅ Required update dialog shown');
          } else {
            print('⚠️ Widget not mounted, cannot show required dialog');
          }
          return; // Don't check recommended if required fails
        }
      } else {
        print('📱 No required version set');
      }

      // Check recommended version
      String? recommendedVersion;
      if (isAndroid) {
        recommendedVersion = featureFlags.minRecommendedVersionAndroid;
        print('📱 Recommended version (Android): $recommendedVersion');
      } else if (isIOS) {
        recommendedVersion = featureFlags.minRecommendedVersionIos;
        print('📱 Recommended version (iOS): $recommendedVersion');
      }

      if (recommendedVersion != null && recommendedVersion.isNotEmpty) {
        final isLessThanRecommended = VersionUtils.isVersionLessThan(
          currentVersion,
          recommendedVersion,
        );
        print(
          '📱 Version check (recommended): $currentVersion < $recommendedVersion = $isLessThanRecommended',
        );

        if (isLessThanRecommended) {
          print('🟡 Showing RECOMMENDED update dialog');
          // Show dismissible dialog with OK button
          if (mounted) {
            await AppDialog.show(
              context: context,
              icon: Icons.upgrade,
              heading: 'Update Available',
              subheading:
                  'A new version ($recommendedVersion) is available with new features and improvements.',
              dismissible: true,
              onOkPressed: _openAppStore,
            );
            print('✅ Recommended update dialog shown');
          } else {
            print('⚠️ Widget not mounted, cannot show recommended dialog');
          }
        } else {
          print('✅ App version meets recommended requirement');
        }
      } else {
        print('📱 No recommended version set');
      }
    } catch (e, stackTrace) {
      print('⚠️ Error checking version requirements: $e');
      print('⚠️ Stack trace: $stackTrace');
      // Ignore errors and continue app initialization
    }
  }

  Future<void> _setupDeepLinks() async {
    _appLinks = AppLinks();

    // Handle deep links while app is running
    _appLinks.uriLinkStream.listen(
      (uri) => _authSignalChain.dispatch(AuthSignal.deepLink(uri)),
    );

    // Handle deep links when app starts
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) {
        _authSignalChain.dispatch(AuthSignal.deepLink(uri));
      }
    } catch (e) {
      print('Initial deep link error: $e');
    }
  }

  Future<void> _checkInitialAuthState() async {
    _authSignalChain.dispatch(const AuthSignal.appStart());
  }

  Future<void> _initializeFCM() async {
    try {
      final apiRepository = context.read<ApiRepository>();
      final prefsService = context.read<NotificationPreferencesService>();
      final fcmService = context.read<FCMService>();

      await prefsService.initialize();
      await fcmService.initialize(
        apiRepository: apiRepository,
        prefsService: prefsService,
      );
    } catch (e) {
      print('Failed to initialize FCM: $e');
    }
  }

  void _initializeStartupOverlayIfNeeded() {
    try {
      final currentSession = SupabaseApiService.auth.currentSession;
      if (currentSession == null) {
        return;
      }

      _showTransitionOverlay = true;
      _holdSolidCover = true;
      _overlayController.value = 0.0;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        _overlayFadeInFuture = _overlayController.animateTo(
          1.0,
          duration: _overlayFadeInDuration,
          curve: Curves.easeInOut,
        );

        _overlayFadeInFuture?.whenComplete(() {
          if (!mounted) return;
          if (_holdSolidCover) {
            setState(() {
              _holdSolidCover = false;
            });
          }
        });
      });
    } catch (e) {
      print('⚠️ Failed to start startup overlay: $e');
    }
  }

  void _handleAuthStateTransition(AuthState state) {
    if (_showTransitionOverlay) {
      if (state is AuthAuthenticatedState) {
        _dismissOverlayAfterAuthSuccess();
      } else if (_shouldDismissOverlayForState(state)) {
        _dismissOverlayAfterAuthFailure();
      }
    }

    if (state is AuthAuthenticatedState && state.userProfile?.username != null) {
      AmplitudeService.instance.setUserId(state.userProfile!.username!);
      AmplitudeService.instance.setUserProperties({
        'email': state.email,
        'role': state.userProfile!.role.value,
      });
    }
  }

  bool _shouldDismissOverlayForState(AuthState state) {
    return state is AuthWelcomeState ||
        state is AuthLoginFormState ||
        state is AuthSignupFormState ||
        state is AuthErrorState ||
        state is AuthPendingEmailConfirmationState ||
        state is AuthVerificationMethodChoiceState ||
        state is AuthPendingPhoneVerificationState ||
        state is AuthPasswordResetState ||
        state is AuthPasswordResetLinkErrorState;
  }

  Future<void> _dismissOverlayAfterAuthSuccess() async {
    if (_overlayDismissScheduled) return;
    _overlayDismissScheduled = true;

    try {
      if (_overlayFadeInFuture != null) {
        await _overlayFadeInFuture;
      }

      await Future.delayed(_overlayHoldDuration);

      if (!mounted) return;

      await _overlayController.animateTo(
        0.0,
        duration: _overlayFadeOutDuration,
        curve: Curves.easeOut,
      );

      if (!mounted) return;

      setState(() {
        _showTransitionOverlay = false;
        _holdSolidCover = false;
      });
    } finally {
      _overlayDismissScheduled = false;
    }
  }

  Future<void> _dismissOverlayAfterAuthFailure() async {
    if (_overlayDismissScheduled) return;
    _overlayDismissScheduled = true;

    try {
      if (_overlayFadeInFuture != null) {
        await _overlayFadeInFuture;
      }

      if (!mounted) return;

      await _overlayController.animateTo(
        0.0,
        duration: _overlayFadeOutDuration,
        curve: Curves.easeOut,
      );

      if (!mounted) return;

      setState(() {
        _showTransitionOverlay = false;
        _holdSolidCover = false;
      });
    } finally {
      _overlayDismissScheduled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return _buildLoadingScreen();
    }

    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) => _handleAuthStateTransition(state),
      builder: (context, state) {
        final screen = _routeToScreen(state);
        return Stack(
          fit: StackFit.expand,
          children: [
            screen,
            if (_holdSolidCover) Container(color: AppTheme.cardGreyBackground),
            if (_showTransitionOverlay)
              IgnorePointer(
                ignoring: true,
                child: FadeTransition(
                  opacity: _overlayOpacity,
                  child: Container(color: AppTheme.cardGreyBackground),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: AppTheme.cardGreyBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/MainScreenLogo.png',
              width: 200,
              height: 200,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeToScreen(AuthState state) {
    // Route to appropriate screen based on auth state
    switch (state.runtimeType) {
      case AuthAuthenticatedState:
        // Initialize FCM when user is authenticated
        _initializeFCM();
        return _getHomeScreen();

      case AuthVerificationMethodChoiceState:
        final choiceState = state as AuthVerificationMethodChoiceState;
        return _getVerificationChoiceScreen(choiceState.email);

      case AuthPendingPhoneVerificationState:
        final phoneState = state as AuthPendingPhoneVerificationState;
        return _getSmsOtpScreen(phoneState.phoneNumber, phoneState.email);

      case AuthPendingEmailConfirmationState:
        final pendingState = state as AuthPendingEmailConfirmationState;
        return _getOtpScreen(pendingState.email, pendingState.otpType);

      case AuthPasswordResetState:
        final resetState = state as AuthPasswordResetState;
        return _getResetPasswordScreen(resetState.resetToken, resetState.uri);

      case AuthPasswordResetLinkErrorState:
        final linkErrorState = state as AuthPasswordResetLinkErrorState;
        return ResetLinkErrorScreen(message: linkErrorState.message);

      case AuthLoadingState:
        return _buildLoadingScreen();

      default:
        return _getAuthScreen();
    }
  }

  // Screen factory methods - import your actual screens here
  Widget _getHomeScreen() {
    return MainScaffold(key: mainScaffoldKey);
  }

  Widget _getVerificationChoiceScreen(String email) {
    return VerificationMethodChoiceScreen(email: email);
  }

  Widget _getSmsOtpScreen(String phoneNumber, String email) {
    return SmsOtpVerificationScreen(phoneNumber: phoneNumber, email: email);
  }

  Widget _getOtpScreen(String email, String otpType) {
    return OtpVerificationScreen(email: email, otpType: otpType); // Import this
  }

  Widget _getResetPasswordScreen(String resetToken, Uri uri) {
    return ResetPasswordScreen(resetToken: resetToken, uri: uri); // Import this
  }

  Widget _getAuthScreen() {
    return const AuthFlowScreen(); // This is your new auth screen
  }

  void _setupAuthListener() {
    SupabaseApiService.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;

      print('🔐 Auth state changed: ${data.event}');
      _authSignalChain.dispatch(
        AuthSignal.supabaseAuthEvent(data.event, data.session),
      );
    });
  }
}
