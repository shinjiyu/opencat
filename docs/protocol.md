# OpenClaw Portable — CS 协议规范

> **版本**: 1.0.0  
> **状态**: 草案  
> **约束**: 客户端（install 脚本、OpenClaw 运行时）和服务端（Token 服务、LLM 代理、Web UI）的所有交互**必须严格遵守本协议**。任何修改须先更新本文档并通知双方。

---

## 1. 总览

```
客户端                                     服务端
──────                                     ──────
install 脚本  ── POST /api/tokens ──────→  Token 服务（分配 + 入库）
OpenClaw CLI  ── POST /v1/chat/completions → LLM 代理（校验 + 限流 + 转发）
浏览器        ── GET  /chat?token=xxx ───→  Web UI（聊天页面）
浏览器 (JS)   ── POST /v1/chat/completions → LLM 代理（同上）
管理员        ── /api/admin/* ───────────→  管理接口（内部使用）
```

**传输层**：全部使用 **HTTPS**（端口 443）。开发环境可用 HTTP。

**编码**：所有请求/响应体为 **JSON**（`Content-Type: application/json`），除流式响应使用 **SSE**（`Content-Type: text/event-stream`）。

**字符集**：UTF-8。

---

## 2. 鉴权

### 2.1 用户 Token（Bearer Token）

- 由 `POST /api/tokens` 分配，格式为 **`ocp_` + 32 位随机 hex**（共 36 字符），例如 `ocp_a1b2c3d4e5f6...`。
- 客户端在所有 LLM 代理请求中通过以下方式之一携带 Token：
  - **HTTP Header**（推荐）：`Authorization: Bearer ocp_xxx`
  - **URL 参数**（仅 Web UI 打开页面时）：`?token=ocp_xxx`
- 服务端必须同时支持两种方式；Header 优先于 URL 参数。

### 2.2 管理员鉴权

- 管理接口（`/api/admin/*`）使用独立的 **Admin Secret**，通过 Header 传递：`X-Admin-Secret: <secret>`。
- Admin Secret 在服务端环境变量 `ADMIN_SECRET` 中配置。

---

## 3. 接口定义

### 3.1 `POST /api/tokens` — 分配新 Token

**用途**：install 脚本在用户电脑上调用，请求分配一个新 Token。

**请求**：

```http
POST /api/tokens HTTP/1.1
Content-Type: application/json

{
  "platform": "win-x64",          // 必填: win-x64 | darwin-arm64 | darwin-x64 | linux-x64
  "install_id": "uuid-string",    // 必填: 客户端本地生成的安装实例 UUID
  "version": "2026.2.27",         // 必填: OpenClaw 版本
  "meta": {                       // 可选: 额外信息
    "hostname": "USER-PC",
    "label": "张三的电脑"
  }
}
```

**成功响应**（`200 OK`）：

```json
{
  "token": "ocp_a1b2c3d4e5f67890a1b2c3d4e5f67890",
  "chat_url": "https://proxy.example.com/chat?token=ocp_a1b2c3d4e5f67890a1b2c3d4e5f67890",
  "proxy_base_url": "https://proxy.example.com/v1",
  "quota": {
    "daily_limit": 100,
    "monthly_limit": 3000
  },
  "created_at": "2026-02-27T10:00:00Z"
}
```

**错误响应**：

| HTTP 状态码 | `error.code` | 说明 |
|-------------|--------------|------|
| 400 | `INVALID_REQUEST` | 缺少必填字段或格式错误 |
| 429 | `RATE_LIMITED` | Token 分配频率过高（同一 IP 短时间内请求过多） |
| 503 | `SERVICE_UNAVAILABLE` | 服务暂不可用 |

错误响应格式：

```json
{
  "error": {
    "code": "INVALID_REQUEST",
    "message": "Missing required field: platform"
  }
}
```

---

### 3.2 `GET /api/tokens/:token/status` — 查询 Token 状态

**用途**：客户端可选调用，检查 Token 是否有效、查看剩余配额。

**请求**：

