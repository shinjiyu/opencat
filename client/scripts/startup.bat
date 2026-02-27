@echo off
setlocal enabledelayedexpansion

echo ==========================================
echo   OpenCat Portable - Startup
echo ==========================================
echo.

set "SCRIPT_DIR=%~dp0"
set "NODE=%SCRIPT_DIR%tools\node\node.exe"
set "APP_DIR=%SCRIPT_DIR%lib\app"
set "CLOUDFLARED=%SCRIPT_DIR%tools\cloudflared\cloudflared.exe"
set "OPENCLAW_PORT=3080"
set "TUNNEL_LOG=%SCRIPT_DIR%cloudflared.log"
set "WATCHDOG_INTERVAL=30"

:: Read token config
set "TMP_OUT=%TEMP%\occ_%RANDOM%.tmp"
"%NODE%" -e "const t=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(t.token)" "%SCRIPT_DIR%token.json" > "%TMP_OUT%"
set /p TOKEN=<"%TMP_OUT%"
"%NODE%" -e "const t=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));const u=new URL(t.proxy_base_url);console.log(u.origin+u.pathname.replace(/\/v1\/?$/,''))" "%SCRIPT_DIR%token.json" > "%TMP_OUT%"
set /p SERVER_BASE=<"%TMP_OUT%"
del "%TMP_OUT%" >nul 2>&1

if "!TOKEN!"=="" (
    echo ERROR: Could not read token from token.json
    pause & exit /b 1
)

:: ---------- Step 1: Kill old instances ----------

echo [1/4] Stopping old instances...
taskkill /im cloudflared.exe /f >nul 2>&1
for /f "tokens=5" %%p in ('netstat -aon 2^>nul ^| findstr ":%OPENCLAW_PORT% " ^| findstr "LISTENING"') do (
    if "%%p" neq "0" (
        echo     Killing PID %%p on port %OPENCLAW_PORT%
        taskkill /pid %%p /f >nul 2>&1
    )
)
timeout /t 1 /nobreak >nul
echo [1/4] Done.
echo.

:: ---------- Step 2: Start OpenClaw ----------

echo [2/4] Starting OpenClaw gateway on port %OPENCLAW_PORT%...

:: Configure gateway for local mode + trusted-proxy access
"%NODE%" "%SCRIPT_DIR%configure-gateway.js" >nul 2>&1
echo     Gateway config OK

> "%SCRIPT_DIR%_run_openclaw.bat" (
    echo @echo off
    echo cd /d "%APP_DIR%"
    echo "%NODE%" openclaw.mjs gateway run --port %OPENCLAW_PORT% --bind loopback --no-color
)
start "OpenClaw" /min cmd /c ""%SCRIPT_DIR%_run_openclaw.bat" > "%SCRIPT_DIR%openclaw.log" 2>&1"

:: Wait for port to be listening (simple netstat check)
echo     Waiting for gateway...
set "READY=0"
for /l %%i in (1,1,30) do (
    if "!READY!"=="0" (
        timeout /t 1 /nobreak >nul
        netstat -an 2>nul | findstr ":%OPENCLAW_PORT% .*LISTENING" >nul 2>&1 && set "READY=1"
    )
)
if "!READY!"=="0" (
    echo     WARN: Gateway not detected within 30s. Check openclaw.log
) else (
    echo     OpenClaw gateway running on ws://127.0.0.1:%OPENCLAW_PORT%
)
echo [2/4] Done.
echo.

:: ---------- Step 3: Start cloudflared ----------

echo [3/4] Starting cloudflared tunnel...
if not exist "%CLOUDFLARED%" (
    echo     WARN: cloudflared not bundled. OpenClaw is local-only.
    goto :show_local_only
)

del "%TUNNEL_LOG%" >nul 2>&1
> "%SCRIPT_DIR%_run_cloudflared.bat" (
    echo @echo off
    echo "%CLOUDFLARED%" tunnel --url http://127.0.0.1:%OPENCLAW_PORT%
)
start "Cloudflared" /min cmd /c ""%SCRIPT_DIR%_run_cloudflared.bat" > "%TUNNEL_LOG%" 2>&1"

echo     Waiting for tunnel URL...
set "TUNNEL_URL="
for /l %%i in (1,1,30) do (
    if "!TUNNEL_URL!"=="" (
        ping -n 2 127.0.0.1 >nul
        for /f "delims=" %%u in ('findstr /r "https://.*trycloudflare\.com" "%TUNNEL_LOG%" 2^>nul') do (
            for %%w in (%%u) do (
                echo %%w | findstr "https://" >nul 2>&1 && set "TUNNEL_URL=%%w"
            )
        )
    )
)

if "!TUNNEL_URL!"=="" (
    echo     WARN: Tunnel URL not detected within 45s. Check cloudflared.log
    echo     If log shows "429 Too Many Requests", Cloudflare quick tunnel is rate-limited; wait a few minutes and run startup again.
    goto :show_local_only
)

:: Clean trailing pipes/spaces from URL
set "TUNNEL_URL=!TUNNEL_URL: =!"
set "TUNNEL_URL=!TUNNEL_URL:|=!"

echo     Tunnel: !TUNNEL_URL!
echo [3/4] Done.
echo.

