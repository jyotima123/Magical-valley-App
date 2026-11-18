@echo off
echo Testing Flutter installation...

echo Checking Flutter version:
flutter --version
if %errorlevel% neq 0 (
    echo ERROR: Flutter command not found or not working
    echo Please ensure Flutter is installed and added to your PATH
    pause
    exit /b 1
)

echo.
echo Checking Flutter doctor:
flutter doctor
if %errorlevel% neq 0 (
    echo WARNING: Flutter doctor shows issues
)

echo.
echo Testing flutter clean in current directory:
flutter clean
if %errorlevel% neq 0 (
    echo ERROR: flutter clean failed
    pause
    exit /b 1
)

echo SUCCESS: Flutter is working correctly
pause
