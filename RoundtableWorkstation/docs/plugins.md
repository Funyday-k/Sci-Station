# 喜鹊圆桌插件开发与发布

插件可以给 Studio 的公开轮次和报告加入方法建议，也可以提供由主持人运行的本地工具。一份订阅目录可以发布多个插件。用户添加目录链接后，逐个选择安装或更新。

## 选择贡献与权限

| `contributions` 中的声明 | 使用时机与数据范围 | 安装时显示的权限 |
| --- | --- | --- |
| `round_guidance` | 为各席的公开发言提供方法建议，包含手动和自动轮次。应用在每轮开始时记录所用版本和内容。 | `round.guidance` |
| `report_guidance` | 为闭会报告的起草、复核及修订提供方法建议。应用在闭会时记录所用版本和内容，重新生成报告也使用这个版本。 | `report.guidance` |
| `actions` 的 `input` 为 `public_turns` | 主持人主动运行时，工具读取所选轮次范围内已经公开的发言。 | `code.execute`、`meeting.public_turns` |
| `actions` 的 `input` 为 `report` | 主持人主动运行时，工具读取当前会话的定稿 Markdown。 | `code.execute`、`meeting.report` |

应用从贡献声明推导权限。安装或升级时，确认窗口列出当前版本的能力，应用同时锁定该版本的 SHA-256 并校验下载文件。插件安装后默认全局启用，可在市场中停用。公开轮次的变更从下一轮生效，报告继续使用闭会时的记录。

方法建议属于提供给模型的可选上下文。写可执行的讨论步骤，例如「为关键判断列出可复查证据」。主持人指令、应用的讨论与报告协议、证据规则和文件权限优先。公开轮次建议只进入各席的公开发言调用。每项建议最多 8 KiB，同一阶段加入模型的建议和对应插件信息合计最多 8 KiB。启用或更新时会检查该上限，作者可缩短建议以便与其他插件共用。

## 编写 manifest

manifest 是 UTF-8 JSON。`id` 用你控制的反向域名命名，例如 `org.example.deliberation-checklist`。后续版本保留 `id`，版本号使用 `MAJOR.MINOR.PATCH`，例如 `1.0.0`。`name`、`author`、`description` 为非空单行文本，分别最多 128、128、1024 字节。

```json
{
  "schema_version": 1,
  "id": "org.example.deliberation-checklist",
  "name": "证据核查清单",
  "version": "1.0.0",
  "author": "Example Lab",
  "description": "在讨论与报告中提示需要补齐的证据。",
  "contributions": {
    "round_guidance": "对关键判断列出可复查的证据。遇到分歧时说明尚待核查的假设。",
    "report_guidance": "在结尾标记证据不足的判断和后续验证动作。"
  }
}
```

每个包至少声明一项贡献。工具放在 `contributions.actions` 数组，最多 16 项。每项声明 `id`、`label`、`input` 和 `format`，其中 `id` 在本包内唯一，最多 64 字节，用小写英文字母起头，其余字符可含小写英文字母、数字、下划线和连字符。`label` 为最多 128 字节的非空单行文本。`input` 取 `public_turns` 或 `report`，`format` 取 `markdown` 或 `text`。一个模块可服务同一插件内的多个工具，用输入中的 `action` 确定调用项。

## 实现本地工具

使用独立的 WebAssembly 模块。应用在本地运行它，工具的数据入口只有该次调用传入的 JSON。模块禁止所有导入及 `start` 节，因而没有 WASI、网络、项目目录、环境变量、私有发言或模型调用入口。返回内容显示为一次工具结果，文件访问权限和公开讨论由应用控制。

编译目标为 WebAssembly Core 1.0，可使用符号扩展和非陷阱浮点转整数指令。导出 `memory`、`alloc(i32) -> i32` 和 `run(i32, i32) -> i64`。

1. `alloc(n)` 返回长度至少为 `n` 的线性内存区的起始地址。应用写入 UTF-8 JSON。
2. `run(ptr, len)` 读取对应字节，并将 UTF-8 结果写入线性内存。应用以纯文本预览结果，`format` 决定下载格式。
3. `run` 返回一个 64 位整数。高 32 位为输出起始地址，低 32 位为输出字节数。C 可表示为 `((uint64_t)result_ptr << 32) | result_len`。

`public_turns` 输入按轮号及席位出场顺序排列，包含已结算轮次里已完成且非空的公开发言。正在执行的轮次整体等到结算后才可读取。

```json
{"action":"count","topic":"评估两种研究设计","turns":[{"round":1,"seat":"seat-03","seat_name":"方法评审","model":"模型名称","text":"建议先核对样本的选择条件。"}]}
```

动作输入中的 `seat` 是稳定席位编号，`seat_name` 是便于阅读的席位名称。名称可能含有引号或 Unicode 字符；统计工具按编号分别计数，并在名称存在时同时输出名称和编号。旧输入缺少 `seat_name` 或提供空名称时，工具回退为只显示编号。

`report` 输入在定稿可用后提供。

```json
{"action":"check-report","topic":"评估两种研究设计","report":"# 会议报告\n…"}
```

运行限制按字节计算。输入 JSON 最多 256 KiB，超限会报错，公开发言可改用更小的轮次范围。输出最多 128 KiB，线性内存最多 16 MiB，每次调用使用独立实例，编译和运行合计有 1 秒预算，同时最多校验或运行两个模块。模块最多 512 KiB，含 base64 模块的 UTF-8 JSON 包最多 1 MiB。写工具时按指针和长度读取数据，并把会议文本当作任意 UTF-8 输入处理。

## 打包并生成目录

