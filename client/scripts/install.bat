@echo off
setlocal enabledelayedexpansion

echo ==========================================
echo   OpenCat Portable - Install
echo ==========================================
echo.

set "SCRIPT_DIR=%~dp0"
set "NODE=%SCRIPT_DIR%tools\node\node.exe"
set "NPM=%SCRIPT_DIR%tools\node\npm.cmd"
set "APP_DIR=%SCRIPT_DIR%lib\app"
set "LOG_DIR=%SCRIPT_DIR%logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
set "LOG_FILE=%LOG_DIR%\install.log"

echo [OpenCat Install] %date% %time% > "%LOG_FILE%"

:: ---------- Pre-flight checks ----------

if not exist "%APP_DIR%\opencat.json" (
    echo ERROR: opencat.json not found - this package is not pre-configured.
    echo ERROR: not pre-configured >> "%LOG_FILE%"
    pause & exit /b 1
)

if not exist "%SCRIPT_DIR%token.json" (
    echo ERROR: token.json not found.
    echo ERROR: token.json not found >> "%LOG_FILE%"
    pause & exit /b 1
)

if not exist "%NODE%" (
    echo ERROR: Bundled Node not found at %NODE%
    echo ERROR: Node not found >> "%LOG_FILE%"
    pause & exit /b 1
)

:: ---------- Step 1: Check Node ----------

echo [1/3] Checking Node...
echo [1/3] Checking Node >> "%LOG_FILE%"
"%NODE%" --version
echo.

:: ---------- Step 2: npm install ----------

echo [2/3] Installing dependencies...
echo [2/3] Installing dependencies >> "%LOG_FILE%"
cd /d "%APP_DIR%"
call "%NPM%" install --omit=dev --ignore-scripts
set "NPM_ERR=!errorlevel!"
cd /d "%SCRIPT_DIR%"
if !NPM_ERR! neq 0 (
    echo ERROR: npm install failed.
    echo ERROR: npm install failed >> "%LOG_FILE%"
    pause & exit /b 1
)
echo [2/3] Done.
echo.

:: ---------- Step 3: First-run setup ----------

echo [3/3] Configuring OpenClaw gateway (first-run setup)...
echo [3/3] Configuring gateway >> "%LOG_FILE%"
"%NODE%" "%SCRIPT_DIR%configure-gateway.js"
if !errorlevel! neq 0 (
    echo WARN: Gateway configuration failed. Check configure-gateway.js output.
    echo WARN: configure-gateway failed >> "%LOG_FILE%"
) else (
    echo [3/3] Done.
)
echo.

echo Install completed >> "%LOG_FILE%"

echo ==========================================
echo   Install complete. Starting services...
echo ==========================================
echo.

:: Auto-call startup script
call "%SCRIPT_DIR%startup.bat"
