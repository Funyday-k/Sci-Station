# `sci_station_agent.uitest`

Python 编排器，驱动 Sci-Station App 跑 manual-test 用例并比对 3 条独立断言通道（事件 / 文件 / 视觉）。

完整设计见 `DOC/Proposal-AT.md`。该 README 只负责让一个新加入的人在 5 分钟内把测试跑起来。

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

应该看到 `22 passed` (启用 PyYAML 的情况下)。

## 写一个新场景

1. 在 `sci_station_agent/uitest/scenarios/MT-xx-YY_<slug>.yaml` 新建文件，
   schema 见 `DOC/Proposal-AT.md` §5。
2. 用到的 accessibility identifier 必须先在
   `Sci-Station/Testing/UITestAccessibilityID.swift` 登记。
3. 期待的事件必须先在
   `Sci-Station/Agent/AppDebugEventName.swift` 登记，并在
   `Tools/SciStationCoreTestRunner/main.swift::emittedEventAllowList`
   追加 raw value。
4. 在 `tests/uitest/test_runner_smoke.py` 旁边复制一份 `_seed_workspace`
   工具方法，准备一个最小复现 workspace 让 NullDriver 跑通；
   实驱动落地（P-AT.3）后这一步可以删掉。

## 模块约定

```text
scenario.py    Scenario / Step / Assertion 数据类 + JSON/YAML loader
events.py      EventLogProbe (read app_events.jsonl)
files.py       FileProbe (read workspace yaml/jsonl/md, 子集匹配)
runner.py      ScenarioRunner: 驱动 step + 串联 probe + 出 result
report.py      渲染 markdown 报告（DOC/manual-tests/runs/...md）
drivers/       UIDriver 协议 + NullDriver；P-AT.3 加 Accessibility/XCUITest
scenarios/     YAML / JSON 场景库（与 DOC/manual-tests/MT-*.md 一对一）
```

## 使用真驱动 (P-AT.3a)

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

3. 启动 App 时打开 Debug-only Test Bridge（P-AT.1e），并在场景里换驱动：

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
- drag 暂未实现（CGEvent 链路留 P-AT.3b）；
  AccessibilityDriver.drag() 抛 DriverError。
- send_test_bridge 需要传入 TestBridgeClient；
  当前实现支持 UnixSocketTestBridgeClient。
- 视觉通道：visual assertion 恒 fail；
  SwiftUI runtime warning 已通过 file 通道断言（参考
  MT02-01 第 3 条 assertion）。完整 baseline diff 等 P-AT.4。
```
