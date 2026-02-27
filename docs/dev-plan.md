# 傻瓜版 OpenClaw — 开发计划

基于 [portable-and-offline-deployment.md](./portable-and-offline-deployment.md) 中确认的方案。

---

## 架构回顾

```
┌──────────────────────────────────────────────────────────────┐
│  用户电脑（客户端）                                           │
│                                                              │
│  ┌──────────────┐     install.bat/ps1                        │
│  │ Node (便携)  │ ──→ npm install (装依赖)                   │
│  │ + OpenClaw   │ ──→ POST /api/tokens (要 Token)            │
│  │   (代码/包)  │ ──→ 写入 openclaw.json + 聊天链接          │
│  └──────┬───────┘                                            │
│         │ 运行后                                              │
│         ▼                                                    │
│  openclaw gateway  ──→  LLM 请求带 Token                     │
│                                                              │
│  浏览器 ──→ https://proxy.example.com/chat?token=xxx         │
└──────────────────────────┬───────────────────────────────────┘
                           │ HTTPS
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  服务端                                                       │
│                                                              │
│  ┌─────────────┐   ┌──────────────┐   ┌──────────────────┐  │
│  │  Token API  │   │  LLM 代理    │   │  聊天 Web UI     │  │
│  │  (分配/管理)│   │  (转发+限流) │   │  (仅聊天功能)    │  │
│  └──────┬──────┘   └──────┬───────┘   └──────────────────┘  │
│         │                 │                                  │
│         ▼                 ▼                                  │
│       ┌─────────────────────┐                                │
│       │     数据库 (DB)     │  tokens / usage / quota        │
│       └─────────────────────┘                                │
│                │                                             │
│                ▼                                             │
│       上游 LLM (OpenRouter / Anthropic / OpenAI / ...)       │
└──────────────────────────────────────────────────────────────┘
```

---

## 开发步骤

### Phase 0: 协议设计（CS 协议 + API 接口规范）

**不写代码，只出文档**。后续所有开发以此为合约。

| 接口 | 方向 | 说明 |
|------|------|------|
| `POST /api/tokens` | install 脚本 → 服务端 | 分配新 Token；请求体可含 `platform`、`install_id`、`meta`；返回 `{ token, chat_url, proxy_base_url }` |
| `GET  /api/tokens/:token/status` | 客户端 → 服务端 | 查询 Token 状态（有效/禁用/配额剩余）；可选，用于 install 后校验或客户端健康检查 |
| `POST /v1/chat/completions` | OpenClaw → LLM 代理 | OpenAI 兼容聊天接口；`Authorization: Bearer <token>`；代理校验 Token 后转发上游 LLM |
| `GET  /chat?token=xxx` | 浏览器 → Web UI | 聊天页；从 URL 取 Token，前端请求 `/v1/chat/completions` 时带同一 Token |
| `POST /api/admin/tokens` | 管理后台 → 服务端 | 管理接口：列出/禁用/调整配额/删除 Token（内部使用，需管理员鉴权） |

交付物：

- [ ] **协议文档**：接口 URL、请求/响应格式（JSON Schema 或示例）、错误码、鉴权方式、限流规则
- [ ] **数据模型**：`tokens` 表结构（`token`, `created_at`, `disabled`, `quota_daily`, `usage_today`, `meta` 等）
- [ ] **聊天 WebSocket/SSE 协议**：Web UI 与代理之间的流式响应约定（SSE `text/event-stream` 或 WebSocket）

---

### Phase 1: 服务端 — Token 服务 + 数据库

**目标**：能分配 Token、入库、查询状态。

- [ ] 选型：运行时（Node/Bun/Python）、框架（Express/Fastify/Hono 等）、数据库（SQLite 起步 / PostgreSQL）
- [ ] 实现 `POST /api/tokens`：生成 UUID Token → 写库 → 返回 `{ token, chat_url, proxy_base_url }`
- [ ] 实现 `GET /api/tokens/:token/status`：查库返回状态
- [ ] 实现管理接口 `POST /api/admin/tokens`：列出 / 禁用 / 调整配额
- [ ] 数据库 migration 脚本
- [ ] 基础测试

---

### Phase 2: 服务端 — LLM 代理（转发 + 限流）

**目标**：收到带 Token 的 `/v1/chat/completions` 请求后，校验 → 限流 → 转发上游 LLM → 流式返回。

- [ ] 实现 `POST /v1/chat/completions`：
  - 从 `Authorization: Bearer <token>` 取 Token
  - 查库校验 Token 有效性
  - 检查该 Token 配额/限流（如每日 N 条、每分钟 M 条）
  - 转发到上游 LLM（初期可用 OpenRouter 或 LiteLLM）
  - 流式（SSE）返回给客户端
  - 扣量/计数写库
- [ ] 超限时返回清晰错误（HTTP 429 + 提示信息）
- [ ] 上游 LLM 配置（环境变量：上游 baseUrl、上游 API Key）
- [ ] 基础测试（curl / Postman 模拟请求）

---

