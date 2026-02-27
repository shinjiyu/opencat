# 本地 OpenClaw Web UI 隧道方案设计（省带宽）

**目标**：用户本机运行 OpenClaw（含 Web UI，如 `http://127.0.0.1:3080`），通过 kuroneko.chat 提供统一入口访问该本地界面；**服务器资源小，需严格控制带宽**。

---

## 1. 约束与原则

| 约束 | 含义 |
|------|------|
| “本地”指用户本机 | 需把用户本机的 OpenClaw Web UI 暴露到公网，供浏览器或 kuroneko 访问 |
| 服务器小、要考虑带宽 | **流量尽量不经过 kuroneko**；kuroneko 只做「入口/登记/重定向」，不做大流量反向代理 |

**原则**：kuroneko 不转发 OpenClaw 的页面、静态资源、API、SSE 等大流量，只做「告诉浏览器去哪」或「登记隧道 URL」。

---

## 2. 带宽对比（为何不做“经服务器的反向代理”）

- **方案 A：kuroneko 反向代理到用户隧道 URL**  
  浏览器 → kuroneko → 隧道 → 用户本机 OpenClaw。  
  所有 HTML/JS/API/SSE 都经 kuroneko 转发，**带宽和连接数都压在服务器上**，不适合小服务器。

- **方案 B（推荐）：kuroneko 只做重定向或展示链接**  
  浏览器先访问 kuroneko 一次（或拿到隧道 URL 后不再经过 kuroneko），随后所有 OpenClaw 流量为：浏览器 ↔ 隧道服务 ↔ 用户本机。  
  **kuroneko 只承担一次 302 或一个小 HTML 页面，带宽可忽略。**

结论：**采用“重定向/登记”模式，不在 kuroneko 上做 OpenClaw 流量的反向代理。**

---

## 3. 整体流程（省带宽）

```
用户本机                          公网                           kuroneko
────────                          ────                           ────────
OpenClaw (127.0.0.1:3080)
       │
       │ 隧道客户端（如 cloudflared / ngrok）
       │ 暴露为 https://xxx.trycloudflare.com 等
       ▼
┌──────────────────┐               │
│ 隧道服务商        │ ◀─────────────┘  (可选：向 kuroneko 登记 URL)
│ (Cloudflare/ngrok)│
└────────┬─────────┘
         │
         │ 用户打开 https://kuroneko.chat/openclaw?token=xxx
         ▼
   kuroneko 只做：
   - 校验 token，查出该 token 对应的隧道 URL
   - 302 重定向到 https://xxx.trycloudflare.com（或返回小 HTML 含该链接）
         │
         │ 之后所有请求：
         │ 浏览器 ◀──────▶ 隧道服务 ◀──────▶ 用户本机 OpenClaw
         │
         └── kuroneko 不再参与，带宽几乎为 0
```

---

## 4. 隧道选型（用户本机侧）

| 方案 | 带宽对服务器影响 | 用户侧复杂度 | 说明 |
|------|------------------|--------------|------|
| **Cloudflare Quick Tunnels** (`cloudflared tunnel --url 127.0.0.1:3080`) | 无（流量走 CF） | 低，单条命令 | 免费、无需在 kuroneko 跑 tunnel server，适合小服务器 |
| **ngrok**（免费/付费） | 无（流量走 ngrok） | 低 | 同上，流量不经 kuroneko |
| **自建 tunnel server 在 kuroneko 上**（如 frps + frpc） | **高**（所有流量经 kuroneko） | 中 | 不推荐，违背“省带宽” |

**推荐**：用户本机跑 **cloudflared** 或 **ngrok**，把 `127.0.0.1:3080` 暴露为一个公网 URL；kuroneko 只存储该 URL 并做重定向。

---

## 5. kuroneko 侧职责（最小、省带宽）

1. **存储「Token → 隧道 URL」**  
   - 用户本机（或 OpenClaw/安装脚本）在隧道就绪后，调用 kuroneko：`POST /api/tunnel`（带 token + tunnel_url），服务器仅做写入/更新，无大流量。

2. **统一入口页**  
   - `GET /openclaw?token=xxx`：  
     - 若该 token 已登记 tunnel_url → **302 重定向**到 tunnel_url（或返回极小 HTML：`<meta refresh` / 跳转链接）。  
     - 若未登记 → 返回简短说明页（“请先在本机启动 OpenClaw 并确保隧道已运行”等）。  
   - 不代理 OpenClaw 的任何静态资源或 API，**带宽仅一次重定向或一个小页面**。

3. **可选**  
   - 安装完成后提示两个入口：  
     - 远端聊天（现有 `/chat?token=xxx`）；  
     - 本地 OpenClaw：`https://kuroneko.chat/openclaw?token=xxx`（由上述逻辑重定向到用户隧道 URL）。

---

## 6. 可选：OpenClaw/安装脚本侧

- 安装脚本或 OpenClaw 启动后，可**自动**拉取 cloudflared（或使用便携版），执行 `cloudflared tunnel --url http://127.0.0.1:3080`，从 stdout 解析出临时 URL，再调用 kuroneko `POST /api/tunnel` 登记。  
- 这样用户只需「安装 → 启动 OpenClaw」，在 kuroneko 点「本地 OpenClaw」即可被重定向到本机界面，无需手填 URL。

---

## 7. 小结

| 项目 | 设计选择 |
|------|----------|
| “本地”含义 | 用户本机 OpenClaw Web UI |
| 隧道 | 用户本机跑 cloudflared/ngrok 等，暴露 127.0.0.1:3080 |
| 带宽 | kuroneko **只做重定向或小页面**，不反向代理 OpenClaw 流量 |
| 服务器 | 仅需「Token → tunnel_url」存储 + `/openclaw?token=xxx` 重定向，负载和带宽均很小 |

后续可实现：`POST /api/tunnel`、`GET /openclaw?token=xxx` 的重定向逻辑，以及（可选）安装/OpenClaw 侧自动起隧道并登记。
