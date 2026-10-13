@echo off
setlocal enabledelayedexpansion

REM Build Production flavor for Android (Batch version)
REM Creates both APK and signed AAB for Google Play Store

REM Configuration
set KEYSTORE_PATH=C:\Users\Alisson\Desktop\KeyProdMVC.jks
set KEY_ALIAS=key0
set FLAVOR=production
set TARGET_FILE=lib/main_production.dart

REM Parse command line arguments
set BUILD_APK=1
set BUILD_AAB=1
set KEYSTORE_PASSWORD=
set KEY_PASSWORD=

:parse_args
if "%~1"=="" goto end_parse
if /i "%~1"=="-APKOnly" (
    set BUILD_AAB=0
    shift
    goto parse_args
)
if /i "%~1"=="-AABOnly" (
    set BUILD_APK=0
    shift
    goto parse_args
)
if /i "%~1"=="-KeystorePassword" (
    set KEYSTORE_PASSWORD=%~2
    shift
    shift
    goto parse_args
)
if /i "%~1"=="-KeyPassword" (
    set KEY_PASSWORD=%~2
    shift
    shift
    goto parse_args
)
shift
goto parse_args
:end_parse

REM Display configuration
echo.
echo ======================================
echo Building Production flavor for Android
echo ======================================
echo Configuration:
echo   * Flavor: %FLAVOR%
echo   * Target: %TARGET_FILE%
echo   * Keystore: %KEYSTORE_PATH%
echo   * Key Alias: %KEY_ALIAS%
echo.

REM Determine what to build
if %BUILD_APK%==0 if %BUILD_AAB%==1 (
    echo Building AAB only
) else if %BUILD_APK%==1 if %BUILD_AAB%==0 (
    echo Building APK only
) else (
    echo Building both APK and AAB
)
echo.

REM Check keystore if building AAB
if %BUILD_AAB%==1 (
    if not exist "%KEYSTORE_PATH%" (
        echo ERROR: Keystore file not found at: %KEYSTORE_PATH%
        echo Please ensure the keystore file exists at the specified location.
        pause
        exit /b 1
    )

    REM Get passwords if not provided
    if "!KEYSTORE_PASSWORD!"=="" (
        echo Enter keystore password:
        set /p KEYSTORE_PASSWORD=
    )

    if "!KEY_PASSWORD!"=="" (
        echo Enter key password:
        set /p KEY_PASSWORD=
    )
)

REM Step 1: Clean project
echo.
echo [1/4] Cleaning project...
echo Executing: flutter clean
call flutter clean
if errorlevel 1 (
    echo ERROR: Cleaning project failed
    pause
    exit /b 1
)
echo Cleaning completed successfully
echo.

REM Step 2: Get dependencies
echo [2/4] Getting dependencies...
echo Executing: flutter pub get
call flutter pub get
if errorlevel 1 (
    echo ERROR: Getting dependencies failed
    pause
    exit /b 1
)
echo Dependencies retrieved successfully
echo.

REM Step 3: Build APK (if requested)
if %BUILD_APK%==1 (
    echo [3/4] Building APK...
    echo Executing: flutter build apk --release --flavor %FLAVOR% -t %TARGET_FILE%
    call flutter build apk --release --flavor %FLAVOR% -t %TARGET_FILE%
    if errorlevel 1 (
        echo ERROR: Building APK failed
        pause
        exit /b 1
    )
    echo APK built successfully
    echo APK location: build\app\outputs\flutter-apk\app-%FLAVOR%-release.apk
    echo.
)

REM Step 4: Build signed AAB (if requested)
if %BUILD_AAB%==1 (
    echo [4/4] Building signed AAB...

    REM Set environment variables for signing
    set KEYSTORE_FILE=%KEYSTORE_PATH%
    set KEYSTORE_PASSWORD_ENV=%KEYSTORE_PASSWORD%
    set KEY_ALIAS_ENV=%KEY_ALIAS%
    set KEY_PASSWORD_ENV=%KEY_PASSWORD%

    echo Executing: flutter build appbundle --release --flavor %FLAVOR% -t %TARGET_FILE%
    call flutter build appbundle --release --flavor %FLAVOR% -t %TARGET_FILE%
    if errorlevel 1 (
        echo ERROR: Building AAB failed
        pause
        exit /b 1
    )
    echo AAB built successfully
    echo AAB location: build\app\outputs\bundle\%FLAVOR%Release\app-%FLAVOR%-release.aab
    echo.
)

REM Success message
echo.
echo ======================================
echo SUCCESS: Production build complete!
echo ======================================
echo.

REM Open build directories
if %BUILD_APK%==1 (
    echo Opening APK directory...
    set APK_PATH=build\app\outputs\flutter-apk
    if exist "!APK_PATH!" (
        start "" "!APK_PATH!"
    )
)

if %BUILD_AAB%==1 (
    echo Opening AAB directory...
    set AAB_PATH=build\app\outputs\bundle\%FLAVOR%Release
    if exist "!AAB_PATH!" (
        start "" "!AAB_PATH!"
    )
)

REM Update README.md with latest release notes and Android build version
echo Updating README.md with latest release notes...
call "%~dp0scripts\update_readme_release.bat"
echo Updating README.md Android build version...
python "%~dp0scripts\update_readme_build_version.py" android
echo.

REM Build summary
echo.
echo Build Summary:
if %BUILD_APK%==1 (
    echo   APK: build\app\outputs\flutter-apk\app-%FLAVOR%-release.apk
)
if %BUILD_AAB%==1 (
    echo   AAB: build\app\outputs\bundle\%FLAVOR%Release\app-%FLAVOR%-release.aab
)
echo.

pause
