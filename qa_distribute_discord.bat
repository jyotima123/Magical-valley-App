@echo off
REM ================================================================
REM  qa_distribute_discord.bat
REM  Builds a QA release APK (development flavor = QA backend,
REM  release mode) and posts it to #qa-builds on Discord.
REM
REM  Usage:
REM    qa_distribute_discord.bat           - full build + upload
REM    qa_distribute_discord.bat -NoBuild  - upload existing APK
REM ================================================================

powershell -NoProfile -ExecutionPolicy Bypass ^
    -File "%~dp0scripts\qa_distribute_discord.ps1" %*

if errorlevel 1 (
    echo.
    echo ERROR: Script failed. See output above.
)

pause
