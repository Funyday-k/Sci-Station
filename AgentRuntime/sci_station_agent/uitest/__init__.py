"""AI Usage Test orchestrator (`Proposal-AT.md`).

Drives a Sci-Station App instance through scenarios authored as YAML/JSON,
collects three independent verification streams (debug events, persisted
files, screenshots) and produces a markdown run report.

This package only ships the *skeleton* in the first slice (P-AT.2):
- :class:`Scenario` data model + loader
- :class:`EventLogProbe` reading ``.sci-station/debug/app_events.jsonl``
- :class:`FileProbe` reading workspace-local YAML/JSONL artifacts
- :class:`ScenarioRunner` orchestrator that wires them together

The accessibility-API and XCUITest drivers plug into the orchestrator via
:class:`sci_station_agent.uitest.drivers.base.UIDriver`; unsupported drivers
should fail explicitly through the driver interface.
"""

from sci_station_agent.uitest.scenario import (
    Assertion,
    Scenario,
    Step,
    load_scenario,
)
from sci_station_agent.uitest.events import (
    DebugEvent,
    EventLogProbe,
    EventQuery,
)
from sci_station_agent.uitest.files import (
    FileProbe,
    PersistedFile,
    SWIFTUI_WARNINGS_RELATIVE_PATH,
    SwiftUIWarning,
    parse_swiftui_warnings_log,
)
from sci_station_agent.uitest.drivers import (
    AccessibilityDriver,
    DEFAULT_BUNDLE_ID,
    DriverError,
    NullDriver,
    PipeTransport,
    StubTransport,
    SubprocessTransport,
    Transport,
    UIDriver,
)
from sci_station_agent.uitest.runner import (
    AssertionOutcome,
    ScenarioRunResult,
    ScenarioRunner,
)
from sci_station_agent.uitest.test_bridge import (
    StubTestBridgeClient,
    TestBridgeClient,
    TestBridgeError,
    UnixSocketTestBridgeClient,
)

__all__ = [
    "AccessibilityDriver",
    "Assertion",
    "AssertionOutcome",
    "DEFAULT_BUNDLE_ID",
    "DebugEvent",
    "DriverError",
    "EventLogProbe",
    "EventQuery",
    "FileProbe",
    "NullDriver",
    "PersistedFile",
    "PipeTransport",
    "SWIFTUI_WARNINGS_RELATIVE_PATH",
    "Scenario",
    "ScenarioRunResult",
    "ScenarioRunner",
    "Step",
    "StubTransport",
    "StubTestBridgeClient",
    "SubprocessTransport",
    "SwiftUIWarning",
    "TestBridgeClient",
    "TestBridgeError",
    "Transport",
    "UIDriver",
    "UnixSocketTestBridgeClient",
    "load_scenario",
    "parse_swiftui_warnings_log",
]
