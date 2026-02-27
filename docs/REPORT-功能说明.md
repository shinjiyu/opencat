# OpenCat 项目功能报告

> 说明：远端服务器已部署；本报告侧重整体功能与「客户端 + 已部署服务端」的使用方式。

---

## 1. 项目定位

**OpenCat** 是一套「便携式 AI 聊天」部署方案：用户**无需自备 LLM API Key、无需安装 Node/Git**，只需：

1. 下载对应平台的 zip 包  
2. 解压 → 运行安装脚本（`install.bat` / `install.sh`）  
3. 打开生成的聊天链接（或 `open-chat.html`）即可在浏览器中聊天  

所有 LLM 能力由**运营方已部署的服务端**通过 Token 鉴权 + 配额管理统一提供。

---

## 2. 架构概览

```
┌─────────────────────────────────────┐         ┌─────────────────────────────────┐
│  用户电脑（客户端）                   │         │  已部署的远端服务器               │
│                                     │         │                                 │
│  zip 包:                             │  HTTPS  │  Token 服务  → 分配/校验 Token  │
│  • Node 便携版 + 应用代码            │ ──────→ │  LLM 代理    → 转发到上游 LLM   │
│  • install.bat / install.sh         │         │  Chat Web UI → /chat?token=xxx  │
│                                     │         │  管理接口     → /api/admin/*     │
│  安装后:                             │         │                                 │
│  • opencat.json（含 Token、代理 URL）│         │  存储: SQLite (tokens + usage)   │
│  • open-chat.html → 跳转 chat_url   │         │                                 │
└─────────────────────────────────────┘         └─────────────────────────────────┘
```

- **传输**：全部 HTTPS；JSON 请求/响应，流式用 SSE。
- **鉴权**：用户用 Bearer Token（`occ_` + 32 位 hex）；管理端用 `X-Admin-Secret`。

---

## 3. 本仓库各模块功能

| 模块 | 路径 | 功能简述 |
|------|------|----------|
| **服务端** | `server/` | Token 分配与校验、LLM 代理（OpenAI 兼容）、聊天 Web UI、管理接口。已部署在远端时，本地主要用于二次开发或自建。 |
| **客户端** | `client/` | 打包脚本（产出各平台 zip）、安装脚本（申请 Token、写配置、生成 open-chat.html）。**远端已部署时，本地主要用这里打包/定制客户端。** |
| **协议与设计** | `docs/` | `protocol.md`（CS 协议，必读）、`design.md`（方案设计）、`dev-plan.md`（开发阶段与待办）。 |

---

## 4. 服务端已部署时的使用方式

### 4.1 用户侧（最终用户）

1. 从运营方获取对应平台的 **zip 包**（由本库 `client/scripts/build-portable.sh` 产出）。  
2. 解压后运行 **install.bat**（Windows）或 **install.sh**（macOS/Linux）。  
3. 安装脚本会：  
   - 向**已部署的服务端** `POST /api/tokens` 申请 Token；  
   - 执行 `npm install` 安装依赖；  
   - 写入 `opencat.json`（含 `proxy_base_url`、`token`）；  
   - 生成 `open-chat.html`（重定向到 `chat_url`）。  
4. 用户双击 **open-chat.html** 或打开 `token.json` 里的 `chat_url`，即可在浏览器中使用 Web UI 聊天。

### 4.2 运营方/开发者侧（本地仓库）

- **只打包客户端、不改服务端**  
  - 进入 `client/scripts`，执行：  
    - `./build-portable.sh --platform all`  
    - 或 `./build-portable.sh --platform win-x64` 等单平台。  
  - 服务端 URL 在打包时注入（如当前 `install.bat` 中的 `SERVER_URL`），需与**已部署的远端地址**一致（如 `https://kuroneko.chat/opencat`）。  
  - 产出在 `client/scripts/dist/`。  

- **可选：预分配 Token**  
  - 使用 `--pre-token` 时，打包前会向当前配置的服务器申请 Token 并写入包内，用户安装时不再请求，适合离线或统一发放场景。

- **自建/二次开发服务端**  
  - 进入 `server/`，复制 `.env.example` 为 `.env`，配置 `UPSTREAM_*`、`ADMIN_SECRET`、`PUBLIC_BASE_URL` 等，然后 `npm run dev` 即可本地跑；与远端部署是同一套代码。

---

## 5. 核心接口（与 protocol.md 一致）

| 接口 | 用途 | 调用方 |
|------|------|--------|
| `POST /api/tokens` | 分配新 Token（platform, install_id, version 等） | 安装脚本 |
| `GET /api/tokens/:token/status` | 查询 Token 状态与配额 | 客户端可选 |
| `POST /v1/chat/completions` | 聊天（OpenAI 兼容，支持流式） | Web UI / 客户端 |
| `GET /v1/models` | 可用模型列表 | Web UI / 客户端 |
| `GET /chat?token=xxx` | 聊天 Web 页面 | 浏览器 |
| `GET /api/admin/tokens` 等 | 管理 Token（列表/修改/删除） | 管理员（需 Admin Secret） |

---

## 6. 技术栈摘要

| 组件 | 技术 |
|------|------|
| 服务端 | Hono (Node.js)、better-sqlite3、dotenv |
| 上游 LLM | 可配置（如 OpenRouter），见 `.env.example` 中 `UPSTREAM_*` |
| Web UI | 静态 HTML + JS，SSE 流式渲染 |
| 客户端打包 | Shell 脚本 + zip；安装脚本为 BAT + Shell |

---

## 7. 安全与限流（协议约定）

- Token 格式：`occ_` + 32 位 hex；配额独立，泄露仅影响该 Token 限额。  
- 默认限流：每 Token 每日/每月请求上限、每分钟请求上限；Token 分配按 IP 限频。  
- 管理接口与用户 Token 分离，使用 `ADMIN_SECRET`。

---

## 8. 总结

- **库的整体功能**：提供「服务端（Token + LLM 代理 + Web UI）+ 客户端（打包 + 安装脚本）」的完整方案，使最终用户通过「解压 → install → 打开链接」即可使用 AI 聊天。  
- **远端服务器已部署时**：本库在本地主要用于**打包/定制客户端**（`client/scripts`），并可选自建或修改服务端（`server/`）；最终用户只需拿到 zip、运行安装脚本，即可自动向该远端申请 Token 并打开聊天页面。

---

*报告基于当前仓库 `README`、`docs/protocol.md`、`docs/design.md`、`docs/dev-plan.md` 及 server/client 代码整理。*
