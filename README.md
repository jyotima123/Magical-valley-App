# MVC Community App 🚀

A powerful Flutter-based community platform that connects organizations with their members through real-time messaging, content sharing, and social features. Built with modern architecture using BLoC pattern and Supabase backend.

## 📋 Latest Release

<!-- LATEST_RELEASE_START -->
# 1.7.2

- Feature: new "Seller" filter on the Cars filter sheet — Dealer or Private Seller (either or both); with neither selected, everything shows
- Feature: vehicle detail now shows the dealership's own name for feed inventory (e.g. the LiftKit dealer) instead of the integration label "LiftKit"
- Feature: the Cars list now shows vehicles without pictures after the ones that have pictures, whatever sort is selected
- Change: revamped the Magic Market initial screen
- Change: Market's "My Listings" moved from a left-hand drawer into a menu at the top right, next to the Add button
<!-- LATEST_RELEASE_END -->

Most recent Android build: <!-- ANDROID_VERSION_START -->1.7.2<!-- ANDROID_VERSION_END --> | Most recent iOS build: <!-- IOS_VERSION_START -->1.6.12<!-- IOS_VERSION_END -->

## ✨ Features

### 🔐 Authentication & Security
- **Multi-platform Authentication**: Email/password, Apple Sign-In (native iOS support)
- **Secure OTP Verification**: Email-based verification with auto-fill support
- **Password Reset Flow**: Deep-link enabled password recovery
- **Social Login Integration**: Streamlined onboarding experience

### 💬 Real-time Chat & Messaging
- **Organization Channels**: Follow and chat with organizations by category
- **Rich Media Support**: Text, images, PDFs, and file attachments
- **Message Reactions**: Emoji reactions for enhanced engagement
- **Pinned Messages**: Admin-controlled message highlighting
- **Search & Filtering**: Find conversations and organizations quickly
- **WhatsApp-style UX**: Familiar chat interface with auto-scroll and timestamps

### 🏢 Organization Management
- **Category-based Discovery**: Explore organizations by interest categories
- **Follow/Unfollow System**: Curated content feed from followed organizations
- **Admin Controls**: Organization management, user roles, and content moderation
- **Profile Management**: Organization profiles with images and descriptions
- **Follower Analytics**: Track engagement and community growth

### 📱 Modern Mobile Experience
- **Cross-platform**: iOS and Android support
- **Responsive Design**: Optimized for all screen sizes
- **Dark/Light Themes**: Customizable appearance
- **Offline Support**: Cached content for better performance
- **Push Notifications**: Stay updated with real-time alerts
- **Deep Linking**: Seamless navigation from external links

### 🛠 Technical Features
- **BLoC State Management**: Predictable state management with flutter_bloc
- **Supabase Backend**: Real-time database with authentication
- **Image Processing**: Compression, cropping, and optimization
- **File Management**: Multi-file uploads with preview support
- **Timezone Support**: Proper time handling across regions
- **Auto-updates**: Built-in app update notifications
- **Comprehensive Testing**: Integration and unit tests included

## 🏗 Architecture

The app follows a clean, modular architecture:

```
lib/
├── modules/
│   ├── auth/           # Authentication flows
│   ├── chat/           # Messaging system
│   ├── channels/       # Organization discovery
│   ├── posts/          # Content management
│   └── profile/        # User settings
├── services/
│   ├── api/            # Backend integration
│   └── api_repository.dart
└── utils/              # Shared utilities
```

### Key Technologies
- **Flutter 3.9+**: Modern UI framework
- **BLoC Pattern**: Reactive state management
- **Supabase**: Backend-as-a-Service with real-time features
- **Google Fonts**: Beautiful typography with Poppins font family
- **Image Processing**: Advanced media handling capabilities

## 🚀 Getting Started

### Prerequisites
- Flutter SDK 3.9.0 or higher
- Dart SDK
- iOS 12.0+ / Android API 21+
- Supabase project setup

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd mvc_app
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Environment Setup**
   - Copy `.env_qa` and `.env_prod` files with your Supabase credentials
   - Configure deep linking for your domain
   - Copy production and qa versions of Google Services for both android and ios
   - Run with Azul Zulu 17 (OpenJDK 64-Bit Server VM Zulu17 LTS)