```http
GET /api/tokens/ocp_a1b2c3d4e5f67890a1b2c3d4e5f67890/status HTTP/1.1
```

**成功响应**（`200 OK`）：

```json
{
  "token": "ocp_a1b2c3d4e5f67890a1b2c3d4e5f67890",
  "status": "active",
  "quota": {
    "daily_limit": 100,
    "daily_used": 12,
    "daily_remaining": 88,
    "monthly_limit": 3000,
    "monthly_used": 156,
    "monthly_remaining": 2844
  },
  "created_at": "2026-02-27T10:00:00Z"
}
```

**`status` 枚举值**：

| 值 | 说明 |
|----|------|
| `active` | 正常可用 |
| `disabled` | 已禁用（管理员操作） |
| `quota_exceeded` | 配额已用尽 |

**错误响应**：

| HTTP 状态码 | `error.code` | 说明 |
|-------------|--------------|------|
| 404 | `TOKEN_NOT_FOUND` | Token 不存在 |

---

### 3.3 `POST /v1/chat/completions` — LLM 聊天（OpenAI 兼容）

**用途**：OpenClaw 或 Web UI 发起聊天请求；代理校验 Token 后转发上游 LLM。

**请求**（与 OpenAI Chat Completions API 兼容）：

```http
POST /v1/chat/completions HTTP/1.1
Content-Type: application/json
Authorization: Bearer ocp_a1b2c3d4e5f67890a1b2c3d4e5f67890

{
  "model": "auto",
  "messages": [
    { "role": "system", "content": "You are a helpful assistant." },
    { "role": "user", "content": "Hello!" }
  ],
  "stream": true,
  "temperature": 0.7,
  "max_tokens": 2048
}
```

**字段说明**：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `model` | string | 是 | 模型标识；`"auto"` 由代理选择默认模型；也可指定如 `"gpt-4o"`、`"claude-sonnet-4-5"`（代理映射到上游） |
| `messages` | array | 是 | 消息数组，格式与 OpenAI 一致 |
| `stream` | boolean | 否 | 是否流式返回；默认 `true` |
| `temperature` | number | 否 | 温度参数 |
| `max_tokens` | number | 否 | 最大输出 token 数 |

**model 映射规则**：

- `"auto"` → 代理配置的默认模型
- 其他值 → 代理在上游 provider（如 OpenRouter）中查找对应模型；找不到则返回 400

**非流式响应**（`stream: false`，`200 OK`）：

```json
{
  "id": "chatcmpl-xxx",
  "object": "chat.completion",
  "created": 1740650000,
  "model": "openrouter/deepseek/deepseek-chat:free",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello! How can I help you?"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 20,
    "completion_tokens": 8,
    "total_tokens": 28
  }
}
```

**流式响应**（`stream: true`，`200 OK`，`Content-Type: text/event-stream`）：

```
data: {"id":"chatcmpl-xxx","object":"chat.completion.chunk","created":1740650000,"model":"openrouter/deepseek/deepseek-chat:free","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}

data: {"id":"chatcmpl-xxx","object":"chat.completion.chunk","created":1740650000,"model":"openrouter/deepseek/deepseek-chat:free","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

data: {"id":"chatcmpl-xxx","object":"chat.completion.chunk","created":1740650000,"model":"openrouter/deepseek/deepseek-chat:free","choices":[{"index":0,"delta":{"content":"!"},"finish_reason":null}]}

data: {"id":"chatcmpl-xxx","object":"chat.completion.chunk","created":1740650000,"model":"openrouter/deepseek/deepseek-chat:free","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```

**SSE 格式规则**：
- 每行以 `data: ` 开头，后跟 JSON 或 `[DONE]`
- 每条消息后跟一个空行（`\n\n`）
- 流结束时发送 `data: [DONE]\n\n`

**错误响应**：

