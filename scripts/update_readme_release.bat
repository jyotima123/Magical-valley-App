@echo off
REM Updates the "Latest Release" section in README.md
REM with the content of the most recent release_notes/*.md file

python "%~dp0update_readme_release.py"
if errorlevel 1 (
    echo ERROR: Failed to update README.md release section
    exit /b 1
)
