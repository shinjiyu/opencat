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
set "CLOUDFLARED=%SCRIPT_DIR%tools\cloudflared\cloudflared.exe"
set "LOG_FILE=%SCRIPT_DIR%install.log"
set "OPENCLAW_PORT=3080"

rem --- Start install log ---
echo [OpenCat Install] %date% %time% > "%LOG_FILE%"

:: Must be a pre-configured package
if not exist "%APP_DIR%\opencat.json" (
    echo ERROR: This package is not pre-configured.
    echo ERROR: not pre-configured >> "%LOG_FILE%"
    echo Please use an officially distributed package.
    pause
    exit /b 1
)

if not exist "%SCRIPT_DIR%token.json" (
    echo ERROR: token.json not found.
    echo ERROR: token.json not found >> "%LOG_FILE%"
    pause
    exit /b 1
)

if not exist "%NODE%" (
    echo ERROR: Node not found at %NODE%
    echo ERROR: Node not found >> "%LOG_FILE%"
    pause
    exit /b 1
)

:: Read token and server URL from token.json
for /f "usebackq delims=" %%a in (`"%NODE%" -e "const t=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(t.token)" "%SCRIPT_DIR%token.json"`) do set "TOKEN=%%a"
for /f "usebackq delims=" %%a in (`"%NODE%" -e "const t=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(t.chat_url)" "%SCRIPT_DIR%token.json"`) do set "CHAT_URL=%%a"
for /f "usebackq delims=" %%a in (`"%NODE%" -e "const t=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));const u=new URL(t.chat_url);console.log(u.origin+u.pathname.replace(/\/chat$/,''))" "%SCRIPT_DIR%token.json"`) do set "SERVER_BASE=%%a"

echo [1/5] Checking Node...
echo [1/5] Checking Node >> "%LOG_FILE%"
"%NODE%" --version
echo.

echo [2/5] Installing dependencies...
echo [2/5] Installing dependencies >> "%LOG_FILE%"
cd /d "%APP_DIR%"
call "%NPM%" install --omit=dev --ignore-scripts
set "NPM_ERR=!errorlevel!"
cd /d "%SCRIPT_DIR%"
if !NPM_ERR! neq 0 (
    echo ERROR: npm install failed.
    echo ERROR: npm install failed >> "%LOG_FILE%"
    pause
    exit /b 1
)
echo [2/5] Done.
echo.

echo [3/5] Starting OpenClaw...
echo [3/5] Starting OpenClaw >> "%LOG_FILE%"
start "OpenClaw" cmd /c "cd /d \"%APP_DIR%\" && \"%NPM%\" start"
echo     Waiting for OpenClaw to start...
timeout /t 3 /nobreak >nul
echo [3/5] Done.
echo.

echo [4/5] Starting tunnel...
echo [4/5] Starting tunnel >> "%LOG_FILE%"
if not exist "%CLOUDFLARED%" (
    echo WARN: cloudflared not found at %CLOUDFLARED%
    echo WARN: cloudflared not found >> "%LOG_FILE%"
    echo     Skipping tunnel. You can manually set up a tunnel later.
    goto :show_result
)

set "TUNNEL_LOG=%SCRIPT_DIR%cloudflared.log"
start "Cloudflared" cmd /c "\"%CLOUDFLARED%\" tunnel --url http://127.0.0.1:%OPENCLAW_PORT% > \"%TUNNEL_LOG%\" 2>&1"
echo     Waiting for tunnel URL...

set "TUNNEL_URL="
set "RETRY=0"
:wait_tunnel
if !RETRY! geq 30 goto :tunnel_timeout
timeout /t 1 /nobreak >nul
set /a RETRY+=1
for /f "usebackq tokens=*" %%a in (`"%NODE%" -e "const fs=require('fs');try{const l=fs.readFileSync(process.argv[1],'utf8');const m=l.match(/https:\/\/[a-zA-Z0-9-]+\.trycloudflare\.com/);if(m)console.log(m[0])}catch(e){}" "%TUNNEL_LOG%"`) do set "TUNNEL_URL=%%a"
if "!TUNNEL_URL!"=="" goto :wait_tunnel

echo     Tunnel URL: !TUNNEL_URL!
echo Tunnel URL: !TUNNEL_URL! >> "%LOG_FILE%"
echo [4/5] Done.
echo.

echo [5/5] Registering tunnel with server...
echo [5/5] Registering tunnel >> "%LOG_FILE%"
"%NODE%" -e "const h=require('https');const u=new URL(process.argv[1]+'/api/tunnel');const d=JSON.stringify({tunnel_url:process.argv[2]});const req=h.request(u,{method:'PUT',headers:{'Content-Type':'application/json','Content-Length':Buffer.byteLength(d),'Authorization':'Bearer '+process.argv[3]}},(res)=>{let b='';res.on('data',c=>b+=c);res.on('end',()=>{if(res.statusCode===200){const r=JSON.parse(b);console.log('Registered. OpenClaw URL: '+r.openclaw_url)}else{console.error('Registration failed: '+b)}})});req.on('error',e=>console.error('Error: '+e.message));req.write(d);req.end()" "!SERVER_BASE!" "!TUNNEL_URL!" "!TOKEN!"
echo [5/5] Done.
echo.
goto :show_result

:tunnel_timeout
echo WARN: Could not detect tunnel URL within 30 seconds.
echo WARN: tunnel timeout >> "%LOG_FILE%"
echo     Check %TUNNEL_LOG% for details.
echo.

:show_result
echo Installation completed successfully >> "%LOG_FILE%"
echo.
echo ==========================================
echo   Installation complete!
echo ==========================================
echo.
echo   1. Remote Chat (server proxy):
echo      %CHAT_URL%
echo.
if defined TUNNEL_URL (
    echo   2. Local OpenClaw via tunnel:
    echo      !TUNNEL_URL!
    echo.
    echo      Or via kuroneko redirect:
    echo      !SERVER_BASE!/openclaw?token=!TOKEN!
) else (
    echo   2. Local OpenClaw (this machine only):
    echo      http://127.0.0.1:%OPENCLAW_PORT%
)
echo.
echo ==========================================
pause
