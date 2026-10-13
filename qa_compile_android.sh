#!/bin/bash
# Build Production flavor for Android

export LANG=en_US.UTF-8

echo "🚀 Building Production flavor for Android..."

# Clean and get dependencies
flutter clean
flutter pub get

# Build Android production flavor
flutter build apk --release --flavor production -t lib/main_production.dart

echo "✅ Production APK build complete!"
echo "📱 APK location: build/app/outputs/flutter-apk/app-production-release.apk"

# Open the build directory
open build/app/outputs/flutter-apk/