### Phase 3: 服务端 — 聊天 Web UI

**目标**：一个简洁的网页聊天界面，只做聊天，不做 OpenClaw 完整配置。

- [ ] 单页应用（HTML + JS，或轻量框架如 Vue/React）
- [ ] 从 URL `?token=xxx` 读取 Token
- [ ] 输入框 → 调用 `/v1/chat/completions`（带 Token）→ 流式显示回复
- [ ] 基本 UI：消息列表、Markdown 渲染、加载状态、错误提示
- [ ] 部署：与代理同域同端口（或同一反向代理下），如 `/chat` 路径
- [ ] 移动端适配（响应式布局）

---

### Phase 4: 客户端 — 打包脚本（按平台打 zip）

**目标**：产出按平台的安装 zip（Node + OpenClaw 代码 + install 脚本）。

- [ ] 打包脚本（如 `scripts/build-portable.sh` 或 `.js`）：
  - 参数：目标平台（`win-x64`、`darwin-arm64`、`darwin-x64`、`linux-x64`）
  - 下载对应平台的 Node 便携版（从 nodejs.org）
  - 复制 OpenClaw 代码/包（不含 `node_modules`）
  - 放入 install 脚本（`install.bat` / `install.ps1` / `install.sh`）
  - 打 zip，输出如 `openclaw-portable-win-x64-<version>.zip`
- [ ] CI 集成（可选：GitHub Actions 产出多平台 zip 并上传到 release/CDN）

---

### Phase 5: 客户端 — install 脚本

**目标**：用户解压后运行 install，完成「装依赖 + 要 Token + 写配置 + 生成聊天链接」。

- [ ] `install.bat`（Windows）/ `install.ps1` / `install.sh`（macOS/Linux）：
  1. 检测包内 Node 可用（`tools/node/node --version`）
  2. 用包内 Node 执行 `npm install --omit=dev`（在 OpenClaw 目录下安装依赖）
  3. 向服务端 `POST /api/tokens` 请求新 Token（用包内 Node 或 curl/PowerShell 发 HTTPS 请求）
  4. 将返回的 Token 写入 `openclaw.json`（设置 `models.providers` 的 `baseUrl` + `apiKey`）
  5. 生成「打开聊天」链接/快捷方式（如 `chat.url` 或 `chat.html` 跳转到 `https://proxy.example.com/chat?token=xxx`）
  6. 输出提示：安装完成、如何启动、聊天链接
- [ ] 错误处理：网络不通、npm install 失败、Token 请求失败等的友好提示
- [ ] 可选：`openclaw.bat` / `openclaw.sh` 启动脚本（设 PATH 并启动 gateway）

---

### Phase 6: 集成测试 + 端到端验证

**目标**：在干净环境下走通全流程。

- [ ] 准备一台干净 Windows（无 Node、无 Git）+ 一台 macOS
- [ ] 全流程：下载 zip → 解压 → 运行 install → Token 分配成功 → 打开聊天链接 → 发消息 → 收到 LLM 回复
- [ ] 验证：Token 限流生效（超限返回 429）；禁用 Token 后无法使用
- [ ] 验证：同一 Token 多设备/多浏览器打开聊天均可用
- [ ] 修复发现的问题

---

### Phase 7: 文档 + 发布

- [ ] 用户文档：下载页说明、install 步骤、常见问题
- [ ] 运维文档：服务端部署、上游 LLM 配置、Token 管理、监控
- [ ] 下载页（openclaw.ai 或独立页面）：按平台提供 zip 下载链接
- [ ] 发布第一批安装包

---

## 依赖关系

```
Phase 0 (协议)
    │
    ├──→ Phase 1 (Token 服务) ──→ Phase 2 (LLM 代理) ──→ Phase 3 (Web UI)
    │                                                          │
    └──→ Phase 4 (打包脚本) ──→ Phase 5 (install 脚本) ────────┘
                                                               │
                                                               ▼
                                                    Phase 6 (集成测试)
                                                               │
                                                               ▼
                                                    Phase 7 (文档+发布)
```

- **Phase 0 必须先完成**（协议是所有 CS 交互的合约）。
- Phase 1~3（服务端）和 Phase 4~5（客户端）可以**并行开发**，因为双方按 Phase 0 的协议各自实现。
- Phase 6 在两边都完成后做集成。

---

## 技术选型建议（可讨论）

| 组件 | 建议 | 理由 |
|------|------|------|
| 服务端运行时 | Node / Bun | 与 OpenClaw 同栈，复用能力 |
| 服务端框架 | Hono / Fastify | 轻量、支持 SSE/流式 |
| 数据库 | SQLite（起步）→ PostgreSQL（规模化） | SQLite 零运维，单文件即可；后期可迁移 |
| LLM 上游 | OpenRouter（初期，一个 Key 多模型） | 国内可直连、有免费模型 |
| Web UI | 单页 HTML + vanilla JS 或 Vue | 只做聊天，越简单越好 |
| 打包脚本 | Shell + Node 脚本 | 跨平台打包，CI 友好 |