| HTTP 状态码 | `error.code` | 说明 |
|-------------|--------------|------|
| 401 | `UNAUTHORIZED` | Token 缺失或无效 |
| 403 | `TOKEN_DISABLED` | Token 已被禁用 |
| 429 | `QUOTA_EXCEEDED` | 配额已用尽（日/月限额） |
| 429 | `RATE_LIMITED` | 请求频率过高（如每分钟超限） |
| 400 | `INVALID_REQUEST` | 请求格式错误（缺 messages 等） |
| 400 | `MODEL_NOT_FOUND` | 请求的 model 不在代理支持列表中 |
| 502 | `UPSTREAM_ERROR` | 上游 LLM 返回错误 |
| 504 | `UPSTREAM_TIMEOUT` | 上游 LLM 超时 |

错误响应格式（与 OpenAI 兼容）：

```json
{
  "error": {
    "code": "QUOTA_EXCEEDED",
    "message": "Daily quota exceeded. Resets at 00:00 UTC.",
    "type": "insufficient_quota"
  }
}
```

---

### 3.4 `GET /chat` — 聊天 Web UI 页面

**用途**：浏览器打开聊天页面。

**请求**：

```http
GET /chat?token=ocp_xxx HTTP/1.1
```

**行为**：
- 返回聊天页面 HTML（`Content-Type: text/html`）
- 前端 JS 从 URL `?token=` 参数读取 Token
- 前端调用 `POST /v1/chat/completions` 时在 Header 中带 `Authorization: Bearer <token>`
- Token 缺失时页面显示「请从安装包中打开聊天链接」

---

### 3.5 `GET /v1/models` — 可用模型列表

**用途**：OpenClaw 或 Web UI 查询当前代理支持的模型。

**请求**：

```http
GET /v1/models HTTP/1.1
Authorization: Bearer ocp_xxx
```

**成功响应**（`200 OK`）：

```json
{
  "object": "list",
  "data": [
    {
      "id": "auto",
      "object": "model",
      "owned_by": "proxy"
    },
    {
      "id": "deepseek-chat",
      "object": "model",
      "owned_by": "deepseek"
    },
    {
      "id": "claude-sonnet-4-5",
      "object": "model",
      "owned_by": "anthropic"
    }
  ]
}
```

---

### 3.6 管理接口 `/api/admin/*`

**鉴权**：所有管理接口需 `X-Admin-Secret` Header。

#### 3.6.1 `GET /api/admin/tokens` — 列出所有 Token

**请求**：

```http
GET /api/admin/tokens?page=1&limit=20&status=active HTTP/1.1
X-Admin-Secret: <secret>
```

**响应**（`200 OK`）：

```json
{
  "tokens": [
    {
      "token": "ocp_a1b2...",
      "status": "active",
      "platform": "win-x64",
      "install_id": "uuid-xxx",
      "quota": { "daily_limit": 100, "daily_used": 12, "monthly_limit": 3000, "monthly_used": 156 },
      "created_at": "2026-02-27T10:00:00Z",
      "last_used_at": "2026-02-27T15:30:00Z"
    }
  ],
  "total": 42,
  "page": 1,
  "limit": 20
}
```

#### 3.6.2 `PATCH /api/admin/tokens/:token` — 修改 Token

**请求**：

```http
PATCH /api/admin/tokens/ocp_a1b2... HTTP/1.1
X-Admin-Secret: <secret>
Content-Type: application/json

{
  "status": "disabled",
  "quota": {
    "daily_limit": 50
  }
}
```

可修改字段：`status`（`active` | `disabled`）、`quota.daily_limit`、`quota.monthly_limit`。

**响应**（`200 OK`）：返回修改后的完整 Token 对象。

#### 3.6.3 `DELETE /api/admin/tokens/:token` — 删除 Token

**请求**：

```http
DELETE /api/admin/tokens/ocp_a1b2... HTTP/1.1
X-Admin-Secret: <secret>
```

**响应**（`204 No Content`）。

---

## 4. 数据模型

### 4.1 `tokens` 表

