@echo off
REM Build Development flavor for Android

echo 🚀 Building Development flavor for Android...

REM Clean and get dependencies
echo 📦 Cleaning project...
flutter clean
if %errorlevel% neq 0 (
    echo ❌ Flutter clean failed!
    pause
    exit /b 1
)

echo 📦 Getting dependencies...
flutter pub get
if %errorlevel% neq 0 (
    echo ❌ Flutter pub get failed!
    pause
    exit /b 1
)

echo 🔨 Building Android development flavor...
REM Build Android development flavor
flutter build apk --release --flavor development -t lib/main_development.dart
if %errorlevel% neq 0 (
    echo ❌ Flutter build failed!
    pause
    exit /b 1
)

echo ✅ Development APK build complete!
echo 📱 APK location: build\app\outputs\flutter-apk\app-development-release.apk

REM Open the build directory
start build\app\outputs\flutter-apk\

pause
