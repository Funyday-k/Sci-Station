# 内置插件示例

- `deliberation-checklist.json` 提供讨论和报告指引。
- `public-turn-count.json` 声明「统计公开发言」动作。`public-turn-count.c` 读取动作输入中的 `turns` 数组，统计发言总数、有发言的席位数和各席位的发言次数。席位明细按首次发言顺序显示人类可读的 `seat_name` 与稳定的 `seat` 编号；旧输入没有名称或名称为空时只显示编号。同名席位会同时显示编号以便区分。

使用 [WASI SDK 28.0](https://github.com/WebAssembly/wasi-sdk/releases/tag/wasi-sdk-28)，将 `WASI_SDK_PATH` 设为解压后的 SDK 目录。从项目根目录运行以下命令，使用构建好的 `roundtable-studio` 命令。

```sh
PLUGIN_SAMPLE_BUILD="$(mktemp -d)"
"$WASI_SDK_PATH/bin/clang" -O2 -ffreestanding -fno-builtin -nostdlib \
  -Wl,--no-entry,--strip-all,--export=alloc,--export=run,--export-memory \
  samples/plugins/public-turn-count.c -o "$PLUGIN_SAMPLE_BUILD/public-turn-count.wasm"

roundtable-studio plugin pack \
  --manifest samples/plugins/deliberation-checklist.json \
  --out "$PLUGIN_SAMPLE_BUILD/deliberation-checklist.json"

roundtable-studio plugin pack \
  --manifest samples/plugins/public-turn-count.json \
  --module "$PLUGIN_SAMPLE_BUILD/public-turn-count.wasm" \
  --out "$PLUGIN_SAMPLE_BUILD/public-turn-count.json"

roundtable-studio plugin catalog --name 圆桌精选 \
  --out "$PLUGIN_SAMPLE_BUILD/catalog.json" \
  "$PLUGIN_SAMPLE_BUILD/deliberation-checklist.json" \
  "$PLUGIN_SAMPLE_BUILD/public-turn-count.json"

diff -rq internal/plugins/builtin "$PLUGIN_SAMPLE_BUILD" \
  --exclude public-turn-count.wasm
```

三个生成的 JSON 文件可一起放入静态网站的同一目录。订阅地址指向其中的 `catalog.json`。完整格式与发布步骤见 [插件作者指南](../../docs/plugins.md)。
