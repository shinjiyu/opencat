# OpenClaw Portable

傻瓜版 OpenClaw 部署系统 —— 让用户「解压 → install → 打开链接即聊天」。

## 项目结构

```
openclaw-portable/
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

## 快速开始

```bash
# 服务端
cd server
npm install
npm run dev

# 打包客户端（示例：Windows x64）
cd client
./scripts/build-portable.sh --platform win-x64
```

## 文档

- [CS 协议规范](docs/protocol.md) — **开发前必读**
- [方案设计](docs/design.md)
- [开发计划](docs/dev-plan.md)
