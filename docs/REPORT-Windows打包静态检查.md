# Windows 打包静态代码检查报告

**检查范围**：Windows 打包路径、后端/LLM 预配置、Token 生成与管理、安装脚本与日志。  
**结论**：发现 **SERVER_URL 无法注入**（严重）、**安装日志不足**、**Content-Length 小问题**；其余路径与 Token 逻辑正常。

---

## 1. 打包路径与结构

### 1.1 build-portable.sh 产出的 Windows 包结构

| 路径 | 说明 |
|------|------|
| `opencat-portable/` | zip 根目录（解压后即为此目录） |
| `opencat-portable/install.bat` | Windows 安装入口 |
| `opencat-portable/tools/node/` | Node 便携版（从 node-v*.-win-x64.zip 解压） |
| `opencat-portable/lib/app/` | 应用代码（npm pack 解压的 package） |

- **结论**：路径设计合理；`install.bat` 使用 `%~dp0` 得到脚本所在目录，`NODE=%SCRIPT_DIR%tools\node\node.exe`、`APP_DIR=%SCRIPT_DIR%lib\app` 与上述结构一致，无路径错误。

### 1.2 潜在注意点

- Windows 下 zip 解压后若用户移动到「带空格或中文」的路径，`SCRIPT_DIR` 含空格时在部分场景可能需引号。当前 `set "NODE=..."` 已用引号，一般无问题；若后续在 `%NODE%` 外再包一层调用，需保持引号使用一致。

---

## 2. 后端 LLM 预配置

- **服务端**：LLM 由已部署服务的 `.env` 配置（`UPSTREAM_BASE_URL`、`UPSTREAM_API_KEY`、`UPSTREAM_DEFAULT_MODEL`），与打包无关。
- **客户端包**：仅需「服务端根 URL」正确；安装后从 `POST /api/tokens` 响应中取得 `proxy_base_url`（即 `{PUBLIC_BASE_URL}/v1`）和 `token`，写入 `opencat.json`。  
  **问题**：见下一节 —— 若打包时传入 `--server-url`，Windows 包内的服务端 URL **未被替换**，导致可能连错环境或无法注入自定义后端。

---

## 3. SERVER_URL 注入问题（严重）

### 3.1 现象

- `build-portable.sh` 对 **Windows** 的注入逻辑（约 131 行）：
  ```bash
  sed "s|SERVER_URL=https://proxy.example.com|SERVER_URL=$SERVER_URL|g" \
    "$SCRIPT_DIR/install.bat" > "$BUNDLE_DIR/install.bat"
  ```
- 当前 **install.bat** 中写死为：
  ```bat
  set "SERVER_URL=https://kuroneko.chat/opencat"
  ```
- 因此 sed 的「查找串」`SERVER_URL=https://proxy.example.com` 在 install.bat 中**不存在**，打包时即使用 `--server-url https://other.com` 打 Windows 包，包内仍是 `https://kuroneko.chat/opencat`，**SERVER_URL 实际未被注入**。

### 3.2 Unix 端

- build 脚本对 install.sh 的替换为：
  ```bash
  sed "s|SERVER_URL=\${SERVER_URL:-https://proxy.example.com}|SERVER_URL=\${SERVER_URL:-$SERVER_URL}|g"
  ```
- 而 install.sh 中为：
  ```bash
  SERVER_URL=${SERVER_URL:-https://kuroneko.chat/opencat}
  ```
- 同样没有 `https://proxy.example.com` 占位符，**Unix 包也无法通过 build 参数注入 SERVER_URL**。

### 3.3 建议修复

- **install.bat**：将默认值改为占位符 `https://proxy.example.com`，与 build 脚本约定一致，打包时由 sed 替换为实际 `--server-url`。
- **install.sh**：将默认值改为 `SERVER_URL=${SERVER_URL:-https://proxy.example.com}`，同上，便于 build 脚本统一替换。

---

## 4. Token 生成与管理

### 4.1 服务端

- `server/src/db/tokens.ts`：`generateToken()` 为 `occ_` + 16 字节 random hex（32 字符），符合协议。
- `server/src/routes/tokens.ts`：`POST /api/tokens` 校验 `platform`、`install_id`，调用 `createToken`，返回 `token`、`chat_url`、`proxy_base_url`、`quota`、`created_at`，与 protocol 一致。
- 数据库为 JSON 文件（schema.ts），持久化正常。

