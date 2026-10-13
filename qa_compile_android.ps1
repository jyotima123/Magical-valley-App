# Build Production flavor for Android (PowerShell version)
# Creates both APK and signed AAB for Google Play Store

param(
    [switch]$APKOnly,
    [switch]$AABOnly,
    [string]$KeystorePassword = '',
    [string]$KeyPassword = ''
)


# Configuration
$KEYSTORE_PATH = 'C:\Users\Alisson\Desktop\KeyProdMVC.jks'
$KEY_ALIAS = 'key0'
$FLAVOR = 'production'
$TARGET_FILE = 'lib/main_production.dart'

# Function to check if keystore exists
function Test-KeystoreExists {
    if (-not (Test-Path $KEYSTORE_PATH)) {
        Write-Host "ERROR: Keystore file not found at: $KEYSTORE_PATH" -ForegroundColor Red
        Write-Host "Please ensure the keystore file exists at the specified location." -ForegroundColor Red
        return $false
    }
    return $true
}

# Function to get passwords securely
function Get-Passwords {
    if ([string]::IsNullOrEmpty($KeystorePassword)) {
        Write-Host "Enter keystore password:" -ForegroundColor Yellow
        $secureKeystorePassword = Read-Host -AsSecureString
        $script:KeystorePassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKeystorePassword))
    }

    if ([string]::IsNullOrEmpty($KeyPassword)) {
        Write-Host "Enter key password:" -ForegroundColor Yellow
        $secureKeyPassword = Read-Host -AsSecureString
        $script:KeyPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKeyPassword))
    }
}

# Function to execute Flutter command with error handling
function Invoke-FlutterCommand {
    param(
        [string]$Command,
        [string]$Description
    )

    Write-Host $Description -ForegroundColor Yellow
    Write-Host "Executing: $Command" -ForegroundColor Gray
    Invoke-Expression $Command

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: $Description failed with exit code $LASTEXITCODE" -ForegroundColor Red
        Write-Host "Command: $Command" -ForegroundColor Red
        return $false
    }

    Write-Host "$Description completed successfully" -ForegroundColor Green
    return $true
}

# Main execution
Write-Host "🚀 Building Production flavor for Android..." -ForegroundColor Green
Write-Host "📋 Configuration:" -ForegroundColor Cyan
Write-Host "   • Flavor: $FLAVOR" -ForegroundColor White
Write-Host "   • Target: $TARGET_FILE" -ForegroundColor White
Write-Host "   • Keystore: $KEYSTORE_PATH" -ForegroundColor White
Write-Host "   • Key Alias: $KEY_ALIAS" -ForegroundColor White

# Determine what to build
$buildAPK = $true
$buildAAB = $true

if ($APKOnly) {
    $buildAAB = $false
    Write-Host "Building APK only" -ForegroundColor Cyan
}
elseif ($AABOnly) {
    $buildAPK = $false
    Write-Host "Building AAB only" -ForegroundColor Cyan
}
else {
    Write-Host "Building both APK and AAB" -ForegroundColor Cyan
}

# Check keystore if building AAB
if ($buildAAB) {
    if (-not (Test-KeystoreExists)) {
        Read-Host "Press Enter to continue"
        exit 1
    }
    Get-Passwords
}

# Step 1: Clean project
if (-not (Invoke-FlutterCommand "flutter clean" "[1/4] Cleaning project...")) {
    Read-Host "Press Enter to continue"
    exit 1
}

# Step 2: Get dependencies
if (-not (Invoke-FlutterCommand "flutter pub get" "[2/4] Getting dependencies...")) {
    Read-Host "Press Enter to continue"
    exit 1
}

# Step 3: Build APK (if requested)
if ($buildAPK) {
    $apkCommand = "flutter build apk --release --flavor $FLAVOR -t $TARGET_FILE"
    if (-not (Invoke-FlutterCommand $apkCommand "[3/4] Building APK...")) {
        Read-Host "Press Enter to continue"
        exit 1
    }
    Write-Host "APK location: build\app\outputs\flutter-apk\app-$FLAVOR-release.apk" -ForegroundColor Cyan
}

# Step 4: Build signed AAB (if requested)
if ($buildAAB) {
    $aabCommand = "flutter build appbundle --release --flavor $FLAVOR -t $TARGET_FILE --keystore=`"$KEYSTORE_PATH`" --store-password=`"$KeystorePassword`" --key-alias=`"$KEY_ALIAS`" --key-password=`"$KeyPassword`""

    if (-not (Invoke-FlutterCommand $aabCommand "[4/4] Building signed AAB...")) {
        Read-Host "Press Enter to continue"
        exit 1
    }
    Write-Host "AAB location: build\app\outputs\bundle\${FLAVOR}Release\app-$FLAVOR-release.aab" -ForegroundColor Cyan
}

# Success message
Write-Host "SUCCESS: Production build complete!" -ForegroundColor Green

# Open build directories
if ($buildAPK) {
    Write-Host "Opening APK directory..." -ForegroundColor Cyan
    $apkPath = "build\app\outputs\flutter-apk"
    if (Test-Path $apkPath) {
        Start-Process $apkPath
    }
}

if ($buildAAB) {
    Write-Host "Opening AAB directory..." -ForegroundColor Cyan
    $aabPath = "build\app\outputs\bundle\${FLAVOR}Release"
    if (Test-Path $aabPath) {
        Start-Process $aabPath
    }
}

Write-Host "`n📋 Build Summary:" -ForegroundColor Green
if ($buildAPK) {
    Write-Host "   APK: build\app\outputs\flutter-apk\app-$FLAVOR-release.apk" -ForegroundColor White
}
if ($buildAAB) {
    Write-Host "   AAB: build\app\outputs\bundle\${FLAVOR}Release\app-$FLAVOR-release.aab" -ForegroundColor White
}

Read-Host "Press Enter to continue"
