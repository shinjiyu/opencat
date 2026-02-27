@echo off
setlocal
cd /d "%~dp0"

set "GIT_BASH=C:\Program Files\Git\bin\bash.exe"
if not exist "%GIT_BASH%" (
    echo ERROR: Git Bash not found at "%GIT_BASH%"
    echo Please install Git for Windows: https://git-scm.com/download/win
    pause
    exit /b 1
)

echo ==========================================
echo   OpenCat - Build Windows Portable
echo ==========================================
echo.
set "EXTRA="
if defined BUILD_SECRET set "EXTRA= --build-secret %BUILD_SECRET%"
"%GIT_BASH%" -c "./build-portable.sh --platform win-x64 --server-url https://kuroneko.chat/opencat%EXTRA%"
set "EXIT_CODE=%errorlevel%"
echo.
if %EXIT_CODE% equ 0 (
    echo Output directory: %~dp0dist\
    dir /b "%~dp0dist\opencat-portable-win-x64*.zip" 2>nul
) else (
    echo Build failed. exit code: %EXIT_CODE%
)
echo ==========================================
pause
exit /b %EXIT_CODE%
