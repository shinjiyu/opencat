# OpenCat

一键部署 AI 聊天系统 —— 让用户「解压 → install → 打开链接即聊天」。

## 项目结构

```
opencat/
├── docs/
│   ├── protocol.md      # CS 协议规范（所有开发必须遵守）
│   ├── design.md        # 方案设计文档
│   └── dev-plan.md      # 开发计划
├── server/              # 服务端（Token 服务 + LLM 代理 + Web UI）
│   ├── src/
│   │   ├── index.ts     # 入口
│   │   ├── routes/      # 路由
│   │   ├── db/          # 数据库
│   │   └── middleware/  # 中间件
│   └── public/          # Web UI 静态文件
├── client/              # 客户端（打包脚本 + install 脚本）
│   ├── scripts/         # 打包与安装脚本
│   └── templates/       # 配置模板
└── README.md
```

## 开发须知

**协议优先**：所有 CS 交互必须严格遵守 [docs/protocol.md](docs/protocol.md)。修改协议须先更新文档。

## 打包客户端

服务端地址已内置，直接打包即可：

```bash
cd client/scripts

# 打包全平台
./build-portable.sh --platform all

# 打包全平台 + 预分配 Token
./build-portable.sh --platform all --pre-token

# 打包单平台
./build-portable.sh --platform win-x64
```

产出在 `dist/` 目录下。

## 本地开发

```bash
cd server
cp .env.example .env    # 编辑 .env 配置上游 LLM
npm install
npm run dev
```

## 文档

- [CS 协议规范](docs/protocol.md) — **开发前必读**
- [方案设计](docs/design.md)
- [开发计划](docs/dev-plan.md)
