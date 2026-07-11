# `sci_station_agent.uitest`

Python 编排器，驱动 Sci-Station App 跑 UI smoke 场景并比对 3 条独立断言通道（事件 / 文件 / 视觉）。

全局测试与发布约定见 `docs/DEVELOPER.md`。该 README 负责 UI smoke 编排器的安装、场景规则和运行方法。

## 安装

```bash
# 在 repo 根目录
.venv/bin/python -m pip install -e AgentRuntime[test,uitest]
```

`uitest` extras 仅追加 `pyyaml`。

## 跑测试

```bash
cd AgentRuntime
../.venv/bin/python -m pytest tests/uitest/ -q
```

测试应全部通过；如果数量变化，以 pytest 输出为准。

## 写一个新场景

1. 在 `sci_station_agent/uitest/scenarios/<scenario-id>_<slug>.yaml` 新建文件；每个场景必须使用稳定的 accessibility identifier，并覆盖事件、文件或视觉通道中的至少一个可验证结果。
2. 用到的 accessibility identifier 必须先在
   `Sci-Station/Testing/UITestAccessibilityID.swift` 登记。
3. 期待的事件必须先在
   `Sci-Station/Agent/AppDebugEventName.swift` 登记，并在
   `Tools/SciStationCoreTestRunner/main.swift::emittedEventAllowList`
   追加 raw value。
4. 准备一个最小复现 workspace，让 NullDriver 或真实 driver 都能跑通。

## 模块约定

```text
scenario.py    Scenario / Step / Assertion 数据类 + JSON/YAML loader
events.py      EventLogProbe (read app_events.jsonl)
files.py       FileProbe (read workspace yaml/jsonl/md, 子集匹配)
runner.py      ScenarioRunner: 驱动 step + 串联 probe + 出 result
report.py      渲染 markdown 报告（输出到调用方指定的本地路径）
drivers/       UIDriver 协议 + NullDriver + Accessibility/XCUITest 适配
scenarios/     YAML / JSON 场景库
```

## 使用真驱动

1. 构建 AX 探针：

   ```bash
   swift build --product SciStationUIProbe
   ```

2. 一次性给探针 Accessibility 权限：

   ```bash
   .build/debug/SciStationUIProbe
   # → 第一次跑会被 macOS 提示"<binary> 想要控制您的电脑"
   # → System Settings → Privacy & Security → Accessibility 勾选
   ```

3. 启动 App 时打开 Debug-only Test Bridge，并在场景里换驱动：

   ```python
   from sci_station_agent.uitest import (
       AccessibilityDriver,
       ScenarioRunner,
       UnixSocketTestBridgeClient,
       load_scenario,
   )

   socket_path = "/tmp/sci-station-uitest.sock"
   driver = AccessibilityDriver(
       bundle_id="Lingyu-Xia.Sci-Station",
       test_bridge=UnixSocketTestBridgeClient(socket_path),
   )
   driver.launch(
       args=["--uitest-bridge", "--uitest-bridge-socket", socket_path],
       wait=True,
   )
   runner = ScenarioRunner(research_root, driver=driver)
   result = runner.run(load_scenario("scenarios/MT02-01_import_pdf.yaml"))
   driver.terminate()
   driver.close()
   ```

驱动也可以用 ``StubTransport`` / ``PipeTransport`` 注入假响应，方便在 CI 上跑
不依赖 GUI 的契约测试。

## 当前限制

```text
- 需要 click/type/drag 的真实场景依赖 macOS Accessibility trust。
- send_test_bridge 需要传入 TestBridgeClient；当前实现支持 UnixSocketTestBridgeClient。
- 视觉通道应作为 smoke 辅助信号，不应替代事件和文件断言。
```
