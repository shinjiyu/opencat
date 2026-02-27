@echo off
setlocal enabledelayedexpansion

echo ==========================================
echo   OpenClaw Portable - Install
echo ==========================================
echo.

set "SCRIPT_DIR=%~dp0"
set "NODE=%SCRIPT_DIR%tools\node\node.exe"
set "NPM=%SCRIPT_DIR%tools\node\npm.cmd"
set "OPENCLAW_DIR=%SCRIPT_DIR%lib\openclaw"
set "SERVER_URL=https://proxy.example.com"

:: Check Node exists
if not exist "%NODE%" (
    echo ERROR: Node not found at %NODE%
    echo Please re-download the portable package for your platform.
    pause
    exit /b 1
)

echo [1/4] Checking Node...
"%NODE%" --version
echo.

echo [2/4] Installing dependencies...
cd /d "%OPENCLAW_DIR%"
"%NPM%" install --omit=dev
if errorlevel 1 (
    echo ERROR: npm install failed.
    echo Check your network connection and try again.
    pause
    exit /b 1
)
echo.

echo [3/4] Requesting Token from server...
:: Generate install_id
for /f %%i in ('powershell -Command "[guid]::NewGuid().ToString()"') do set "INSTALL_ID=%%i"

:: Request token via Node script
"%NODE%" -e "const https=require('https');const url='%SERVER_URL%/api/tokens';const data=JSON.stringify({platform:'win-x64',install_id:'%INSTALL_ID%',version:'portable'});const req=https.request(url,{method:'POST',headers:{'Content-Type':'application/json','Content-Length':data.length}},(res)=>{let body='';res.on('data',c=>body+=c);res.on('end',()=>{if(res.statusCode===200){const r=JSON.parse(body);const fs=require('fs');fs.writeFileSync('%SCRIPT_DIR%token.json',body);console.log('Token: '+r.token);console.log('Chat URL: '+r.chat_url)}else{console.error('Failed: '+body);process.exit(1)}})});req.on('error',e=>{console.error('Network error: '+e.message);process.exit(1)});req.write(data);req.end()"
if errorlevel 1 (
    echo ERROR: Failed to get token from server.
    echo Check your network connection and try again.
    pause
    exit /b 1
)
echo.

echo [4/4] Writing configuration...
:: Read token from token.json and write openclaw.json
"%NODE%" -e "const fs=require('fs');const t=JSON.parse(fs.readFileSync('%SCRIPT_DIR%token.json','utf8'));const cfg={models:{mode:'merge',providers:{proxy:{baseUrl:t.proxy_base_url,apiKey:t.token,api:'openai-completions',models:[{id:'auto',name:'Auto',reasoning:false,input:['text'],contextWindow:128000,maxTokens:4096}]}}}};fs.writeFileSync('%OPENCLAW_DIR%\\openclaw.json',JSON.stringify(cfg,null,2));console.log('Config written.');const html='<html><head><meta http-equiv=\"refresh\" content=\"0;url='+t.chat_url+'\"></head></html>';fs.writeFileSync('%SCRIPT_DIR%open-chat.html',html);console.log('Chat shortcut created: open-chat.html')"
echo.

echo ==========================================
echo   Installation complete!
echo.
echo   To chat: double-click open-chat.html
echo   Or open the URL shown above in browser.
echo ==========================================
pause