### 4.2 客户端 install.bat

- 使用 `powershell -Command "[guid]::NewGuid().ToString()"` 生成 `INSTALL_ID`（UUID），符合协议。
- 请求体包含 `platform: 'win-x64'`、`install_id`、`version: 'portable'`，满足必填字段。
- 成功后将响应写入 `%SCRIPT_DIR%token.json`，再根据其内容写入 `%APP_DIR%\opencat.json` 和 `open-chat.html`，路径与用途正确。
- **小问题**：下一节 Content-Length。

### 4.3 pre-token 预配置

- build 脚本在 `--pre-token` 时向当前 `SERVER_URL` 请求 Token，并在包内预写 `lib/app/opencat.json` 和 `open-chat.html`。
- install.bat 通过 `if exist "%APP_DIR%\opencat.json"` 判断预配置，跳过 Token 请求，仅执行 npm install，逻辑正确。

---

## 5. 安装脚本问题与日志

### 5.1 Content-Length（小问题）

- **install.bat** 中 Node 内联脚本使用 `'Content-Length': data.length`（字符数）。
- 协议与 HTTP 要求为字节数；当前仅传 ASCII 字段无问题，但若日后扩展 `meta` 等含中文，应改为 `Buffer.byteLength(data)`。
- **install.sh** 已使用 `Buffer.byteLength(data)`，建议 Windows 端与之一致。

### 5.2 安装过程日志不足

当前 install.bat 仅有：

- 步骤提示：`[1/4]`～`[4/4]`
- 成功时：Node 版本、Token、Chat URL、Config written、Chat shortcut created
- 失败时：ERROR 文案 + pause

**缺少**：

- 未输出 **SERVER_URL**、**INSTALL_ID**，排障时难以确认请求目标和实例。
- 未将「各步骤结果、错误响应体、时间」写入**安装日志文件**，失败时难以事后分析（尤其无控制台截图时）。

**建议**：

- 在请求 Token 前 echo `SERVER_URL`、`INSTALL_ID`。
- 可选：将关键步骤与错误写入 `%SCRIPT_DIR%install.log`（带时间戳），便于支持与排查。

---

## 6. 检查项汇总

| 检查项 | 结果 | 说明 |
|--------|------|------|
| Windows 打包目录结构 | 通过 | tools/node、lib/app、install.bat 与脚本内路径一致 |
| 后端 LLM 预配置 | 通过 | 由已部署服务 .env 决定；客户端仅需正确 SERVER_URL |
| SERVER_URL 打包注入 | **不通过** | install.bat/install.sh 未使用 proxy.example.com 占位符，sed 无法替换 |
| Token 生成（服务端） | 通过 | occ_+32hex，入库与返回符合协议 |
| Token 请求与写入（install.bat） | 通过 | platform/install_id/version 正确，文件路径正确 |
| pre-token 流程 | 通过 | 预写 opencat.json 后安装脚本正确跳过申请 |
| Content-Length | 建议修复 | install.bat 使用 data.length，建议改为 Buffer.byteLength(data) |
| 安装详细日志 | 不通过 | 无 SERVER_URL/INSTALL_ID 输出，无日志文件 |

---

## 7. 建议修复优先级

1. **高**：统一 SERVER_URL 占位符（install.bat + install.sh），确保 `--server-url` 对 Windows/Unix 均生效。
2. **中**：安装脚本增加详细日志（至少输出 SERVER_URL、INSTALL_ID；推荐写入 install.log）。
3. **低**：install.bat 中 Content-Length 改为 Buffer.byteLength(data)，与协议及 install.sh 一致。

---

## 8. 已实施的修复（与本次检查同步）

- **SERVER_URL 占位符**：`install.bat`、`install.sh` 已改为默认 `https://proxy.example.com`，与 `build-portable.sh` 的 sed 一致，打包时 `--server-url` 可正确注入。
- **install.bat 日志**：增加 `install.log`（脚本同目录），记录开始时间、Server URL、各步骤及错误；控制台增加 `[INFO] Server URL`、`[INFO] Install ID` 输出；完成时提示 Log file 路径。
- **Content-Length**：install.bat 中 Node 请求头已改为 `Buffer.byteLength(data)`，与 install.sh 及协议一致。

---

*报告基于当前 `client/scripts` 与 `server/src` 静态阅读完成。*