:: ---------- Step 4: Register tunnel ----------

echo [4/4] Registering tunnel with server...
"%NODE%" -e "const h=require('https');const u=new URL(process.argv[1]+'/api/tunnel');const d=JSON.stringify({tunnel_url:process.argv[2]});const req=h.request(u,{method:'PUT',headers:{'Content-Type':'application/json','Content-Length':Buffer.byteLength(d),'Authorization':'Bearer '+process.argv[3]}},(res)=>{let b='';res.on('data',c=>b+=c);res.on('end',()=>{if(res.statusCode===200){const r=JSON.parse(b);console.log('    OpenClaw URL: '+r.openclaw_url)}else{console.error('    Registration failed: '+b)}})});req.on('error',e=>console.error('    Error: '+e.message));req.write(d);req.end()" "!SERVER_BASE!" "!TUNNEL_URL!" "!TOKEN!"
echo [4/4] Done.
echo.

echo ==========================================
echo   All services running
echo ==========================================
echo.
echo   OpenClaw (tunnel):     !TUNNEL_URL!
echo   OpenClaw (redirect):   !SERVER_BASE!/openclaw?token=!TOKEN!
echo   OpenClaw (local):      http://localhost:%OPENCLAW_PORT%
echo.
echo   This window is the Watchdog monitor.
echo   Do NOT close it -- tunnel auto-recovery depends on it.
echo   To stop everything, run shutdown.bat instead.
echo ==========================================
echo.

title OpenCat Watchdog - !TUNNEL_URL!
goto :watchdog

:show_local_only
echo.
echo ==========================================
echo   OpenClaw running (local only)
echo ==========================================
echo.
echo   OpenClaw (local):      http://localhost:%OPENCLAW_PORT%
echo ==========================================
pause
exit /b 0

:: ===== Watchdog =====
:watchdog
set "FAIL_COUNT=0"
set "CHECK_COUNT=0"

:watchdog_loop
ping -n %WATCHDOG_INTERVAL% 127.0.0.1 >nul
set /a CHECK_COUNT+=1

:: Check cloudflared process alive
tasklist /fi "imagename eq cloudflared.exe" /nh 2>nul | find /i "cloudflared.exe" >nul
if errorlevel 1 (
    echo [%time%] cloudflared process not found. Restarting...
    goto :restart_tunnel
)

:: Check tunnel reachable
"%NODE%" -e "const h=require('https');h.get(process.argv[1],{timeout:10000},r=>{process.exit(r.statusCode>=200&&r.statusCode<500?0:1)}).on('error',()=>process.exit(1))" "!TUNNEL_URL!" >nul 2>&1
if errorlevel 1 (
    set /a FAIL_COUNT+=1
    echo [%time%] Tunnel unreachable ^(!FAIL_COUNT!/3^)
    if !FAIL_COUNT! geq 3 goto :restart_tunnel
) else (
    if !FAIL_COUNT! gtr 0 (
        echo [%time%] Tunnel recovered.
        set "FAIL_COUNT=0"
    )
    echo [%time%] OK ^(check #!CHECK_COUNT!^) - !TUNNEL_URL!
)
goto :watchdog_loop

:restart_tunnel
set "FAIL_COUNT=0"
taskkill /im cloudflared.exe /f >nul 2>&1
timeout /t 1 /nobreak >nul

del "%TUNNEL_LOG%" >nul 2>&1
start "Cloudflared" /min cmd /c ""%SCRIPT_DIR%_run_cloudflared.bat" > "%TUNNEL_LOG%" 2>&1"

set "TUNNEL_URL="
echo [Watchdog %time%] Waiting for new tunnel...
for /l %%i in (1,1,30) do (
    if "!TUNNEL_URL!"=="" (
        ping -n 2 127.0.0.1 >nul
        for /f "delims=" %%u in ('findstr /r "https://.*trycloudflare\.com" "%TUNNEL_LOG%" 2^>nul') do (
            for %%w in (%%u) do (
                echo %%w | findstr "https://" >nul 2>&1 && set "TUNNEL_URL=%%w"
            )
        )
    )
)
if "!TUNNEL_URL!"=="" (
    echo [Watchdog %time%] Failed to get URL. Retry in %WATCHDOG_INTERVAL%s...
    goto :watchdog_loop
)
set "TUNNEL_URL=!TUNNEL_URL: =!"
set "TUNNEL_URL=!TUNNEL_URL:|=!"
echo [Watchdog %time%] New tunnel: !TUNNEL_URL!

"%NODE%" -e "const h=require('https');const u=new URL(process.argv[1]+'/api/tunnel');const d=JSON.stringify({tunnel_url:process.argv[2]});const req=h.request(u,{method:'PUT',headers:{'Content-Type':'application/json','Content-Length':Buffer.byteLength(d),'Authorization':'Bearer '+process.argv[3]}},(res)=>{let b='';res.on('data',c=>b+=c);res.on('end',()=>{if(res.statusCode===200){console.log('[Watchdog] Re-registered OK')}else{console.error('[Watchdog] Failed: '+b)}})});req.on('error',e=>console.error('[Watchdog] Error: '+e.message));req.write(d);req.end()" "!SERVER_BASE!" "!TUNNEL_URL!" "!TOKEN!"
goto :watchdog_loop
