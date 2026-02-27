# 傻瓜版 OpenClaw 部署方案（便携 / 离线 / 无 Git / 无 Node）

本文档描述在**无 Git、无本机 Node、可能有防火墙、且包含 Windows** 环境下，如何设计一套「傻瓜版」部署方案，使用户只需下载、解压（或运行安装器）即可使用 OpenClaw。

---

## 1. 场景与约束

| 约束 | 含义 |
|------|------|
| 用户电脑可能是 Windows | 需支持原生 Windows（PowerShell / 便携目录），可选支持 WSL2 |
| 防火墙不能访问 Git | 不能依赖 `git clone` / `git pull`；所有获取均通过 **HTTPS 直连**（浏览器、Invoke-WebRequest、curl 等） |
| 没有 Node.js | 不能假设本机已安装 Node；需**内嵌 Node 运行时**或由安装过程**仅用 HTTPS 下载 Node 便携版** |

目标：用户**零前置环境**（不装 Git、不装 Node），通过「下载一个安装包 / 便携包」即可完成部署。

---

## 2. 方案总览

| 方案 | 形态 | 适用场景 | 依赖网络 |
|------|------|----------|----------|
| **便携包（Portable）** | 单 zip，内嵌 Node + OpenClaw | 解压即用，可放 U 盘/内网共享 | 可选：仅首次下载需外网，之后可完全离线 |
| **傻瓜安装器（Simple Installer）** | 安装脚本或小型安装程序 | 一键安装到指定目录，自动下载 Node + OpenClaw | 安装时需 HTTPS（npm / openclaw.ai） |
| **离线安装包（Offline）** | 单一大 zip（Node + OpenClaw 已打包） | 完全不能上外网；由管理员在有网环境下载后拷贝 | 仅下载时需网络，目标机可完全离线 |

推荐优先做：**便携包（Windows 优先）** + **傻瓜安装器（PowerShell）**；离线包可作为便携包的一种发布物（同一内容，由有网机器下载后拷贝）。

---

## 2.1 方案总结（落地版）

在满足「免配置聊天」的前提下，采用**最简鉴权（URL 带 Token）**，整体方案可归纳为四条：

| 序号 | 事项 | 说明 |
|------|------|------|
| **1** | **打包 Node.js + OpenClaw** | 便携包内嵌 Node 与 OpenClaw（代码/包）；可选**全量包**（含依赖 + 打包时写 Token）或**包 Node+OpenClaw、用户本机运行 install 安装依赖**并同时向服务器要 Token（见 §2.3）。用户无需预装 Node、无需 Git。 |
| **2** | **预配置连接你们的 LiteLLM 代理** | 打包的 OpenClaw 已配置好指向你们的 LLM 代理（baseUrl + 每个包专属 Token），用户无需填写 API Key。 |
| **3** | **开发并运维 LLM 代理** | 你们自建代理（如基于 LiteLLM），接收带 Token 的请求、校验并限流后转发上游 LLM；一包一 Token，按 Token 控成本。 |
| **4** | **开发转发 Web UI** | 一个**仅提供聊天功能**的 Web 页，挂在代理同域；**不必与 OpenClaw 原有 Web UI 一致**。用户通过「URL 带 Token」打开即可聊天。OpenClaw 的完整能力（渠道、技能、本地配置等）由用户在本地自行配置、按需使用。 |
| **5** | **打包脚本 + 服务端数据库** | 打包时由脚本**分配 Token**、写入包内配置与「打开聊天」链接，并**调用服务端 API 将 Token 登记入库**；代理校验请求时查库校验 Token 并做限流。 |

**鉴权**：直接用 **URL 带 Token** 即可（如 `https://your-proxy.example.com/chat?token=xxx`），无需 Session/Cookie、帐密或复杂登录流程；包内「打开聊天」链接固定带该包 Token，用户点开即用。

---

## 2.2 打包脚本与 Token 入库

因每个安装包需绑定**唯一 Token**，且代理侧要能校验与限流，打包流程需与**服务端数据库**配合。

**流程**：

1. **执行打包脚本**（如 `scripts/build-portable.js` 或 `build-portable.sh`）：  
   - 脚本向**服务端 API** 请求「分配一个新 Token」（或本地生成 Token 后调用 API「登记 Token」）。  
   - 服务端在**数据库**中写入该 Token（及可选：创建时间、备注、初始配额等），并返回 Token 给脚本。
2. **脚本将 Token 写入包内**：  
   - 写入 OpenClaw 所用配置（如 `openclaw.json` 或 `.env` 中的代理 baseUrl + 该 Token）；  
   - 生成包内「打开聊天」链接（如 `https://your-proxy.example.com/chat?token=<Token>`），写入 README 或桌面快捷方式/本地小页面。
3. **打 zip / 产出安装包**：脚本用通用模板（Node + OpenClaw + 占位配置）替换为上述 Token 后打包，输出唯一安装包（或带版本号的文件名）。

**服务端数据库（或 API）职责**：

- **登记 Token**：打包脚本调用「创建/登记 Token」接口，服务端在库中新增一条记录（至少：`token`、`created_at`；可选：`quota`、`disabled`、`meta`）。  
- **代理校验**：LLM 代理与 Web UI 后端在处理请求时，从 URL/Header 取出 Token，**查库**校验是否存在、未禁用，并按该 Token 做限流/计费。

**脚本与服务的对接方式**：

