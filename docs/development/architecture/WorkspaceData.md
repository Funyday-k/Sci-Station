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

## 数据版本分类

- **App Version**：Xcode `MARKETING_VERSION`，用于用户沟通。
- **Build Number**：Xcode `CURRENT_PROJECT_VERSION`，每次测试构建递增。
- **Workspace Schema**：描述 Research Root 整体兼容性。
- **Feature Schema**：如 Tasks、Recommendation snapshot、Graph 等各自的 `schema_version`。
- **Agent Protocol**：sidecar / agent IPC 的协议版本，不等同于 App 版本。

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