4. **Run the app**
   ```bash
   # Development
   flutter run --flavor development -t lib/main_development.dart
   
   # Production
   flutter run --flavor production -t lib/main_production.dart
   ```

### Building for Release

```bash
# iOS
./qa_compile_ios.sh

# Android
flutter build apk --flavor production -t lib/main_production.dart
```

## 📋 Recent Updates (v1.1.19)

- ✅ Native Apple Sign-In integration
- ✅ Emoji reactions system
- ✅ Improved organization management screens
- ✅ Fixed navigation issues and chat behavior
- ✅ Timezone support for global users
- ✅ Message editing and deletion capabilities
- ✅ Pinned posts functionality
- ✅ Advanced search and filtering

## 📊 Amplitude Analytics

All analytics events flow through `AmplitudeService` (`lib/services/amplitude_service.dart`). Users are identified by **username** with `email` and `role` set as user properties on login. Identity is cleared on sign-out.

### Event Reference

| Event | Properties | Source |
|---|---|---|
| `user_signed_in` | `method` (email / apple / google) | `main.dart` auth listener |
| `user_signed_out` | — | `main.dart` auth listener |
| `sign_up` | `method` | `SupabaseApiService.signUp` |
| `sign_up_error` | `error` | `SupabaseApiService.signUp` |
| `login_error` | `method`, `error` | `SupabaseApiService.signIn` / `signInWithProvider` |
| `tab_viewed` | `tab` (home / messages / manage / directory) | `MainScaffold` bottom nav |
| `chat_opened` | `channel_id`, `channel_name`, `organization_id` | `RealChatScreen._navigateToChatView` |
| `chat_closed` | `channel_id`, `channel_name`, `organization_id` | `RealChatScreen._navigateToChatView.then` |
| `dm_chat_opened` | `conversation_id`, `organization_id`, `organization_name` | `DirectMessagesScreen._navigateToChatView` |
| `dm_chat_closed` | `conversation_id`, `organization_id` | `DirectMessagesScreen._navigateToChatView.then` |
| `dm_conversation_started` | `organization_id`, `organization_name`, `role` | `DirectMessagesScreen._startNewConversation` / `_startNewConversationAsAdmin` |
| `dm_conversation_start_error` | `organization_id`, `error`, `role` | `DirectMessagesScreen` — all failure paths |
| `channel_followed` | `organization_id` | `SupabaseApiService.followOrganization` |
| `channel_follow_error` | `organization_id`, `error` | `SupabaseApiService.followOrganization` |
| `channel_unfollowed` | `organization_id` | `SupabaseApiService.unfollowOrganization` |
| `channel_unfollow_error` | `organization_id`, `error` | `SupabaseApiService.unfollowOrganization` |
| `post_reacted` | `post_id`, `emojis` | `SupabaseApiService.upsertPostReaction` |
| `post_reaction_removed` | `post_id` | `SupabaseApiService.removePostReaction` |
| `post_reaction_error` | `post_id`, `error` | `SupabaseApiService` — reaction failure paths |
| `direct_message_sent` | `conversation_id`, `message_type` | `SupabaseApiService.sendDirectMessage` |
| `direct_message_error` | `conversation_id`, `error` | `SupabaseApiService.sendDirectMessage` |
| `profile_updated` | `fields` (list of changed keys) | `SupabaseApiService.updateUserProfile` |
| `profile_screen_tapped` | `item` (edit_profile / account_settings / channels_followed / send_feedback / about / terms / privacy_policy / sign_out) | `SettingsScreen` |
| `feedback_submitted` | `feedback_type`, `has_screenshot` | `SupabaseApiService.submitFeedback` |
| `feedback_error` | `feedback_type`, `error` | `SupabaseApiService.submitFeedback` |
| `badge_updated` | `count`, `total_channels` | `ChatService.updateNotificationBadgeFromChannels` |

## 🧪 Testing

The app includes comprehensive testing:

```bash
# Unit tests
flutter test

# Integration tests
 ./integration_test/run_integration_tests.sh 
```

## 📱 Supported Platforms

- **iOS**: 12.0+
- **Android**: API 21+ (Android 5.0)
- **Web**: Modern browsers (limited features)

## 🤝 Contributing

1. Clone the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is proprietary software. All rights reserved.

---

**Built with ❤️ using Flutter and Supabase**
