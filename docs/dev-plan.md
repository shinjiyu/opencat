# OpenCat — 开发计划

基于 [design.md](./design.md) 中确认的方案。

---

## 架构回顾

```
┌──────────────────────────────────────────────────────────────┐
│  用户电脑（客户端）                                           │
│                                                              │
│  ┌──────────────┐     install.bat/sh                         │
│  │ Node (便携)  │ ──→ npm install (装依赖)                   │
│  │ + 应用代码   │ ──→ POST /api/tokens (要 Token)            │
│  └──────┬───────┘                                            │
│         │ 安装后                                              │
│         ▼                                                    │
│  浏览器打开 chat_url  ──→  LLM 请求带 Token                  │
└──────────────┬───────────────────────────────────────────────┘
               │ HTTPS
               ▼
┌──────────────────────────────────────────────────────────────┐
│  运营方服务器                                                 │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Token 服务   │  │ LLM 代理     │  │ Chat Web UI  │       │
│  │ /api/tokens  │  │ /v1/chat/... │  │ /chat        │       │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┘       │
│         │                 │                                   │
│    ┌────▼────┐      ┌─────▼─────┐                            │
│    │  数据库  │      │ 上游 LLM  │                            │
│    │ SQLite  │      │ Provider  │                            │
│    └─────────┘      └───────────┘                            │
└──────────────────────────────────────────────────────────────┘
```

---

## 开发阶段

### Phase 0: 协议设计（CS 协议 + API 接口规范）

**产出**: `docs/protocol.md`

- [x] 定义 Token 分配接口 (`POST /api/tokens`)
- [x] 定义 Token 状态查询接口 (`GET /api/tokens/:token/status`)
- [x] 定义 LLM 代理接口 (`POST /v1/chat/completions`, OpenAI 兼容)
- [x] 定义模型列表接口 (`GET /v1/models`)
- [x] 定义管理接口 (`/api/admin/*`)
- [x] 定义 Web UI 页面接口 (`GET /chat`)
- [x] 定义数据模型 (tokens 表 + usage 表)
- [x] 定义限流规则
- [x] 定义鉴权机制 (Bearer Token + Admin Secret)
- [x] 定义 SSE 流式传输格式

### Phase 1: 服务端 — Token 服务 + 数据库

**产出**: `server/src/db/`, `server/src/routes/tokens.ts`

- [x] SQLite 数据库初始化 (tokens + usage 表)
- [x] Token 生成与分配 (`occ_` + 32 hex)
- [x] Token CRUD 操作
- [x] 配额查询 (日/月用量)
- [x] 用量记录与递增

### Phase 2: 服务端 — LLM 代理（转发 + 限流）

**产出**: `server/src/routes/proxy.ts`, `server/src/middleware/auth.ts`

- [x] Token 鉴权中间件
- [x] 配额检查 (日/月限额)
- [x] 上游 LLM 请求转发
- [x] SSE 流式响应透传
- [x] 非流式响应处理
- [x] 用量统计
- [ ] 每分钟滑动窗口限流（待实现）

### Phase 3: 服务端 — 聊天 Web UI

**产出**: `server/public/index.html`

- [x] 简洁聊天界面
- [x] URL Token 读取
- [x] SSE 流式消息渲染
- [x] 错误提示
- [ ] Markdown 渲染（待实现）
- [ ] 消息历史持久化（待实现）

### Phase 4: 客户端 — 打包脚本

**产出**: `client/scripts/build-portable.sh`

- [x] 多平台 Node.js 下载与打包
- [x] 应用代码打包
- [x] install 脚本注入 server URL
- [x] `--platform all` 全平台一键打包
- [x] `--pre-token` 预分配 Token
- [x] Node.js 下载缓存

### Phase 5: 客户端 — 安装脚本

**产出**: `client/scripts/install.sh`, `client/scripts/install.bat`

- [x] Windows BAT 安装脚本
- [x] macOS/Linux Shell 安装脚本
- [x] 自动 npm install 依赖
- [x] 自动请求 Token
- [x] 自动写入配置
- [x] 生成聊天快捷方式

### Phase 6: 集成测试 + E2E 验证

- [ ] 服务端启动 → Token 分配 → 代理转发 E2E
- [ ] 打包 → 解压 → install → 聊天 全流程
- [ ] Windows 平台测试（CI 或虚拟机）
- [ ] 错误场景测试（无网络、Token 过期、配额超限）

### Phase 7: 文档 + 发布

- [ ] 运营方部署文档
- [ ] 用户使用说明
- [ ] 常见问题 FAQ

---

## 阶段依赖

```
Phase 0 (协议) ──→ Phase 1 (Token) ──→ Phase 2 (代理) ──→ Phase 3 (Web UI)
                                                              │
Phase 0 ──→ Phase 4 (打包) ──→ Phase 5 (安装)                │
                                                              │
                      Phase 6 (集成测试) ←────────────────────┘
                              │
                      Phase 7 (文档+发布)
```

---

## 技术栈

| 组件 | 技术选型 |
|------|----------|
| 服务端框架 | Hono (Node.js) |
| 数据库 | SQLite (better-sqlite3) |
| 上游 LLM | 可配置（OpenRouter / 自有 API） |
| Web UI | 纯 HTML + JS（无框架） |
| 打包 | Bash 脚本 + zip |
| 安装 | BAT (Windows) / Shell (macOS/Linux) |
