@echo off
echo Testing basic Flutter commands...

echo.
echo Running: flutter --version
flutter --version
echo Exit code: %errorlevel%

echo.
echo Running: flutter doctor --version
flutter doctor --version
echo Exit code: %errorlevel%

echo.
echo Running: flutter clean --verbose
flutter clean --verbose
echo Exit code: %errorlevel%

echo.
echo Test completed.
pause
