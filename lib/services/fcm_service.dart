import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logging/logging.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/services/notification_preferences_service.dart';
import 'package:mvc_app/firebase_options.dart';
import 'package:mvc_app/main_scaffold.dart';

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  static FCMService get instance => _instance;

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final Logger _logger = Logger('FCMService');

  ApiRepository? _apiRepository;
  NotificationPreferencesService? _prefsService;

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  bool _isInitialized = false;
  //
  // Initialize FCM service
  Future<void> initialize({
    required ApiRepository apiRepository,
    required NotificationPreferencesService prefsService,
  }) async {
    if (_isInitialized) {
      // Update dependencies in case they changed (e.g. after re-login)
      _apiRepository = apiRepository;
      _prefsService = prefsService;
      return;
    }
    _isInitialized = true;
    _apiRepository = apiRepository;
    _prefsService = prefsService;

    try {
      // Initialize Firebase if not already done
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      // Request permission for notifications
      await _requestPermission();

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Get and store FCM token
      await _setupFCMToken();

      // Setup message handlers
      _setupMessageHandlers();

      _logger.info('FCM Service initialized successfully');
    } catch (e) {
      _logger.severe('Failed to initialize FCM service: $e');
    }
  }

  // Request notification permissions
  Future<void> _requestPermission() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      _logger.info('User granted permission');
    } else if (settings.authorizationStatus ==
        AuthorizationStatus.provisional) {
      _logger.info('User granted provisional permission');
    } else {
      _logger.warning('User declined or has not accepted permission');
    }
  }

  // Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      const postChannel = AndroidNotificationChannel(
        'post_notifications',
        'Post Notifications',
        description: 'Notifications for new posts in followed channels',
        importance: Importance.high,
      );

      const dmChannel = AndroidNotificationChannel(
        'dm_notifications',
        'Direct Messages',
        description: 'Notifications for direct messages',
        importance: Importance.high,
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await androidPlugin?.createNotificationChannel(postChannel);
      await androidPlugin?.createNotificationChannel(dmChannel);
    }
  }

  // Setup FCM token
  Future<void> _setupFCMToken() async {
    try {
      _fcmToken = await _firebaseMessaging.getToken();
      if (_fcmToken != null) {
        _logger.info('FCM Token obtained: ${_fcmToken!.substring(0, 20)}...');
        await _storeFCMTokenInSupabase(_fcmToken!);
      }

      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((token) {
        _fcmToken = token;
        _storeFCMTokenInSupabase(token);
      });
    } catch (e) {
      _logger.severe('Failed to get FCM token: $e');
    }
  }

  // Store FCM token in Supabase
  Future<void> _storeFCMTokenInSupabase(String token) async {
    try {
      if (_apiRepository != null) {
        await _apiRepository!.storeFCMToken(token);
        _logger.info('FCM token stored in Supabase');
      }
    } catch (e) {
      _logger.severe('Failed to store FCM token in Supabase: $e');
    }
  }

  // Setup message handlers
  void _setupMessageHandlers() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background messages (when app is in background but not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // Handle messages when app is opened from terminated state
    _firebaseMessaging.getInitialMessage().then((message) {
      if (message != null) {
        _handleMessageOpenedApp(message);
      }
    });
  }

  // Handle foreground messages
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    _logger.info('Received foreground message: ${message.messageId}');

    // DM and vehicle-inquiry notifications use the in-app banner overlay
    // instead of a system notification, so we skip _showLocalNotification.
    final foregroundType = message.data['notification_type'];
    if (foregroundType == 'direct_message' ||
        foregroundType == 'vehicle_inquiry') {
      _logger.info('$foregroundType foreground message — handled by in-app banner');
      return;
    }

    // Check if notifications are enabled for this channel
    final channelId = message.data['channel_id'];
    if (channelId != null && _prefsService != null) {
      final isEnabled = await _prefsService!.isChannelNotificationEnabled(
        channelId,
      );
      if (!isEnabled) {
        _logger.info('Notifications disabled for channel $channelId, skipping');
        return;
      }
    }

    // Show local notification
    await _showLocalNotification(message);
  }

  // Handle message when app is opened from notification
  Future<void> _handleMessageOpenedApp(RemoteMessage message) async {
    _logger.info('App opened from notification: ${message.messageId}');

    // Clear the notification badge immediately when app is opened from notification
    await updateNotificationBadge(count: 0);

    // Navigate to specific screen based on message data
    final notificationType = message.data['notification_type'] ?? 'post';
    final channelId = message.data['channel_id'];
    final postId = message.data['post_id'];
    final conversationId = message.data['conversation_id'];

    if (notificationType == 'direct_message' && conversationId != null) {
      // Navigate to direct messages
      _navigateToDirectMessages(conversationId);
      _logger.info('Navigating to direct message conversation: $conversationId');
    } else if (notificationType == 'vehicle_inquiry' && conversationId != null) {
      // Navigate to the Market inquiry chat (car or any other listing)
      _navigateToVehicleInquiry(conversationId);
      _logger.info('Navigating to vehicle inquiry conversation: $conversationId');
    } else if (channelId != null) {
      // Navigate to the specific channel
      _navigateToChannel(channelId, postId);
      _logger.info('Navigating to channel: $channelId, post: $postId');
    }
  }

  // Show local notification
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final isDM = message.data['notification_type'] == 'direct_message';

    final androidDetails = AndroidNotificationDetails(
      isDM ? 'dm_notifications' : 'post_notifications',
      isDM ? 'Direct Messages' : 'Post Notifications',
      channelDescription: isDM
          ? 'Notifications for direct messages'
          : 'Notifications for new posts in followed channels',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      details,
      payload: jsonEncode(message.data),
    );
  }

  // Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        final notificationType = data['notification_type'] ?? 'post';
        final channelId = data['channel_id'];
        final postId = data['post_id'];
        final conversationId = data['conversation_id'];

        // Clear the notification badge when notification is tapped
        updateNotificationBadge(count: 0);

        if (notificationType == 'direct_message' && conversationId != null) {
          // Navigate to direct messages
          _navigateToDirectMessages(conversationId);
          _logger.info(
            'Notification tapped - navigating to direct message conversation: $conversationId',
          );
        } else if (notificationType == 'vehicle_inquiry' &&
            conversationId != null) {
          // Navigate to the Market inquiry chat (car or any other listing)
          _navigateToVehicleInquiry(conversationId);
          _logger.info(
            'Notification tapped - navigating to vehicle inquiry conversation: $conversationId',
          );
        } else if (channelId != null) {
          // Navigate to the specific channel
          _navigateToChannel(channelId, postId);
          _logger.info(
            'Notification tapped - navigating to channel: $channelId, post: $postId',
          );
        }
      } catch (e) {
        _logger.warning('Failed to parse notification payload: $e');
      }
    }
  }

  // Subscribe to topic (for channel notifications)
  Future<void> subscribeToChannel(String channelId) async {
    try {
      await _firebaseMessaging.subscribeToTopic('channel_$channelId');
      _logger.info('Subscribed to channel topic: channel_$channelId');
    } catch (e) {
      _logger.severe('Failed to subscribe to channel topic: $e');
    }
  }

  // Update notification badge on iOS
  // If count is null or 0, clears the badge
  Future<void> updateNotificationBadge({int? count}) async {
    try {
      final badgeCount = count ?? 0;
      // Ensure we await the badge update, especially important on iOS
      await AppBadgePlus.updateBadge(badgeCount);
      
      if (badgeCount == 0) {
        _logger.info('iOS notification badge cleared');
      } else {
        _logger.info('iOS notification badge updated to $badgeCount');
      }
    } catch (e) {
      _logger.warning('Failed to update notification badge: $e');
      // Re-throw to allow callers to handle the error if needed
      rethrow;
    }
  }

  // Clear notification badge on iOS (backwards compatibility)
  Future<void> clearNotificationBadge() async {
    await updateNotificationBadge(count: 0);
  }

  // Navigate to a specific channel
  void _navigateToChannel(String channelId, String? postId) {
    try {
      // Access the main scaffold to switch to channels tab and select the channel
      if (mainScaffoldKey.currentState != null) {
        mainScaffoldKey.currentState!.switchToChannelsTab(
          organizationId: channelId,
        );
        _logger.info('Navigated to channel: $channelId');
      } else {
        _logger.warning('MainScaffold not available for navigation');
      }
    } catch (e) {
      _logger.warning('Failed to navigate to channel: $e');
    }
  }

  // Navigate to direct messages
  void _navigateToDirectMessages(String conversationId) {
    try {
      // Access the main scaffold to switch to direct messages tab
      if (mainScaffoldKey.currentState != null) {
        mainScaffoldKey.currentState!.switchToDirectMessagesTab(
          conversationId: conversationId,
        );
        _logger.info('Navigated to direct messages: $conversationId');
      } else {
        _logger.warning('MainScaffold not available for navigation');
      }
    } catch (e) {
      _logger.warning('Failed to navigate to direct messages: $e');
    }
  }

  // Navigate to a Market inquiry chat (car or any other listing)
  void _navigateToVehicleInquiry(String conversationId) {
    try {
      if (mainScaffoldKey.currentState != null) {
        mainScaffoldKey.currentState!
            .openVehicleInquiryConversation(conversationId);
        _logger.info('Navigated to vehicle inquiry: $conversationId');
      } else {
        _logger.warning('MainScaffold not available for navigation');
      }
    } catch (e) {
      _logger.warning('Failed to navigate to vehicle inquiry: $e');
    }
  }

  // Unsubscribe from topic
  Future<void> unsubscribeFromChannel(String channelId) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic('channel_$channelId');
      _logger.info('Unsubscribed from channel topic: channel_$channelId');
    } catch (e) {
      _logger.severe('Failed to unsubscribe from channel topic: $e');
    }
  }

  // Clear badge when app becomes active (user opens the app)
  Future<void> clearBadgeOnAppActive() async {
    try {
      await updateNotificationBadge(count: 0);
      _logger.info('Badge cleared on app active');
    } catch (e) {
      _logger.warning('Failed to clear badge on app active: $e');
    }
  }

  // Clean up on logout
  Future<void> cleanup() async {
    try {
      if (_fcmToken != null && _apiRepository != null) {
        await _apiRepository!.removeFCMToken(_fcmToken!);
      }
      await _firebaseMessaging.deleteToken();
      _fcmToken = null;
      _isInitialized = false;
      _logger.info('FCM service cleaned up');
    } catch (e) {
      _logger.severe('Failed to cleanup FCM service: $e');
    }
  }
}

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase with platform-specific options
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final logger = Logger('FCMBackgroundHandler');
  logger.info('Handling background message: ${message.messageId}');

  // You can perform background tasks here if needed
  // Note: This runs in a separate isolate, so you can't access app state
}
