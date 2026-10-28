#!/bin/bash
# Build Development flavor for iOS

exec > >(tee -a compile_ios.log) 2>&1

export LANG=en_US.UTF-8

echo "🚀 Building Development flavor for iOS..."

# Clean and regenerate dependencies (also regenerates ios/Flutter/Generated.xcconfig)
flutter clean
flutter pub get

# Install pods before building so Xcode finds all dependencies
cd ios && pod install && cd ..

mkdir -p build/ios/archive

# Pre-build Flutter framework so Xcode 26+ ScanDependencies can resolve
# Flutter/Flutter.h before any build phase scripts run. --no-codesign avoids
# interfering with the archive's own signing step.
flutter build ios --release --flavor development --no-codesign

# Archive — xcode_backend.sh is invoked automatically via Xcode build phases.
xcodebuild archive \
  -workspace ios/Runner.xcworkspace \
  -scheme development \
  -configuration Release-development \
  -archivePath build/ios/archive/Runner-Development.xcarchive \
  -destination 'generic/platform=iOS' \
  COMPILER_INDEX_STORE_ENABLE=NO

echo "✅ Development build complete!"
echo "📱 Opening archive in Xcode..."

# Open the archive in Xcode for distribution
open -a Xcode build/ios/archive/Runner-Development.xcarchive

