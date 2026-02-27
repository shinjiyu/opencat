# 便携 AI 聊天系统 — 部署方案设计

本文档描述在**无 Git、无本机 Node、可能有防火墙、且包含 Windows** 环境下，如何设计一套「傻瓜版」部署方案，使用户只需下载、解压、运行安装脚本即可使用 AI 聊天。

---

## 1. 场景与约束

| 约束 | 含义 |
|------|------|
| 用户电脑可能是 Windows | 需支持原生 Windows（PowerShell / BAT），可选支持 macOS / Linux |
| 防火墙不能访问 Git | 不能依赖 `git clone`；所有获取均通过 **HTTPS 直连** |
| 没有 Node.js | 需**内嵌 Node 运行时**或由安装过程仅用 HTTPS 下载 Node 便携版 |
| 没有 LLM API Key | 用户无需自备 LLM Key；运营方通过代理提供 |

目标：用户**零前置环境**，通过「下载一个 zip → 解压 → 双击安装 → 打开链接」即可聊天。

---

## 2. 方案总结

1. **打包**: 将 Node.js 便携版 + 客户端代码打入 zip，按平台区分（win-x64 / darwin-arm64 / darwin-x64 / linux-x64）
2. **代理预配置**: 打包时或安装时预写配置，指向运营方的 LLM 代理服务
3. **LLM 代理服务**: 运营方部署 Token 管理 + LLM 转发代理，用户无需自备 API Key
4. **Web UI**: 提供简单的聊天 Web 页面，用户通过浏览器直接使用
5. **Token 体系**: 每个安装包/激活分配唯一 Token，用于鉴权和配额管理

### 2.1 鉴权方式

- 直接用 **URL 带 Token**（如 `?token=occ_xxx`）
- 用户拿到安装包后，安装脚本自动向服务端申请 Token
- Token 可跨设备使用（聊天链接可在任意浏览器打开）

### 2.2 打包方式

推荐方案：打包 Node.js 便携版 + 客户端代码（不含 node_modules），安装时在用户机器上 `npm install` 依赖。

优点：
- 包体积较小（~80MB 含 Node，不含数百 MB 的 node_modules）
- 依赖与用户平台完全匹配

缺点：
- 安装时需要网络连接

### 2.3 Node.js 平台区分

Node.js 二进制是平台相关的，需要按操作系统打包：

| 平台 | Node 包 |
|------|---------|
| win-x64 | `node-vXX-win-x64.zip` |
| darwin-arm64 | `node-vXX-darwin-arm64.tar.gz` |
| darwin-x64 | `node-vXX-darwin-x64.tar.gz` |
| linux-x64 | `node-vXX-linux-x64.tar.gz` |

打包脚本支持 `--platform all` 一次生成全部 4 个 zip。

---

## 3. 架构

```
┌──────────────────────────────────┐     ┌────────────────────────────────┐
│  用户电脑（客户端）               │     │  运营方服务器                    │
│                                  │     │                                │
│  zip 包:                         │     │  ┌─────────────┐               │
│  ├─ tools/node/  (Node 便携版)   │     │  │ Token 服务  │ ← SQLite/PG  │
│  ├─ lib/app/     (应用代码)      │     │  ├─────────────┤               │
│  └─ install.bat/sh               │     │  │ LLM 代理    │ → 上游 LLM   │
│                                  │     │  ├─────────────┤               │
│  安装后:                         │     │  │ Chat Web UI │               │
│  ├─ config.json  (Token+代理URL) │     │  └─────────────┘               │
│  └─ open-chat.html (聊天入口)    │     │                                │
└──────────────────────────────────┘     └────────────────────────────────┘
         │                                         ▲
         │  HTTPS: POST /api/tokens                │
         │  HTTPS: POST /v1/chat/completions       │
         └─────────────────────────────────────────┘
```

---

## 4. 交互入口

推荐使用 **反向代理 Web UI**（服务端托管聊天页面），用户通过浏览器访问。

优点：
- 零配置，打开链接即用
- 跨平台，任何有浏览器的设备都能用
- URL 自带 Token，无需额外登录

---

## 5. 安全考虑

- Token 不等于 API Key：即使 Token 泄露，攻击者只能使用有限配额
- 每个 Token 有独立的日/月用量限制
- 管理员可随时禁用任意 Token
- HTTPS 传输加密
- Admin Secret 独立管理，与用户 Token 分离
