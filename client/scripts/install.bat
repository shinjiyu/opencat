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
set "LOG_FILE=%SCRIPT_DIR%install.log"

rem --- Server URL (injected at build time; do not change this placeholder) ---
set "SERVER_URL=https://proxy.example.com"

rem --- Start install log ---
echo [OpenCat Install] %date% %time% > "%LOG_FILE%"
echo Server URL: !SERVER_URL! >> "%LOG_FILE%"

:: Check if already configured (pre-token mode)
if exist "%APP_DIR%\opencat.json" (
    echo [INFO] Config already exists - pre-configured package detected.
    echo [INFO] Skipping token request. Running npm install only.
    echo Pre-configured, skipping token request >> "%LOG_FILE%"
    goto :install_deps
)

:: Check Node exists
if not exist "%NODE%" (
    echo ERROR: Node not found at %NODE%
    echo ERROR: Node not found at %NODE% >> "%LOG_FILE%"
    echo Please re-download the portable package for your platform.
    pause
    exit /b 1
)

echo [1/4] Checking Node...
echo [1/4] Checking Node >> "%LOG_FILE%"
"%NODE%" --version
echo.

:install_deps
echo [2/4] Installing dependencies...
echo [2/4] Installing dependencies >> "%LOG_FILE%"
cd /d "%APP_DIR%"
"%NPM%" install --omit=dev
if errorlevel 1 (
    echo ERROR: npm install failed.
    echo ERROR: npm install failed >> "%LOG_FILE%"
    echo Check your network connection and try again.
    pause
    exit /b 1
)
echo.

:: Skip token if pre-configured
if exist "%APP_DIR%\opencat.json" (
    echo [3/4] Skipped (pre-configured).
    echo [4/4] Skipped (pre-configured).
    goto :done
)

echo [3/4] Requesting Token from server...
echo [INFO] Server URL: !SERVER_URL!
echo [3/4] Requesting Token from server >> "%LOG_FILE%"
for /f %%i in ('powershell -Command "[guid]::NewGuid().ToString()"') do set "INSTALL_ID=%%i"
echo [INFO] Install ID: !INSTALL_ID!
echo Install ID: !INSTALL_ID! >> "%LOG_FILE%"

"%NODE%" -e "const h=require(!SERVER_URL!.startsWith('https')?'https':'http');const url=!SERVER_URL!+'/api/tokens';const data=JSON.stringify({platform:'win-x64',install_id:'!INSTALL_ID!',version:'portable'});const u=new URL(url);const req=h.request(u,{method:'POST',headers:{'Content-Type':'application/json','Content-Length':Buffer.byteLength(data)}},(res)=>{let body='';res.on('data',c=>body+=c);res.on('end',()=>{if(res.statusCode===200){const r=JSON.parse(body);const fs=require('fs');fs.writeFileSync('%SCRIPT_DIR%token.json',body);console.log('Token: '+r.token);console.log('Chat URL: '+r.chat_url)}else{console.error('Failed: '+body);process.exit(1)}})});req.on('error',e=>{console.error('Network error: '+e.message);process.exit(1)});req.write(data);req.end()"
if errorlevel 1 (
    echo ERROR: Failed to get token from server.
    echo ERROR: Failed to get token from server >> "%LOG_FILE%"
    pause
    exit /b 1
)
echo.

echo [4/4] Writing configuration...
echo [4/4] Writing configuration >> "%LOG_FILE%"
"%NODE%" -e "const fs=require('fs');const t=JSON.parse(fs.readFileSync('%SCRIPT_DIR%token.json','utf8'));const cfg={models:{mode:'merge',providers:{proxy:{baseUrl:t.proxy_base_url,apiKey:t.token,api:'openai-completions',models:[{id:'auto',name:'Auto',reasoning:false,input:['text'],contextWindow:128000,maxTokens:4096}]}}}};fs.writeFileSync('%APP_DIR%\\opencat.json',JSON.stringify(cfg,null,2));console.log('Config written.');const html='<html><head><meta http-equiv=\"refresh\" content=\"0;url='+t.chat_url+'\"></head></html>';fs.writeFileSync('%SCRIPT_DIR%open-chat.html',html);console.log('Chat shortcut created: open-chat.html')"
echo Config written successfully >> "%LOG_FILE%"
echo.

:done
echo Installation completed successfully >> "%LOG_FILE%"
echo.
echo ==========================================
echo   Installation complete!
echo.
if exist "%SCRIPT_DIR%open-chat.html" (
    echo   To chat: double-click open-chat.html
    echo   Log file: %LOG_FILE%
) else (
    echo   To chat: open the chat_url in token.json
    echo   Log file: %LOG_FILE%
)
echo ==========================================
pause
