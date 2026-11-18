@echo off
REM Build Production flavor for Android

echo Building Production flavor for Android...

REM Clean and get dependencies
echo [1/3] Cleaning project...
flutter clean
if %errorlevel% neq 0 (
    echo ERROR: Flutter clean failed with exit code %errorlevel%
    echo Please check if Flutter is properly installed and accessible
    pause
    exit /b 1
)
echo Clean completed successfully

echo [2/3] Getting dependencies...
flutter pub get
if %errorlevel% neq 0 (
    echo ERROR: Flutter pub get failed with exit code %errorlevel%
    echo Please check your pubspec.yaml file and internet connection
    pause
    exit /b 1
)
echo Dependencies retrieved successfully

echo [3/3] Building Android production flavor...
REM Build Android production flavor
flutter build apk --release --flavor production -t lib/main_production.dart
if %errorlevel% neq 0 (
    echo ERROR: Flutter build failed with exit code %errorlevel%
    echo Please check your Flutter configuration and Android setup
    pause
    exit /b 1
)

echo SUCCESS: Production APK build complete!
echo APK location: build\app\outputs\flutter-apk\app-production-release.apk

REM Open the build directory
start build\app\outputs\flutter-apk\

pause
