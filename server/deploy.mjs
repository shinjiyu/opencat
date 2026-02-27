import { Client } from 'ssh2';

const SERVER = {
  host: process.env.DEPLOY_HOST ?? '43.156.244.45',
  port: 22,
  username: process.env.DEPLOY_USER ?? 'root',
  password: process.env.DEPLOY_PASSWORD,
};

const COMMANDS = process.argv.includes('--fix-nginx') ? [
  // Add /opencat/openclaw location to nginx.conf
  // First backup, then use sed to insert after the /opencat/health block
  'cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak.$(date +%Y%m%d_%H%M%S)',
  `sed -i '/location \\/opencat\\/health {/,/}/ {
/}/a\\
\\
    location /opencat/openclaw {\\
        proxy_pass http://127.0.0.1:3080/openclaw;\\
        proxy_set_header Host \\$host;\\
        proxy_set_header X-Real-IP \\$remote_addr;\\
        proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;\\
        proxy_set_header X-Forwarded-Proto \\$scheme;\\
    }
}' /etc/nginx/nginx.conf`,
  'nginx -t',
  'systemctl reload nginx',
  'echo "nginx updated and reloaded"',
] : process.argv.includes('--nginx') ? [
  'grep -n "opencat\\|3080" /etc/nginx/nginx.conf',
] : process.argv.includes('--test') ? [
  // === Test Suite ===
  // 1. Health check via public URL
  'echo "=== 1. Health Check ===" && curl -s https://kuroneko.chat/opencat/health',

  // 2. Token allocation (no BUILD_SECRET set so it should work without header)
  'echo "\n=== 2. Allocate Token ===" && curl -s -X POST https://kuroneko.chat/opencat/api/tokens -H "Content-Type: application/json" -d \'{"platform":"win-x64","install_id":"test-deploy-001","version":"2026.2.27"}\'',

  // 3. Check token status (uses a known token from db)
  'echo "\n=== 3. Token Status ===" && TOKEN=$(curl -s -X POST https://kuroneko.chat/opencat/api/tokens -H "Content-Type: application/json" -d \'{"platform":"win-x64","install_id":"test-deploy-002","version":"2026.2.27"}\' | grep -o \'"token":"[^"]*"\' | head -1 | cut -d\\" -f4) && echo "Token: $TOKEN" && curl -s https://kuroneko.chat/opencat/api/tokens/$TOKEN/status',

  // 4. Register tunnel URL
  'echo "\n=== 4. Register Tunnel ===" && TOKEN=$(curl -s -X POST https://kuroneko.chat/opencat/api/tokens -H "Content-Type: application/json" -d \'{"platform":"win-x64","install_id":"test-deploy-003","version":"2026.2.27"}\' | grep -o \'"token":"[^"]*"\' | head -1 | cut -d\\" -f4) && echo "Token: $TOKEN" && curl -s -X PUT https://kuroneko.chat/opencat/api/tunnel -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d \'{"tunnel_url":"https://test-tunnel-12345.trycloudflare.com"}\'',

  // 5. OpenClaw redirect (should 302)
  'echo "\n=== 5. OpenClaw Redirect ===" && TOKEN=$(curl -s -X POST https://kuroneko.chat/opencat/api/tokens -H "Content-Type: application/json" -d \'{"platform":"win-x64","install_id":"test-deploy-004","version":"2026.2.27"}\' | grep -o \'"token":"[^"]*"\' | head -1 | cut -d\\" -f4) && curl -s -X PUT https://kuroneko.chat/opencat/api/tunnel -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d \'{"tunnel_url":"https://test-tunnel-99999.trycloudflare.com"}\' > /dev/null && curl -s -o /dev/null -w "HTTP Status: %{http_code}, Redirect: %{redirect_url}" https://kuroneko.chat/opencat/openclaw?token=$TOKEN',

  // 6. Delete tunnel
  'echo "\n=== 6. Delete Tunnel ===" && TOKEN=$(curl -s -X POST https://kuroneko.chat/opencat/api/tokens -H "Content-Type: application/json" -d \'{"platform":"win-x64","install_id":"test-deploy-005","version":"2026.2.27"}\' | grep -o \'"token":"[^"]*"\' | head -1 | cut -d\\" -f4) && curl -s -X PUT https://kuroneko.chat/opencat/api/tunnel -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d \'{"tunnel_url":"https://test-tunnel-del.trycloudflare.com"}\' > /dev/null && curl -s -o /dev/null -w "DELETE HTTP Status: %{http_code}" -X DELETE https://kuroneko.chat/opencat/api/tunnel -H "Authorization: Bearer $TOKEN"',

  // 7. OpenClaw offline page (no tunnel registered)
  'echo "\n=== 7. OpenClaw Offline ===" && TOKEN=$(curl -s -X POST https://kuroneko.chat/opencat/api/tokens -H "Content-Type: application/json" -d \'{"platform":"win-x64","install_id":"test-deploy-006","version":"2026.2.27"}\' | grep -o \'"token":"[^"]*"\' | head -1 | cut -d\\" -f4) && curl -s -o /dev/null -w "HTTP Status: %{http_code}" https://kuroneko.chat/opencat/openclaw?token=$TOKEN',

  // 8. Chat UI accessible
  'echo "\n=== 8. Chat UI ===" && curl -s -o /dev/null -w "Chat page HTTP Status: %{http_code}" https://kuroneko.chat/opencat/chat',

  // 9. LLM Proxy test (should require token)
  'echo "\n=== 9. LLM Proxy (no auth) ===" && curl -s https://kuroneko.chat/opencat/v1/chat/completions -X POST -H "Content-Type: application/json" -d \'{"model":"glm-4-flash","messages":[{"role":"user","content":"hi"}]}\'',
] : [
  // === Deploy ===
  'if [ -d /var/www/opencat-repo/.git ]; then cd /var/www/opencat-repo && git pull; else git clone https://github.com/shinjiyu/opencat.git /var/www/opencat-repo; fi',
  'cd /var/www/opencat-repo/server && npm install',
  'cp /var/www/opencat/.env /var/www/opencat-repo/server/.env',
  'cp -r /var/www/opencat/data /var/www/opencat-repo/server/data 2>/dev/null; ls -la /var/www/opencat-repo/server/data/',
  'cp -r /var/www/opencat/public/* /var/www/opencat-repo/server/public/ 2>/dev/null; echo "public synced"',
  `cat > /etc/systemd/system/opencat.service << 'SERVICEEOF'
[Unit]
Description=OpenCat Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/var/www/opencat-repo/server
ExecStart=/usr/bin/npx tsx src/index.ts
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
SERVICEEOF`,
  'systemctl daemon-reload && systemctl restart opencat',
  'sleep 2 && systemctl status opencat',
  'curl -s http://127.0.0.1:3080/health || echo "health check failed"',
];

function runCommand(conn, cmd) {
  return new Promise((resolve, reject) => {
    console.log(`\n>>> ${cmd}`);
    conn.exec(cmd, (err, stream) => {
      if (err) return reject(err);
      let output = '';
      stream.on('data', (data) => {
        const text = data.toString();
        process.stdout.write(text);
        output += text;
      });
      stream.stderr.on('data', (data) => {
        const text = data.toString();
        process.stderr.write(text);
        output += text;
      });
      stream.on('close', (code) => {
        resolve({ code, output });
      });
    });
  });
}

async function main() {
  const conn = new Client();

  await new Promise((resolve, reject) => {
    conn.on('ready', resolve);
    conn.on('error', reject);
    conn.connect(SERVER);
  });

  console.log('Connected to server.');

  for (const cmd of COMMANDS) {
    const { code } = await runCommand(conn, cmd);
    if (code !== 0) {
      console.error(`(exit code: ${code})`);
    }
  }

  conn.end();
  console.log('\nDeploy complete.');
}

main().catch((err) => {
  console.error('Deploy failed:', err.message);
  process.exit(1);
});
