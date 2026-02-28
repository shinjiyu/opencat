const fs = require('fs');
const path = require('path');

const homedir = process.env.USERPROFILE || process.env.HOME || require('os').homedir();
const configPath = path.join(homedir, '.openclaw', 'openclaw.json');
// Script is run from portable root: node "<bundle>/configure-gateway.js" → argv[1] = script path
const scriptDir = path.dirname(process.argv[1] || '.');
const tokenPath = path.join(scriptDir, 'token.json');

let c = {};
try { c = JSON.parse(fs.readFileSync(configPath, 'utf8')); } catch (e) {}

// Gateway only reads ~/.openclaw/openclaw.json; bundle's lib/app/opencat.json is NOT loaded.
// So we must write the Kuroneko proxy provider into user config from token.json.
let tokenJson = {};
try { tokenJson = JSON.parse(fs.readFileSync(tokenPath, 'utf8')); } catch (e) {}
const proxyBase = tokenJson.proxy_base_url || tokenJson.proxyBaseUrl || '';
const apiKey = tokenJson.token || '';
if (proxyBase && apiKey) {
  if (!c.models) c.models = {};
  if (!c.models.providers) c.models.providers = {};
  c.models.providers.proxy = {
    baseUrl: proxyBase,
    apiKey,
    api: 'openai-completions',
    models: [{ id: 'auto', name: 'Auto', reasoning: false, input: ['text'], contextWindow: 128000, maxTokens: 4096 }]
  };
  if (c.models.mode !== 'replace') c.models.mode = 'merge';
}

if (!c.gateway) c.gateway = {};
c.gateway.mode = 'local';

c.gateway.auth = { mode: 'none' };
c.gateway.trustedProxies = ['127.0.0.1', '::1'];

if (!c.gateway.controlUi) c.gateway.controlUi = {};
c.gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback = true;
c.gateway.controlUi.dangerouslyDisableDeviceAuth = true;
c.gateway.controlUi.allowInsecureAuth = true;

// Prefer Kuroneko proxy for chat (faster than local Ollama 32B)
if (!c.agents) c.agents = {};
if (!c.agents.defaults) c.agents.defaults = {};
if (!c.agents.defaults.model) c.agents.defaults.model = {};
c.agents.defaults.model.primary = 'proxy/auto';

fs.mkdirSync(path.dirname(configPath), { recursive: true });
fs.writeFileSync(configPath, JSON.stringify(c, null, 2));
console.log('OK');