- 脚本通过 **HTTPS 调用你们的内网或公网 API**（如 `POST /api/tokens` 或 `POST /api/portable/allocate-token`），传入必要参数（如来源标识、备注），服务端返回新 Token 并落库。  
- 若打包环境无法访问外网，可改为：脚本**本地生成** Token（如 UUID），产出包后，由**人工或 CI 后续步骤**将 Token 清单导入服务端数据库；代理侧同样按库校验。

**小结**：打包脚本 = 分配/生成 Token + 写入包内 + 通知服务端入库；服务端数据库 = 存 Token、供代理校验与限流。这样每个产出的安装包都有唯一 Token，且代理能识别并控成本。

---

## 2.3 两种打包方式：全量包 vs 包 Node+OpenClaw + 用户本机 install 依赖

**方案 A — 全量便携包（Node + OpenClaw + 依赖一起打包）**  
- **打包时**：脚本向服务器请求新 Token，将 **Node + OpenClaw**（含完整 `node_modules`）与 Token 一起打进 zip；Token 写入包内配置与「打开聊天」链接，并已在服务端入库。  
- **用户侧**：解压即用，**无需再运行 install**；包内已含完整运行环境与预配置。  
- 适用：希望用户「解压就能用」、且接受在你们侧为每次分发生成带 Token 的 zip（或一批预生成包）；zip 体积较大（含依赖）。

**方案 B — 打包 Node + OpenClaw，用户本机 install 依赖（推荐）**  
- **打包时**：把 **Node 便携版（按平台）+ OpenClaw**（代码/包，可不带或只带部分 `node_modules`）按**平台**打成多份 zip（见下「Node 是否区分平台」），每份内放 **install 脚本**（如 `install.bat` / `install.ps1`）；打包时**不**分配 Token。  
- **用户侧**：下载与己平台对应的 zip，解压后运行 **install**；install 脚本在用户电脑上：  
  1. 向**服务器请求新 Token**（如 `POST /api/tokens`），服务端生成 Token 并落库、返回给脚本；  
  2. 用包内 Node 在 OpenClaw 目录下**安装依赖**（如 `npm install` / `pnpm install`，拉取并写入 `node_modules`）；  
  3. 写入配置（代理 baseUrl + 该 Token）、生成「打开聊天」链接并保存到本地（如 README 或桌面快捷方式）。  
- **结果**：zip 体积小（不含完整依赖），一安装一 Token（在用户运行 install 时分配并入库）；需**按平台维护多份 zip**（因 Node 二进制按平台不同），或采用「通用 zip 不含 Node、install 时下载对应 Node」（见下）。  
- **代价**：用户首次必须联网运行 install（拉依赖 + 要 Token）；完全离线需用方案 A 或预装好依赖的离线包。

**结论**：**打包 Node.js 和 OpenClaw（代码/包），在用户机器上运行 install 时安装依赖并向服务器要 Token**；这样既避免 zip 里塞满 node_modules，又保持「一个通用包 + 一安装一 Token」。

**是否提前打包 node_modules？推荐不打包。**

| 方式 | 优点 | 缺点 |
|------|------|------|
| **不打包依赖，用户本机 `npm install`** | zip 小（Node + OpenClaw 代码约几十 MB）；一次通用包即可，无需按平台打多份；用户侧依赖与当前 registry 一致。 | 用户首次必须联网；`npm install` 可能因网络/权限/原生模块失败，需文档或脚本做好提示。 |
| **提前打包好 node_modules（全量包）** | 解压即用，可完全离线；不依赖用户环境拉依赖。 | zip 很大（通常 100MB+）；若含原生模块需按平台（Windows/Linux）分别打包；更新时用户要重下整包。 |

**建议**：默认采用**不打包 node_modules**，用户本机 install 依赖——包体积小、分发简单，且能下载 zip 的用户一般也能访问 npm registry（HTTPS）。若存在**完全不能联网**或**内网无 registry** 的场景，再单独提供「预装好依赖的离线全量包」或内网 npm 镜像说明。

**Node 是否需要区分 Mac / Windows？需要。**

Node 运行时是**平台相关**的二进制（Windows / macOS Intel / macOS ARM / Linux 等不能混用），因此：

