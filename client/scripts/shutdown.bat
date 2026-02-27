@echo off
setlocal enabledelayedexpansion

echo ==========================================
echo   OpenCat Portable - Shutdown
echo ==========================================
echo.

set "SCRIPT_DIR=%~dp0"
set "NODE=%SCRIPT_DIR%tools\node\node.exe"
set "OPENCLAW_PORT=3080"
set "TOKEN="
set "SERVER_BASE="

:: Read token config
if exist "%SCRIPT_DIR%token.json" call :read_token

:: ---------- Step 1: Deregister tunnel ----------

if not defined TOKEN goto :skip_deregister
if not defined SERVER_BASE goto :skip_deregister

echo [1/3] Deregistering tunnel from server...
"%NODE%" -e "const h=require('https');const u=new URL(process.argv[1]+'/api/tunnel');const req=h.request(u,{method:'DELETE',headers:{'Authorization':'Bearer '+process.argv[2]}},r=>{r.resume();r.on('end',()=>{console.log(r.statusCode===204?'    Tunnel deregistered.':'    Response: '+r.statusCode);process.exit(0)})});req.on('error',e=>{console.error('    Error:',e.message);process.exit(0)});req.end()" "!SERVER_BASE!" "!TOKEN!"
echo [1/3] Done.
echo.
goto :step2

:skip_deregister
echo [1/3] Skipped (no token config).
echo.

:: ---------- Step 2: Stop cloudflared ----------

:step2
echo [2/3] Stopping cloudflared...
taskkill /im cloudflared.exe /f >nul 2>&1
echo     Done.
echo [2/3] Done.
echo.

:: ---------- Step 3: Stop OpenClaw ----------

echo [3/3] Stopping OpenClaw on port %OPENCLAW_PORT%...
set "KILLED=0"
for /f "tokens=5" %%p in ('netstat -aon 2^>nul ^| findstr ":%OPENCLAW_PORT% " ^| findstr "LISTENING"') do (
    if "%%p" neq "0" (
        echo     Killing PID %%p
        taskkill /pid %%p /f >nul 2>&1
        set "KILLED=1"
    )
)
if "!KILLED!"=="0" (
    echo     OpenClaw is not running on port %OPENCLAW_PORT%.
) else (
    echo     OpenClaw stopped.
)
echo [3/3] Done.
echo.

:: ---------- Cleanup ----------

del "%SCRIPT_DIR%_run_openclaw.bat" >nul 2>&1
del "%SCRIPT_DIR%_run_cloudflared.bat" >nul 2>&1

echo ==========================================
echo   All services stopped.
echo ==========================================
echo.
pause
exit /b 0

:: ====== Subroutine: read token ======
:read_token
set "TMP_OUT=%TEMP%\occ_%RANDOM%.tmp"
"%NODE%" -e "const t=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(t.token)" "%SCRIPT_DIR%token.json" > "%TMP_OUT%" 2>nul
set /p TOKEN=<"%TMP_OUT%"
"%NODE%" -e "const t=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));const u=new URL(t.proxy_base_url);console.log(u.origin+u.pathname.replace(/\/v1\/?$/,''))" "%SCRIPT_DIR%token.json" > "%TMP_OUT%" 2>nul
set /p SERVER_BASE=<"%TMP_OUT%"
del "%TMP_OUT%" >nul 2>&1
exit /b 0
