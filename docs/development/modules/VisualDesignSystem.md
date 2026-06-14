# Visual Design System

## 范围

负责 Sci-Station 的整体视觉语言：颜色、层级、密度、圆角、阴影、Liquid Glass 使用边界、图标 tint、状态色、数据色，以及 Home/Project/AI Lab/Library 等模块之间的 UI 一致性。

## 参考产品与启发

本轮参考方向来自 Apple 官方新设计系统资料，以及优秀生产力软件的公开产品页：

- Apple Liquid Glass：控制层和导航层从内容层上方浮起，材料动态适配内容与明暗环境；不要把玻璃当作普通背景纹理。
- Linear：高密度产品协作 UI 可以用深一点的中性色、清楚的 issue/status/project 层级、少量强状态色保持速度感。
- Raycast：命令型工具强调键盘优先、毫秒级响应、单/双栏结果、强扩展入口；AI 能力应嵌入操作流，而不是另开孤立聊天页。
- Things：任务与计划 UI 的优秀点不在于装饰，而在于低负担录入、清晰的 Today/Project/Area 层级、适度留白和不会打断工作的动效。

## 色彩方向

当前界面偏淡，下一轮视觉实现应从“浅色玻璃卡片堆叠”转向“清晰层级 + 更深语义色”：

- 背景：使用更稳定的 off-white / cool gray 基底，减少大面积接近纯白的卡片。
- 内容卡片：卡片底色可比背景深 2-4 个百分点，并配合细边框；不要只依靠阴影区分层级。
- 状态色：Planning、Active、Blocked、Done、Needs Review 等状态要有固定语义色，不临时取蓝/绿/紫。
- 数据色：论文、任务、日历、AI、图谱等模块使用独立但克制的模块色；图标 tint 只表达类型或状态。
- 强调色：主操作和当前选择保留 accent color；同屏不要出现多个同权重高饱和按钮。
- 对比度：所有色板必须在 Light、Dark、Increase Contrast、Reduce Transparency 下验证。

## 密度与形态

- macOS operational UI 以扫描效率为主，避免营销式 hero、过大的标题和多层 card-in-card。
- Home 与 Project widgets 使用 4 列单位网格；`1×1` 是圆角正方形，内容只显示一个主判断。
- 较大 widget 增加信息密度，不做简单等比放大。
- 圆角遵循 concentric radius：外层容器、内层内容和 padding 应形成统一几何关系。
- 小控件优先 rounded rectangle；capsule 只给主操作、搜索/筛选等需要明显可点的区域。

## AI 对话视觉方向

- AI Lab 不再是单一聊天框，而是三层结构：会话列表、消息/工具调用流、证据与写回目标。
- 工具调用用状态卡表达 pending、running、approval、failed、completed；审批卡和失败卡要比普通 assistant 消息更醒目。
- 消息内容保持阅读宽度，证据和产物放在右侧或可折叠 inspector，避免长消息把操作入口挤出视野。
- AI 输入区应提供附件、引用当前选择、模式、工具预算和权限摘要，控件密度接近 Raycast/Linear，而不是大面积空白。

## 发布前检查

- 截图中第一眼能区分背景、导航、内容、状态、操作。
- 同一组件在 Home 与 Project 中的边距、圆角、图标 chip、按钮密度一致。
- 每个模块至少定义：主色、浅 tint、状态色、空态色、危险/警告色使用方式。
- 不使用颜色作为唯一状态表达，必须同时有文字、图标或布局提示。
- Reduce Transparency 下仍有足够层级；没有 glass-on-glass 造成的低对比文本。