| 做法 | 说明 |
|------|------|
| **按平台打多份 zip** | 每个平台一份：如 `openclaw-portable-win-x64.zip`（内嵌 Node win-x64）、`openclaw-portable-darwin-arm64.zip`（内嵌 Node darwin-arm64）、`openclaw-portable-darwin-x64.zip`、`openclaw-portable-linux-x64.zip` 等。用户下载时选择与自己系统对应的包。打包脚本需为各平台下载对应 [Node 官方构建](https://nodejs.org/dist/) 并打进 zip。 |
| **通用 zip 不含 Node，install 时下载** | 只打一份「通用」zip（仅 OpenClaw 代码 + install 脚本，**不含 Node**）。用户解压后运行 install；install 脚本**检测当前系统**（如 `process.platform` / `os.arch()` 或系统命令），从 nodejs.org 或你们镜像下载**该平台**的 Node 便携包，解压到包内再执行 `npm install` 等。这样只需维护一份 zip，但用户首次 install 需能访问 Node 下载源。 |

**建议**：若希望用户「解压即带 Node」、且能接受按平台发版，用**按平台多份 zip**（常见如 Windows x64 + macOS ARM + macOS x64）。若希望只维护一个下载入口，用**通用 zip + install 时下载对应 Node**。

---

## 3. 便携包（Portable Bundle）

### 3.1 内容（全量包时；若采用「只包 Node + install」则见 §2.3 方案 B）

- **Node 运行时**：Node 22 便携版（例如 Windows 用 [nodejs.org 的 win-x64 zip](https://nodejs.org/dist/v22.22.0/node-v22.22.0-win-x64.zip)），解压到目录内，例如 `tools/node/`。
- **OpenClaw**（仅全量包）：从 npm 拉取的 `openclaw` 包（tgz 解压）或预构建的 `dist` + `node_modules`，放在目录内，例如 `lib/openclaw/`。若采用「只包 Node + install」，则由 install 脚本在用户本机下载/安装。
- **启动脚本**：
  - Windows：`openclaw.bat` 或 `openclaw.ps1`，设置 `PATH` 指向内嵌的 `node`，再执行 `node lib/openclaw/openclaw.mjs ...`（或通过 `bin/openclaw` 之类入口）。
  - 若有 WSL/Linux 版本：`openclaw` 脚本，`export PATH=<bundle>/tools/node/bin:$PATH`，再调用同一 CLI。

### 3.2 目录结构示例

```
openclaw-portable/
├── tools/
│   └── node/           # Node 22 便携版（win-x64 或 linux-x64 解压）
│       └── bin/node
├── lib/
│   └── openclaw/       # OpenClaw 包内容（npm 包或预构建）
├── bin/
│   └── openclaw        # 入口脚本（指向 lib/openclaw）
├── openclaw.bat        # Windows 批处理入口
├── openclaw.ps1        # Windows PowerShell 入口（可选）
└── README.txt          # 使用说明（解压路径、如何运行、数据目录 ~/.openclaw）
```

### 3.3 分发与更新

- **分发**：在 openclaw.ai 或 CDN 提供固定 URL，例如：  
  `https://openclaw.ai/downloads/openclaw-portable-win64-<version>.zip`  
  用户用**浏览器**或任意支持 HTTPS 的工具下载，**不需要 Git**。
- **更新**：提供新版本 zip；用户下载后覆盖解压或解压到新目录。可选：在 CLI 内提供「检查更新」仅输出新版本下载链接（HTTPS），由用户自行下载。

### 3.4 数据与配置

- 配置与数据仍放在 **用户目录**（如 `~/.openclaw` 或 Windows `%USERPROFILE%\.openclaw`），不写死在便携目录内，便于同一便携包多用户或 U 盘换机使用。
- 启动脚本无需管理员权限，不写系统 PATH（或可选「添加到 PATH」由用户选择）。

---

## 4. 傻瓜安装器（Simple Installer）

### 4.1 目标

- 用户**没有 Node、没有 Git**，只需能运行 PowerShell 并能访问 **HTTPS**（openclaw.ai、nodejs.org、registry.npmjs.org 等）。
- 安装器自动：检测/下载 Node 便携版 → 下载 OpenClaw（npm tgz 或 openclaw.ai 预打包）→ 解压到指定目录 → 创建启动脚本与可选快捷方式。

### 4.2 流程（PowerShell 示例）

1. **检测 PowerShell 版本**（建议 5+）。
2. **选择安装目录**（默认如 `%LOCALAPPDATA%\OpenClaw` 或用户选择）。
3. **Node**：若本机无 Node 或版本 &lt; 22，则用 `Invoke-WebRequest` 从 nodejs.org 下载 **Windows 便携 zip**（仅 HTTPS），解压到 `<安装目录>\tools\node`。
4. **OpenClaw**：  
   - 方式 A：从 npm registry 用 HTTPS 下载 `openclaw@latest` 的 tgz（不执行 `npm install`，仅下载 tgz + 解压），或  
   - 方式 B：从 openclaw.ai 下载预打包的 `openclaw-<version>.tgz` 或 zip，解压到 `<安装目录>\lib\openclaw`。  
   两种方式均**不需要 Git**。
5. **写启动脚本**：在安装目录生成 `openclaw.bat` / `openclaw.ps1`，内部 `PATH` 指向 `<安装目录>\tools\node`，调用 `node <安装目录>\lib\openclaw\...`。
6. **（可选）** 将安装目录的 `bin` 或脚本所在目录添加到用户 PATH；或创建开始菜单/桌面快捷方式。
7. **（可选）** 运行 `openclaw doctor --non-interactive` 做基础检查。

### 4.3 安装器本身如何下发

- **有 HTTPS 无 Git**：将 `install-portable.ps1` 放在 openclaw.ai，用户执行：  
  `irm https://openclaw.ai/install-portable.ps1 | iex`  
  或先浏览器下载 `install-portable.ps1` 再本地执行。
- **完全无外网**：安装器脚本与「离线安装包」一起用 U 盘拷贝；安装器从**本地路径**读取已打包好的 Node + OpenClaw，解压到目标目录（不再从网络拉取）。

---

## 5. 离线安装包（Offline Bundle）

- **内容**：与便携包相同（内嵌 Node + OpenClaw），打成单一大 zip。
- **使用**：在有网络的机器下载该 zip，通过 U 盘/内网共享拷贝到目标机；目标机解压即用，**无需任何外网**。
- **构建**：在 CI 或发布流程中，用 Node 官方 Windows 便携 zip + npm 的 openclaw tgz（或 openclaw.ai 的预打包）组装，并生成 SHA256 校验和，便于内网分发时校验。

---

## 6. 技术要点小结

| 要点 | 做法 |
|------|------|
| **不依赖 Git** | 所有代码/包通过 HTTPS 直连获取（npm registry、openclaw.ai、nodejs.org）；安装器与文档中不出现 `git clone` / `git pull`。 |
| **不依赖本机 Node** | 便携包/离线包内嵌 Node；傻瓜安装器在安装时用 HTTPS 下载 Node 便携版并解压到安装目录。 |
| **防火墙友好** | 仅使用常见放行的 HTTPS 端口（443）；不依赖 Git 协议或其它非标准端口。 |
| **Windows 优先** | 提供 `.bat` / `.ps1` 入口；Node 使用官方 win-x64 zip；安装目录与数据目录使用 Windows 习惯（%LOCALAPPDATA%、%USERPROFILE%\.openclaw）。 |
| **可选 WSL2** | 若有 Linux 便携包，可单独提供；文档中保留「推荐 WSL2」作为进阶选项，傻瓜版仍以原生 Windows 为主。 |

---

## 7. 与现有安装方式的关系

- **install.sh / install.ps1**：依赖系统 Node 或自动装 Node（winget/choco）、可选 Git；适合「能访问外网、可装 Node」的环境。
- **install-cli.sh**：已支持「本地 prefix + 内嵌 Node 下载」，但当前仍会 Ensure Git；若仅用 npm 方法，可考虑在「便携/傻瓜」分支中完全去掉 Git 依赖。
- **傻瓜版**：与上述三者**并列**，面向「无 Git、无 Node、Windows、可能离线」的场景，通过**便携包 + 傻瓜安装器 + 可选离线包**覆盖。

---

## 8. 实施顺序建议

1. **便携包构建流水线**：脚本或 CI 步骤：下载 Node 便携 zip + 下载 openclaw tgz → 解压组装 → 打 zip → 生成 SHA256。
2. **Windows 启动脚本**：`openclaw.bat` / `openclaw.ps1`，正确设置 PATH 与工作目录，调用内嵌 Node 与 OpenClaw。
3. **傻瓜安装器**：PowerShell 脚本 `install-portable.ps1`，实现上述 4.2 流程；先支持「在线」（HTTPS 下载 Node + OpenClaw），再支持「离线」（从本地 zip 解压）。
4. **文档与下载页**：在 openclaw.ai 提供「傻瓜版 / 便携版」说明与下载链接；文档中明确「无需 Git、无需预装 Node、适合防火墙环境」。

若你希望，我可以再细化某一节的实现细节（例如 PowerShell 脚本伪代码、或 CI 构建步骤）。

---

## 9. 用户没有 LLM：通用 API 路由

若用户**没有任何一家 LLM 厂商的 API Key**（没有 Anthropic / OpenAI / 国内厂商等），仍可通过「**通用 API 路由**」用**一个入口、一个 Key** 访问多种模型，或使用免费/本地方案。

### 9.1 可选方案概览

| 方案 | 用户需要 | 说明 |
|------|----------|------|
| **OpenRouter** | 一个 OpenRouter API Key（注册即得，可先用免费模型） | 统一端点 + 一个 Key 访问多家模型；含 **免费模型**（如 `openrouter/meta-llama/llama-3.3-70b-instruct:free`），无需信用卡。 |
| **LiteLLM 代理** | 由运维/组织下发的一个 LiteLLM Key | 组织自建 LiteLLM，后端配置好各厂商 Key；用户只拿一个 LiteLLM Key，不接触底层厂商。 |
| **Vercel / Cloudflare AI Gateway** | 由网关管理员配置的 Key 或账号 | 网关统一路由；通常「管理员配置后端 Key，用户用网关 Key 或账号」。 |
| **本地模型（Ollama / vLLM / LM Studio）** | 无需任何 API Key | 本机跑模型，OpenClaw 连本地端点；适合有显卡、可离线、不想用云 API 的场景。 |

### 9.2 推荐：OpenRouter（零厂商 Key + 可选免费）

- **特点**：一个 [OpenRouter](https://openrouter.ai) 账号 → 一个 `OPENROUTER_API_KEY`，即可在 OpenClaw 里使用多种模型；兼容 OpenAI API，OpenClaw 内置支持。
- **免费模型**：OpenRouter 提供带 `:free` 的模型（如 `openrouter/deepseek/deepseek-r1:free`、`openrouter/google/gemini-2.0-flash-vision:free`），无需绑卡即可调用。
- **配置要点**：
  - 环境变量：`OPENROUTER_API_KEY=sk-or-...`
  - 模型引用格式：`openrouter/<厂商>/<模型>`，例如 `openrouter/anthropic/claude-sonnet-4-5`；免费模型加后缀 `:free`。
- **傻瓜版建议**：便携包/安装器附带的 README 或首次引导里，可写「若没有其他 LLM：去 openrouter.ai 注册，拿到一个 Key，在 OpenClaw 里配置为 OpenRouter 即可」；并推荐先用 `openclaw models scan`（需设 `OPENROUTER_API_KEY`）查看当前免费模型列表。

详见：[OpenRouter](/providers/openrouter)、[Model Providers](/concepts/model-providers)；扫描免费模型：[Models — Scanning (OpenRouter free models)](/concepts/models#scanning-openrouter-free-models)。

### 9.3 组织内共享：LiteLLM 代理

- **特点**：由公司/团队部署 [LiteLLM](https://litellm.ai) 代理，在代理里配置好 Anthropic、OpenAI 等真实 API Key；给最终用户只发放**一个 LiteLLM API Key**（可设额度、审计）。
- **用户侧**：无需任何厂商 Key，只需能访问该 LiteLLM 端点 + 自己的 LiteLLM Key；OpenClaw 将 `baseUrl` 指向该代理，`apiKey` 用下发的 Key 即可。
- **适用**：内网/防火墙环境、统一管控成本与合规、多模型路由与降级。

详见：[LiteLLM](/providers/litellm)。

### 9.4 完全无云：本地模型（Ollama / vLLM）

- **特点**：不依赖任何云 API，无需 API Key；本机安装 Ollama 或 vLLM，OpenClaw 连接本地 `http://localhost:...`。
- **限制**：需要本机或内网有一台能跑模型的机器（显存/内存足够）；傻瓜版文档中可写「若无云 Key，可选用本地模型」，并指向 [Local models](/gateway/local-models)。

### 9.5 小结（傻瓜版文档可写）

- **没有任何 LLM 时**：优先推荐「**一个 OpenRouter 账号 + 免费模型**」，或由组织提供「**一个 LiteLLM Key**」。
- **不想用云 / 不能联网**：用 **Ollama 等本地模型**，零 Key。
- 通用 API 路由 = **一个入口、一个 Key（或零 Key 本地）**，避免用户去记多家厂商、多个 Key；便携版 README 可只写 OpenRouter + 本地两种路径，其余按需链到文档。

---

## 10. 分发式零配置：不预埋 Key 怎么让用户「啥都不用配就能聊」

目标是**分发式傻瓜版**：用户解压/安装后**不填任何 Key 就能聊天**。但**不能**在安装包里预打包真实 API Key（会泄露、被滥用、成本不可控）。下面是几种可行做法。

### 10.1 为什么不能预埋 Key

- 包会流传、反编译或配置被拷贝，Key 一旦泄露 = 所有人共用，容易被刷爆或封号。
- 成本无法控制；合规与风控也成问题。
- 因此：**零配置聊天**必须通过「后端或一次性的用户侧授权」解决，而不是在分发包里写死 Key。

### 10.2 方案 A：自建「演示后端」（真·零配置）

**思路**：由你（或社区/赞助方）跑一个**统一代理**（如 LiteLLM、或自研小网关），后端配置好真实 Key 或只用免费/低成本模型；**傻瓜版默认连这个端点**，并带一个**仅用于演示的公共 Token**（或按 IP/设备限流、不强制 Token）。

- **用户侧**：解压即用，无需填 Key，打开就能聊。
- **你方**：承担调用成本；通过**严格限流**控费，例如：
  - 按 IP 或按设备 ID：例如每设备每日 N 条、或每 IP 每小时 M 条；
  - 总预算：每天/每月封顶金额，超限后返回「演示额度已用完，请配置自己的 Key」。
- **可选**：演示 Token 可轮换或短期有效，减少泄露后的影响。

**适用**：想做真正的「分发即聊」、愿意承担有限演示成本（或靠赞助/捐赠覆盖）。

### 10.3 方案 B：「一步拿 Key」—— 只让用户做一次最少操作

**思路**：不预埋 Key，但把「拿 Key」做成**唯一一步、尽量无脑**：

- **方式 1**：首次启动时弹出「获取免费 Key」→ 点按钮后**用系统浏览器打开 OpenRouter 注册/登录页**（或支持 OAuth 则直接回调），用户登录后**复制一个 Key** 回来粘贴一次（或 OAuth 回调自动写进配置）。
- **方式 2**：便携包内带一个**固定链接**（如 `https://openrouter.ai/keys` 或你们自己的引导页），文案写「复制页面上的 Key，回到 OpenClaw 粘贴一次即可」；OpenClaw 首次启动检测到无 Key 时，只提示这一步。

这样用户**只做「打开网页 → 复制 Key → 粘贴一次」**，之后永久有效；没有在分发包里放 Key，只是把「拿 Key」的步骤压到最少。

**适用**：可以接受「用户必须做一次操作」，但希望体验接近「傻瓜」。

### 10.4 方案 C：混合——先演示额度，用完再自带 Key

**思路**：结合 A 和 B：

- 默认连**你的演示后端**，每设备/每 IP 给一个**小额度**（如 5～10 条/天），真正零配置先玩起来。
- 额度用完后，界面提示：「演示次数已用完。请配置自己的 Key（推荐 OpenRouter 一个 Key 即可）或安装 Ollama 使用本地模型」，并引导到方案 B 的「一步拿 Key」或本地模型文档。

这样**首次使用 = 零配置**，长期使用 = 用户自带 Key 或本地，你方只需为「尝鲜」付一点成本。

### 10.5 方案 D：不提供零配置，只做「最少配置」

**思路**：分发版**不预埋 Key、也不自建演示后端**；首次启动时**必须**让用户二选一：

- 填一个 OpenRouter Key（或你们文档里推荐的「一个 Key」入口），或  
- 选择「使用本机 Ollama」并检测本地是否已装 Ollama。

把引导做得很短（一个页面、一段文案、一个输入框），但**不承诺「啥都不配就能聊」**。

**适用**：不想承担后端成本、也不想维护演示额度，只做「分发包 + 最少配置引导」。

### 10.6 小结与推荐

| 方案 | 用户零配置？ | 你方成本/运维 | 实现难度 |
|------|--------------|----------------|----------|
| **A. 自建演示后端** | 是 | 需限流 + 预算或赞助 | 中（后端 + 客户端默认 endpoint） |
| **B. 一步拿 Key** | 否（做一次） | 无 | 低（首次启动引导 + 链接/ OAuth） |
| **C. 混合（演示额度 + 再用自带 Key）** | 首次是 | 有限演示成本 | 中高 |
| **D. 最少配置** | 否 | 无 | 低 |

- 若**必须**「啥都不配就能聊」：只能走 **A** 或 **C**（自建演示后端 + 严格限流）。
- 若可接受「用户只做一次操作」：**B** 最现实——分发版不包 Key，但首次启动只让用户「打开网页拿一个 Key、粘贴一次」，后续永久可用。
- **C** 在体验和成本之间折中：零配置尝鲜，用完自然过渡到自带 Key，避免无限兜底成本。

### 10.7 推荐形态：API 转发代理 + 一包一账号

在「自建演示后端」基础上，把**每个安装包（或每次安装）绑定一个独立的代理账号**，这样既零配置，又不会「一个 Key 泄露全部分发用户共用」。

**目标**：

- 用户拿到的要么是**唯一安装包**（包内已带该包专属的代理 Token），要么是**通用包 + 首次运行自动领一个 Token**。
- 每个 Token = 一个代理账号：只用于访问你的转发代理，你方在代理侧按 Token 限流、计费、封禁，不暴露真实 LLM Key。

**系统组成**：

1. **API 转发代理（你的后端）**
   - 对外提供 OpenAI 兼容的聊天接口（如 `/v1/chat/completions`），请求头带 `Authorization: Bearer <token>`。
   - 校验 Token：合法则转发到上游 LLM（你配置的 Anthropic/OpenAI/OpenRouter 等），非法则 401。
   - 按 Token 做限流与用量统计（如每 Token 每日 N 条、或每月预算封顶）；可随时禁用某 Token。

2. **Token / 账号发放**
   - **方式甲：按下载生成唯一安装包**  
     用户在你提供的下载页点击「下载傻瓜版」→ 后端为该次下载生成一个 **新 Token**，并生成**唯一安装包**（通用 zip 模板 + 把该 Token 写入包内配置，如 `openclaw.json` 或 `.env` 或单独 `proxy.token`）。用户解压即用，无需再填任何 Key。  
   - **方式乙：通用包 + 首次激活**  
     所有用户下载**同一份**安装包。首次运行时，客户端调用你的后端「激活」接口（可带设备指纹或安装 ID），后端为该次安装**发放一个 Token**，客户端写入本地配置；之后请求一律带该 Token。效果同样是「一安装一账号」，但不需要为每次下载生成不同 zip。

3. **安装包内容**
   - 傻瓜版默认 `models.providers`（或环境变量）指向**你的代理 baseUrl**，且认证方式为「从本地读取 Token」。
   - 若采用**方式甲**：打包时已写入该包专属 Token，用户无感知。
   - 若采用**方式乙**：打包时 baseUrl 固定，Token 为空；首次启动时请求激活接口拿到 Token 并写入本地，再开始正常请求。

**小结**：

- **API 转发代理** = 统一入口、你方控制 Key 与成本；**一包一账号（或一安装一账号）** = 每个分发单位独立 Token，防泄露、可限流、可封禁。
- 实现上二选一即可：**唯一安装包（下载时生成 Token 并打进包）** 或 **通用包 + 首次激活（首次运行向后端领 Token）**；后者分发更简单（一个通用 zip），前者适合「离线/内网」场景（Token 已在包内，不依赖首次联网激活）。

---

## 11. 交互入口：免配置下用什么 UI、要不要飞书

傻瓜版**免配置**意味着不能让用户自己去配飞书机器人（创建应用、拿 App ID/Secret、配置事件订阅等，步骤多且容易劝退）。交互入口只能二选一或组合：**你方提供的反向代理 Web UI**，或 **你方预埋飞书机器人并把用户拉进你的企业**。对比如下。

### 11.1 方案对比

| 方案 | 做法 | 用户侧体验 | 你方成本与问题 |
|------|------|------------|----------------|
| **反向代理 Web UI** | 你方部署一个 Web 聊天页（可复用 OpenClaw 的 web/control 或自建简版），挂在代理同一域名下；用户用浏览器打开 URL，用「包内 Token」或会话登录后即可聊天。LLM 请求走你的代理 + Token。 | 打开链接就能聊，无需装飞书、无需加企业；手机/电脑有浏览器即可。 | 需维护一个 Web 前端 + 会话/鉴权（可与代理 Token 打通）；不依赖飞书。 |
| **预埋飞书机器人 + 拉用户进企业** | 你方在自己的飞书企业下创建一个机器人；用户被「邀请加入你的企业」或加入你建的群，在飞书里和该机器人对话。 | 用户在飞书里聊，习惯飞书的人会觉得自然。 | 用户必须**加入你的飞书企业**（或至少进你的群）：信任/隐私门槛高；企业成员数、权限、合规都要你管；所有用户共用一个企业/一个 bot，按人限流要靠群或会话维度，运维和隔离都更复杂。 |

### 11.2 推荐：以反向代理 Web UI 为主入口

- **免配置**：用户只需「打开你给的链接」（或安装包内预设的链接），用包内 Token 或首次激活拿到的 Token 即可聊天，**无需配置飞书、无需加入任何企业**。
- **实现**：代理后端除提供 `/v1/chat/completions` 外，再挂一个 **Web 聊天页**（例如 `/chat` 或 `/`）；该页由你方前端提供，请求聊天时带同一 Token（Cookie / Header / 登录态）。可选：安装包内写死「打开即用」的 URL（如 `https://your-proxy.example.com/chat?token=<包内Token>` 或登录页自动读本地 Token）。
- **扩展**：若希望支持飞书，可做成**可选、进阶**——「想用飞书请自己创建飞书应用并配置」并链到 [Feishu](/channels/feishu) 文档；傻瓜版默认不依赖飞书。

### 11.3 不推荐：预埋飞书机器人并拉用户进你的企业

- **拉进企业**：用户必须加入你的飞书企业（或你建的群），很多人不愿加陌生企业、或所在公司不允许加外部组织；企业成员上限、审批、权限也会成为瓶颈。
- **单企业单 bot**：所有分发用户共用一个企业、一个机器人，按人限流/按 Token 计费要依赖「用户在哪个群 / 会话」来映射，复杂且易混乱；你方还要长期承担「企业管理员」角色。
- **结论**：除非目标用户本来就是「你们公司内部或紧密合作方」，否则**不建议**把「预埋飞书 + 拉用户进企业」作为傻瓜版主入口；更适合用 **反向代理 Web UI** 做主入口，飞书留给用户自建、自配。

### 11.4 多用户 Web UI 鉴权

多用户共用同一个 Web UI 域名时，需要**按「谁」做鉴权与限流**。你方已经有一包一账号（每个安装包/每次激活对应一个 **Proxy Token**），鉴权就围绕「把 Token 交给前端 → 后端校验并按 Token 限流」来做。

**简化方案（推荐）**：鉴权**仅用 URL 带 Token**（如 `https://proxy.example.com/chat?token=xxx`）。包内「打开聊天」链接固定带该包 Token，用户点开即用；后端每次请求从 URL 或请求参数/Header 取 Token 校验并限流即可，无需 Session、Cookie 或帐密。以下为可选扩展（需要「不把 Token 暴露在 URL」或「无 Token 时也能登录」时再考虑）。

**原则**：

- **身份 = Token**：不要求用户再注册账号；一个 Token 就是一个「账号」，后端按 Token 做限流、计费、封禁。
- **多用户** = 多个不同 Token 同时访问同一 Web UI；后端根据请求里带的 Token 区分用户即可。

**用户无需每次输入 Token**：

- **第一次**：用户通过以下任一方式「带出」Token 一次即可——（1）点安装包里的「打开聊天」链接（链接里已带 Token），或（2）在登录页粘贴一次 Token，或（3）由包内本地服务自动提供 Token。后端校验 Token 后 **Set-Cookie 写入 Session**（如 SessionID），并跳转到聊天页。
- **之后同一设备/浏览器**：只要 Cookie 未过期、未清除，用户**直接打开聊天页**（如收藏的 `https://proxy.example.com/chat`）或**再次点包里的同一链接**即可，**无需再输入 Token**——请求会自动带上 Cookie，后端用 Session 识别身份。
- **包内「打开聊天」链接的两种用法**：  
  - **推荐**：链接写 `?token=xxx`，用户每次点都带 Token 访问；后端若发现 URL 带合法 Token，则刷新/创建 Session 并重定向到无 Token 的 `/chat`。这样用户**永远不用输入**，点一次就进；新设备或清除 Cookie 后，再点同一链接即可恢复登录。  
  - **备选**：首次点链接用 Token 换 Session 后，提示用户「可收藏当前页面地址，下次直接打开」；之后用户只打开收藏的 `/chat`，靠 Cookie 登录。
- **多设备**：换了一台设备或换了浏览器时，在该设备上**再点一次包里的链接**（或把链接发给自己再点），或**粘贴一次 Token**，即可在该设备也建立 Session；之后该设备同样无需再输入。Token 可写在包内说明或本地配置文件里，用户只需在「新设备首次」复制粘贴一次。

**Token 如何到用户手里**（沿用前面设计）：

- 唯一安装包：Token 已写在包内配置或说明里；用户打开包内「一键打开 Web」链接时，该链接可带 Token（见下）。
- 通用包 + 首次激活：首次运行时客户端向激活接口领 Token，并写入本地；之后打开 Web 时需把该 Token 带给前端（见下）。

**前端 / 入口如何拿到 Token**（三选一或组合）：

| 方式 | 做法 | 优点 | 注意 |
|------|------|------|------|
| **A. URL 带 Token（首次打开）** | 安装包内「打开聊天」指向 `https://proxy.example.com/chat?token=xxx` 或 `#token=xxx`；前端首次加载从 query/fragment 读 Token，**立刻存到 Session 或内存**，并**重定向到无 Token 的 URL**（如 `/chat`），避免 Token 留在地址栏、Referrer、历史里。 | 零输入、一点即用。 | 仅首次用 URL；之后用 Session 或 Cookie，不再把 Token 放在 URL。 |
| **B. 登录页粘贴 Token** | 用户打开 `https://proxy.example.com/chat`，未带有效会话时显示「请输入您的使用码 / Token」；用户从包内说明或本地配置文件复制 Token 粘贴提交；后端校验后下发 Session（Cookie），并跳转到聊天页。 | Token 不经过 URL；适合「通用包」或 Token 在本地文件里的场景。 | 需要用户做一次复制粘贴。 |
| **C. 本地服务提供 Token** | 安装包内带一个**本地小服务**（如 `localhost:小端口`），浏览器打开 Web UI 时，前端通过该本地服务（或安装包内页面）拿到当前机器的 Token（从本地配置读）；再带着 Token 访问你的 Web UI（如 POST 到后端换 Session，或带 Token 跳转一次后重定向掉）。 | 用户无需复制粘贴，且 Token 不写进安装包里的 URL。 | 需在安装包内跑一个本地进程，并处理浏览器与本地服务的通信（如 CORS、或本地页做中转）。 |

**前端请求时如何带身份**（二选一）：

- **Session（推荐）**：首次用 A/B/C 之一拿到 Token 后，**后端校验 Token 并创建会话**，Set-Cookie 一个 **SessionID**（HttpOnly、Secure、SameSite）；之后所有请求只带该 Cookie，后端根据 SessionID 查出对应 Token，再转发 LLM 并限流。这样 Token 只在前端出现一次（或不出现），不随每次请求暴露。
- **每次带 Token**：前端把 Token 放在内存或 localStorage，每次请求聊天 API 时带 `Authorization: Bearer <token>`。实现简单，但 Token 在前端持久化有被 XSS 窃取风险；若用则尽量只在内存、用完即丢，或限制 Token 权限/额度以降低泄露影响。

**后端校验与多用户**：

- 每个请求（聊天接口、或带 Session 的 Web 请求）：从 Cookie 的 SessionID 或 Header 的 Bearer Token 解析出 **Token**。
- 校验 Token 是否有效、是否被禁用；若有效则根据 Token 查限流/配额，通过则转发上游 LLM，并在该 Token 上扣量/计费。
- 多用户 = 多个不同 Token 并发请求；后端无状态地按 Token 区分即可，无需在 Web 层维护「用户表」（除非你额外做账号体系）。

**安全小结**：

- 使用 **HTTPS**，Cookie 设 **HttpOnly + Secure + SameSite**。
- 尽量**避免 Token 长期出现在 URL**（首次用 URL 带 Token 时，立即换 Session 并重定向到无 Token 的地址）。
- 若用「粘贴 Token」登录，提交用 POST、不把 Token 再写回 URL。
- 可选：Token 设有效期或单设备绑定，降低泄露后的影响。

**同一用户多平台登录**：

- **同一 Token 可在多设备/多平台使用**：一个用户可能同时在手机、电脑、不同浏览器打开 Web UI；只要都用**同一个 Token** 登录即可。后端应允许**同一 Token 对应多个并发 Session**（多台设备 = 多个 SessionID，都映射到同一 Token）。
- **限流与计费按 Token 聚合**：不按 Session 数限流，而是按 **Token** 汇总该用户在所有设备上的用量；配额、封禁、计费都以 Token 为单位，这样「多平台登录」自然共享同一份额度。
- **实现要点**：登录/激活时若用 Session，每台设备会拿到不同的 SessionID，但后端存储时 **SessionID → Token** 映射即可；同一 Token 可对应多条 Session 记录。校验请求时用 SessionID 查出 Token，再按 Token 做限流和扣量。
- **可选策略**：若担心一个 Token 被多人共享滥用，可加「同一 Token 最多 N 个并发 Session」或「同一 Token 最多 N 台设备」（按设备指纹或 Session 数限制）；一般情况下可不限制，仅按 Token 总用量控成本。

**无 Token 时：支持帐密登录**：

- **场景**：用户没带 Token（换设备没保存链接、包丢了、Token 忘了等），仍需要能登录 Web UI。此时应支持**账号密码（帐密）登录**作为备选。
- **设计**：后端维护「账号」与「Token」的绑定关系（一对一：一个账号对应一个 Token）。  
  - **登录方式 1 — Token**：用包内链接或粘贴 Token，校验后建 Session（同上）。  
  - **登录方式 2 — 帐密**：用户输入用户名/邮箱 + 密码；后端校验通过后，查出该账号绑定的 Token（若没有则可为该账号生成新 Token 并绑定），用该 Token 建 Session，后续与「Token 登录」行为一致（限流、计费都按该 Token）。
- **账号从哪来**：可选（1）**注册页**：用户自行注册用户名/邮箱+密码，注册成功时后端为其生成并绑定一个 Token；（2）**发放时即建账号**：在「下载唯一安装包」或「首次激活」时，除下发 Token 外，同时生成一对帐密（或让用户设密码）并写入包内说明/邮件，相当于「一个包 = 一个 Token + 一个账号」；（3）仅**绑定已有 Token**：用户先有 Token，再在 Web 里「绑定账号」设置密码，之后可用帐密登录。
- **找回 Token**：用户用帐密登录后，在「设置 / 账号」里可查看或复制当前账号绑定的 Token，便于在新设备用链接或粘贴方式登录，或写进新安装包。
- **小结**：Token 仍为后端鉴权与限流的单位；帐密是「人的记忆入口」，通过账号 ↔ Token 绑定，在没 Token 时也能登录并复用同一 Token 的配额与多端能力。
