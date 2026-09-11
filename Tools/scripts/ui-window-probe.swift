import CoreGraphics
import Darwin
import Foundation

guard CommandLine.arguments.count == 3,
      let rawPID = Int32(CommandLine.arguments[1]),
      let timeout = TimeInterval(CommandLine.arguments[2]),
      rawPID > 0,
      timeout > 0 else {
    fputs("usage: ui-window-probe.swift <pid> <timeout-seconds>\n", stderr)
    exit(2)
}

let processID = pid_t(rawPID)
let deadline = Date().addingTimeInterval(timeout)

while Date() < deadline {
    if Darwin.kill(processID, 0) != 0, errno == ESRCH {
        fputs("Sci-Station exited before its main window became visible.\n", stderr)
        exit(1)
    }

    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    for window in windowInfo {
        let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue
        let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0
        guard ownerPID == rawPID, layer == 0, alpha > 0.05,
              let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
              bounds.width >= 680,
              bounds.height >= 460 else {
            continue
        }

        print(
            "SCI_STATION_UI_SMOKE_OK pid=\(rawPID) "
                + "width=\(Int(bounds.width)) height=\(Int(bounds.height))"
        )
        exit(0)
    }

    Thread.sleep(forTimeInterval: 0.2)
}

fputs("Sci-Station did not expose a visible main window before timeout.\n", stderr)
exit(1)
