#!/bin/bash
# Build production flavor

export LANG=en_US.UTF-8

echo "🚀 Building Production flavor for iOS..."

# Clean and regenerate dependencies (also regenerates ios/Flutter/Generated.xcconfig)
flutter clean
flutter pub get

# Install pods before building so Xcode finds all dependencies
cd ios && pod install && cd ..

mkdir -p build/ios/archive

# Pre-build Flutter framework so Xcode 26+ ScanDependencies can resolve
# Flutter/Flutter.h before any build phase scripts run. --no-codesign avoids
# interfering with the archive's own signing step.
flutter build ios --release --flavor production --no-codesign

# Archive — xcode_backend.sh is invoked automatically via Xcode build phases.
xcodebuild archive \
  -workspace ios/Runner.xcworkspace \
  -scheme production \
  -configuration Release-production \
  -archivePath build/ios/archive/Runner-Production.xcarchive \
  -destination 'generic/platform=iOS' \
  COMPILER_INDEX_STORE_ENABLE=NO

# Update README.md with latest release notes and iOS build version
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "📝 Updating README.md with latest release notes..."
python3 "$SCRIPT_DIR/scripts/update_readme_build_version.py" ios

echo "✅ Production build complete!"
echo "📱 Opening archive in Xcode..."

# Open the archive in Xcode for distribution
open -a Xcode build/ios/archive/Runner-Production.xcarchive
