<#
.SYNOPSIS
    Builds a QA release APK (development flavor = QA backend), uploads it to
    Google Drive via rclone, and posts the download link to #qa-builds on Discord.
.PARAMETER NoBuild
    Skip flutter clean / pub get / build and use the existing APK.
#>
param([switch]$NoBuild)

$ErrorActionPreference = 'Stop'

# ── Config ────────────────────────────────────────────────────────────────────
$RCLONE      = 'C:\rclone.exe'
$DRIVE_DIR   = 'gdrive:QA_APKS'
$FLAVOR      = 'development'
$TARGET_FILE = 'lib/main_development.dart'
$APK_OUT     = 'build\app\outputs\flutter-apk\app-arm64-v8a-development-release.apk'
$WEBHOOK     = 'https://discord.com/api/webhooks/1500892918733472007/tjwRkHSQ6WCDnqCguXugTvEk2aIg5JW6BhyoGHKefeFnwyIOo82RQ1n5o8exgzNFb0RW'

# Resolve project root (this script lives in scripts\)
$ROOT      = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
$NOTES_DIR = Join-Path $ROOT 'release_notes'

Set-Location $ROOT

# ── Header ────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '===============================================' -ForegroundColor Cyan
Write-Host '   QA APK Build & Drive Distribution'          -ForegroundColor Cyan
Write-Host '===============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "Flavor  : $FLAVOR  (points to QA backend)"
Write-Host "Target  : $TARGET_FILE"
Write-Host ''

# ── Build ─────────────────────────────────────────────────────────────────────
if (-not $NoBuild) {
    Write-Host '[1/3] Cleaning project...'
    & flutter clean
    if ($LASTEXITCODE -ne 0) { throw 'flutter clean failed' }
    Write-Host ''

    Write-Host '[2/3] Getting dependencies...'
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
    Write-Host ''

    Write-Host '[3/3] Building QA release APK...'
    Write-Host "      flutter build apk --release --flavor $FLAVOR -t $TARGET_FILE --split-per-abi"
    & flutter build apk --release --flavor $FLAVOR -t $TARGET_FILE --split-per-abi
    if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed' }
    Write-Host ''
} else {
    Write-Host 'Skipping build (-NoBuild).' -ForegroundColor Yellow
    Write-Host ''
}

if (-not (Test-Path $APK_OUT)) {
    throw "APK not found at '$APK_OUT'. Run without -NoBuild to compile first."
}

# ── Parse version ─────────────────────────────────────────────────────────────
$versionLine = Get-Content 'pubspec.yaml' |
    Where-Object { $_ -match '^version:\s' } |
    Select-Object -First 1
$versionFull = ($versionLine -replace '^version:\s*', '').Trim()
$parts       = $versionFull -split '\+'
$versionName = $parts[0]
$buildNum    = if ($parts.Count -gt 1) { $parts[1] } else { '?' }

$apkItem = Get-Item $APK_OUT
$sizeMB  = [math]::Round($apkItem.Length / 1MB, 1)

Write-Host "Version : $versionName"
Write-Host "Build # : $buildNum"
Write-Host "APK     : $APK_OUT ($sizeMB MB)"

# ── Release notes ─────────────────────────────────────────────────────────────
$notesFile = Join-Path $NOTES_DIR "$versionName.md"
$hasNotes  = Test-Path $notesFile
if ($hasNotes) {
    Write-Host "Notes   : $notesFile [found]"
} else {
    Write-Host "Notes   : none for v$versionName"
}
Write-Host ''

# ── Upload APK to Google Drive ────────────────────────────────────────────────
$apkFilename  = "mvc-qa-v$versionName-build$buildNum.apk"
$driveTarget  = "$DRIVE_DIR/$apkFilename"

Write-Host "Uploading to Google Drive: $driveTarget ..."
& $RCLONE copyto $APK_OUT $driveTarget --progress
if ($LASTEXITCODE -ne 0) { throw 'rclone upload failed' }
Write-Host ''

Write-Host 'Generating share link...'
$driveLink = (& $RCLONE link $driveTarget) | Select-Object -Last 1
if ($LASTEXITCODE -ne 0) { throw 'rclone link failed' }
Write-Host "Link    : $driveLink"
Write-Host ''

# ── Build Discord message ─────────────────────────────────────────────────────
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine(':rocket: **QA Build Available**')
[void]$sb.AppendLine("**Version:** $versionName  |  **Build:** #$buildNum")
[void]$sb.AppendLine(":inbox_tray: **Download APK:** $driveLink")

if ($hasNotes) {
    $raw = (Get-Content $notesFile -Raw -Encoding UTF8).Trim()

    # Include only the summary bullet list, not the "# Detailed Changes" section
    $detailIdx = $raw.IndexOf('# Detailed Changes')
    if ($detailIdx -gt 0) { $raw = $raw.Substring(0, $detailIdx).TrimEnd() }

    # Discord message cap: stay safely under 2000 chars
    if ($raw.Length -gt 1400) { $raw = $raw.Substring(0, 1397) + '...' }

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine($raw)
}

$msg = $sb.ToString()

# ── Post to Discord (plain JSON — no file attachment) ─────────────────────────
Write-Host 'Posting to Discord...'
$body = [System.Text.Encoding]::UTF8.GetBytes(
    (@{ content = $msg } | ConvertTo-Json -Compress -Depth 2)
)
$req             = [System.Net.WebRequest]::Create($WEBHOOK)
$req.Method      = 'POST'
$req.ContentType = 'application/json; charset=utf-8'
$req.ContentLength = $body.Length
$stream = $req.GetRequestStream()
$stream.Write($body, 0, $body.Length)
$stream.Close()

$resp     = $req.GetResponse()
$httpCode = [int]([System.Net.HttpWebResponse]$resp).StatusCode
$resp.Close()

Write-Host "HTTP $httpCode"
Write-Host ''

if ($httpCode -in 200, 204) {
    Write-Host 'Posted to Discord successfully!' -ForegroundColor Green
} else {
    Write-Warning "Unexpected HTTP $httpCode from Discord."
}

Write-Host ''
Write-Host '===============================================' -ForegroundColor Cyan
Write-Host '   Done!'                                       -ForegroundColor Cyan
Write-Host '===============================================' -ForegroundColor Cyan
Write-Host ''
