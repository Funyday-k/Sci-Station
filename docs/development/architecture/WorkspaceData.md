# Workspace 与数据格式

Research Root 是 Sci-Station 的用户数据边界。应用不得把用户论文、私有笔记、API key 或运行产物写入源码仓库。

## Research Root 典型结构

```text
ResearchRoot/
├── .sci-station/              内部索引、debug events、agent runs、推荐历史
├── library/                   论文库
├── projects/                  项目空间
├── wiki/                      全局 wiki
├── tasks/                     全局任务
├── settings/                  workspace 偏好
├── imports/                   导入暂存
├── data/ code/ figures/       研究资料
└── outputs/                   输出产物
```

## AI / Agent 本地状态

AI Lab 的生产默认 runtime 是 Swift Loop。与 AI Lab 相关的用户可管理状态属于 Research Root，而不是源码仓库：

```text
ResearchRoot/
└── .sci-station/
    └── agent/
        ├── profile.json       Prompt override、Skill toggle、MCP server 覆盖配置
        └── runs/<run-id>/     run ledger、prompt_snapshot.json、tool/evidence/debug artifacts
```

约束：

- `profile.json` 默认初始化为空列表，不保存 API key、token、private key、完整 provider response 或本机 secret。
- Prompt override 已进入 Swift Loop 执行链；run 需要记录 active template 的 id、version、hash 和 surface，便于回看。
- Workspace Skill 默认 untrusted；未显式 trusted 时不能读取正文或获得 write/network/destructive 权限。
- Local command MCP 默认 disabled；启用后也必须经过工具白名单和 approval。Remote HTTP/SSE MCP 是实验性可诊断路径：状态需要记录 transport、endpoint、last error/success、retry/backoff 和 credential failure，权限边界不因 remote transport 放松。
- Evidence trace 必须指向真实 paper/PDF/Markdown/Wiki/Graph artifact 等来源；synthetic/sample evidence 只能存在于测试 fixture 或明确标注的实验数据中。
- 写回结果只能在审批通过后修改 workspace 文件；拒绝审批不得删除 draft。

## 数据版本分类

- **App Version**：Xcode `MARKETING_VERSION`，用于用户沟通。
- **Build Number**：Xcode `CURRENT_PROJECT_VERSION`，每次测试构建递增。
- **Workspace Schema**：描述 Research Root 整体兼容性。
- **Feature Schema**：如 Tasks、Recommendation snapshot、Graph 等各自的 `schema_version`。
- **Agent Protocol**：sidecar / agent IPC 的协议版本，不等同于 App 版本。
- **Agent Runtime Selection**：workspace preference，当前默认 `swift_loop`；sidecar/auto 是实验性选择，不能作为生产默认迁移依据。

## 新增持久化文件规则

1. 明确归属：workspace、library paper、project、agent run、debug、cache。
2. 说明路径：写入路径必须在 Proposal 和 release record 中列出。
3. 说明 schema：字段、默认值、兼容解码、坏数据处理。
4. 说明隐私：是否包含正文、路径、标题、外部 URL、模型输出或 secret。
5. 补测试：round trip、缺字段、坏字段、旧版本样例。

## 兼容策略

- 可选新增字段：使用默认值和兼容 decode。
- 字段重命名：保留旧字段读取至少一个 minor 版本。
- 不兼容结构变化：增加 schema version，写 migration 或阻止写入。
- 用户数据修复：必须可备份、可取消、可解释。

## 禁止事项

- 不把 API key、token、private key、`.env*` 写入 Research Root 普通文本。
- 不静默删除用户文件。
- 不把 provider 原始响应长期持久化，除非用户明确要求并有隐私说明。
- 不让 debug events 泄漏绝对路径、论文正文、wiki 正文或 secret。
- 不把 synthetic evidence、sample evidence 或测试 fixture 输出写成普通生产 evidence。