在仓库根目录运行以下命令。`make headless` 构建包含发布命令的本地程序。若已有新版 macOS 应用，也可以把 `magpie` 指向应用包中的 `Contents/MacOS/sci-station`。

此例发布 `samples/plugins/` 中的两个插件。「论证与决策清单」提供文本建议。「公开发言统计」使用 C 编写，用 WASI SDK 28 编译为独立模块。将 `WASI_SDK_PATH` 设为 SDK 解压目录。 [下载 WASI SDK 28](https://github.com/WebAssembly/wasi-sdk/releases/tag/wasi-sdk-28)

```sh
make headless
magpie="$PWD/build/bin/sci-station-server"
publication_dir="$(mktemp -d)"
"$WASI_SDK_PATH/bin/clang" -O2 -ffreestanding -fno-builtin -nostdlib \
  -Wl,--no-entry,--strip-all,--export=alloc,--export=run,--export-memory \
  samples/plugins/public-turn-count.c -o "$publication_dir/public-turn-count.wasm"
"$magpie" plugin pack --manifest samples/plugins/deliberation-checklist.json \
  --out "$publication_dir/deliberation-checklist.json"
"$magpie" plugin pack --manifest samples/plugins/public-turn-count.json \
  --module "$publication_dir/public-turn-count.wasm" \
  --out "$publication_dir/public-turn-count.json"
"$magpie" plugin validate "$publication_dir/public-turn-count.json"
"$magpie" plugin catalog --name '我的喜鹊圆桌插件' --out "$publication_dir/catalog.json" \
  "$publication_dir/deliberation-checklist.json" "$publication_dir/public-turn-count.json"
```

`pack` 把 `.wasm` 写入包的 `module` 字段，编码为 base64。纯文本建议省略 `--module`。`validate` 校验整个包及模块接口并打印包的 ID、版本和 SHA-256，模块会编译检查，执行效果需要在真实会话中试用。`catalog` 从包内容生成版本、描述、权限和 SHA-256，并按 `id` 排序。目录和各包必须在同一个本地目录，每个 `id` 只登记一个版本，单份目录最多 256 个插件和 1 MiB。命令在本地生成新文件，已有同名输出时请指定新路径。

生成的目录是由 `schema_version`（值为 `1`）、`name` 和 `plugins` 数组组成的 JSON。每项包含 `id`、`version`、`name`、`author`、`description`、`url`、`sha256` 和 `capabilities`。更改包内容后，用正式发布的文件重新生成目录，确保摘要和权限与下载内容一致。

## 订阅、试用和升级

本机试用可执行 `python3 -m http.server 8769 --bind 127.0.0.1 --directory "$publication_dir"`。进入 Studio 侧栏的「插件市场」，在「插件目录」输入 `http://127.0.0.1:8769/catalog.json` 并点「订阅」。在「发现插件」按目录筛选，确认能看到两项插件。选择当前目录中的公开发言统计，授权对应能力并点「安装并启用」。同一个插件 ID 只能安装一份。若已经从内置来源安装示例，可使用独立测试数据目录试用自己的订阅来源。

在 Studio 会话标题栏打开「插件工具」，选择「统计公开发言」及已结算的轮次范围，点「运行工具」核对总数和每席计数。试用报告动作时先让报告定稿。可在市场「已安装」页启用、停用或卸载插件。

正式发布时将 `catalog.json` 和相应的包 JSON 放到同一个 HTTPS 静态站点目录，将目录的完整 URL 发给用户。目录内的包 URL 相对于 `catalog.json` 解析，目录和包必须同源。HTTP 仅可用于本机回环地址。站点直接返回生成的文件字节，包括末尾换行。静态站点收到的文件只需要目录 JSON 和已打好的包 JSON。

发布后若要修改插件，保持 `id`，递增 `version`，并用新文件名生成包，例如 `public-turn-count-1.1.0.json`。把新包与其他仍在目录中的包放进同一个新建发布目录，重新生成 `catalog.json`。先上传新包，再把新目录内容发布到原订阅 URL。用户刷新目录后可点「更新」并确认新版本的权限，应用校验目录中公布的 SHA-256。应用保留安装版本直到用户确认升级，升级维持原有启停状态。某个目录暂时无法刷新时，应用仍可使用上一次成功获取的目录，已安装包也保留在本地。

## 排查发布问题

| 现象 | 检查方法 |
| --- | --- |
| manifest 或模块校验失败 | 先看具体字段或导出名。确认版本格式、动作声明、模块配对及 `memory`、`alloc`、`run` 的导出签名。出现 WASI 或标准库导入时，检查编译指令是否包含 `-nostdlib` 及无入口选项。 |
| 目录无法生成 | 确认包的父目录与目录输出一致，且每个插件 ID 只提供一次。输出路径已存在时，在新目录中生成本次发布文件。 |
| 用户能看到目录，但包无法下载安装 | 直接打开目录和包 URL 检查 HTTPS、相对位置、同源及 HTTP 状态。若报告 SHA-256 不一致，将下载的 JSON 交给 `plugin validate`，与目录中的摘要逐字对照。若报告权限或元数据不一致，用正式发布的包重新生成目录，再刷新来源。 |
| 指导插件安装、启用或更新失败 | 如果提示指导总量超过 8 KiB，在市场中停用暂时用不到的同类指导，或发布正文更短的新版本。 |
| 工具运行失败 | 确认所需轮次已经结算或报告已经定稿。检查返回的地址、字节长度及 UTF-8 编码。超过输入上限时缩小公开轮次范围，超过内存、输出或时间上限时缩减模块工作量。 |
