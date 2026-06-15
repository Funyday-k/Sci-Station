"""Driver implementations for the AI Usage Test orchestrator.

* :class:`UIDriver` -- abstract protocol all drivers conform to.
* :class:`NullDriver` -- record-only driver used in unit tests.
* :class:`AccessibilityDriver` -- macOS Accessibility API driver backed
  by the ``Tools/SciStationUIProbe`` Swift helper.
* (Future) ``XCUITestDriver`` -- shells out to an XCUITest target.
"""

from sci_station_agent.uitest.drivers.accessibility import (
    DEFAULT_BUNDLE_ID,
    AccessibilityDriver,
    PipeTransport,
    StubTransport,
    SubprocessTransport,
    Transport,
)
from sci_station_agent.uitest.drivers.base import (
    DriverError,
    NullDriver,
    UIDriver,
)

__all__ = [
    "AccessibilityDriver",
    "DEFAULT_BUNDLE_ID",
    "DriverError",
    "NullDriver",
    "PipeTransport",
    "StubTransport",
    "SubprocessTransport",
    "Transport",
    "UIDriver",
]