| 字段 | 类型 | 说明 |
|------|------|------|
| `token` | TEXT PRIMARY KEY | Token 值（`ocp_` + 32 hex） |
| `status` | TEXT NOT NULL DEFAULT 'active' | `active` / `disabled` |
| `platform` | TEXT NOT NULL | `win-x64` / `darwin-arm64` / `darwin-x64` / `linux-x64` |
| `install_id` | TEXT NOT NULL | 客户端安装实例 UUID |
| `version` | TEXT | OpenClaw 版本号 |
| `daily_limit` | INTEGER NOT NULL DEFAULT 100 | 每日请求上限 |
| `monthly_limit` | INTEGER NOT NULL DEFAULT 3000 | 每月请求上限 |
| `meta` | TEXT | JSON 格式的额外信息 |
| `created_at` | TEXT NOT NULL | ISO 8601 创建时间 |
| `last_used_at` | TEXT | ISO 8601 最后使用时间 |

### 4.2 `usage` 表

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | INTEGER PRIMARY KEY AUTOINCREMENT | 自增 ID |
| `token` | TEXT NOT NULL | 关联的 Token |
| `date` | TEXT NOT NULL | 日期（`YYYY-MM-DD`，UTC） |
| `request_count` | INTEGER NOT NULL DEFAULT 0 | 当日请求数 |
| `prompt_tokens` | INTEGER NOT NULL DEFAULT 0 | 当日 prompt token 数 |
| `completion_tokens` | INTEGER NOT NULL DEFAULT 0 | 当日 completion token 数 |

**唯一约束**：`(token, date)` 联合唯一。

---

## 5. 限流规则

| 维度 | 默认值 | 行为 |
|------|--------|------|
| 每 Token 每日请求数 | 100 | 超限返回 429 `QUOTA_EXCEEDED`，UTC 0:00 重置 |
| 每 Token 每月请求数 | 3000 | 超限返回 429 `QUOTA_EXCEEDED`，每月 1 日 UTC 0:00 重置 |
| 每 Token 每分钟请求数 | 10 | 超限返回 429 `RATE_LIMITED`（滑动窗口） |
| Token 分配频率 | 每 IP 每小时 5 个 | 超限返回 429 `RATE_LIMITED` |

超限响应应包含 `Retry-After` Header（秒）。

---

## 6. install 脚本与服务端交互流程

```
用户解压 zip
    │
    ▼
运行 install.bat / install.sh
    │
    ├─ 1. 检测包内 Node 可用
    │
    ├─ 2. 生成 install_id (UUID v4)
    │
    ├─ 3. POST /api/tokens
    │     请求体: { platform, install_id, version }
    │     ← 响应: { token, chat_url, proxy_base_url, quota }
    │
    ├─ 4. npm install --omit=dev (用包内 Node 安装依赖)
    │
    ├─ 5. 写入 openclaw.json:
    │     models.providers.proxy = {
    │       baseUrl: proxy_base_url,
    │       apiKey: token,
    │       api: "openai-completions",
    │       models: [{ id: "auto", name: "Auto" }]
    │     }
    │
    ├─ 6. 生成 chat.html / chat.url (快捷方式)
    │     指向 chat_url
    │
    └─ 7. 输出安装完成提示
```

---

## 7. Web UI 与代理交互流程

```
用户点击 chat_url (浏览器打开)
    │
    ▼
GET /chat?token=ocp_xxx
    │
    ▼
浏览器加载聊天页面
    │
    ├─ JS 从 URL ?token= 读取 Token
    │
    ├─ 用户输入消息
    │
    ├─ POST /v1/chat/completions
    │   Header: Authorization: Bearer ocp_xxx
    │   Body: { model: "auto", messages: [...], stream: true }
    │
    ├─ 代理校验 Token → 查库 → 检查限流
    │   ├─ 通过 → 转发上游 LLM → SSE 流式返回
    │   └─ 不通过 → 返回错误 (401/403/429)
    │
    └─ 前端逐行读取 SSE data → 显示在消息列表
```

---

## 8. 版本与兼容性

- 协议版本通过响应 Header `X-Protocol-Version: 1.0.0` 返回。
- 客户端和服务端都应在日志/调试信息中记录协议版本。
- 破坏性变更须升大版本号（如 2.0.0），并保持旧版本至少 30 天兼容。
