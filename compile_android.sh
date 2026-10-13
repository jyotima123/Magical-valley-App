#!/bin/bash
# Build Development flavor for Android

exec > >(tee -a compile_android.log) 2>&1

export LANG=en_US.UTF-8

echo "🚀 Building Development flavor for Android..."

# Clean and get dependencies
flutter clean
flutter pub get

# Build Android development flavor
flutter build apk --release --flavor development -t lib/main_development.dart

echo "✅ Development APK build complete!"
echo "📱 APK location: build/app/outputs/flutter-apk/app-development-release.apk"

# Open the build directory
open build/app/outputs/flutter-apk/
