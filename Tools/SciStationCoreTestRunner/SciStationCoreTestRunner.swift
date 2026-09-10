import Foundation
import CoreGraphics
import SciStationCore

@main
struct SciStationCoreTestRunner {
    static func main() async {
        let summary = await CoreVerificationSuite().runAll()
        fputs(
            "[SUMMARY] matched=\(summary.executed) passed=\(summary.passed) failed=\(summary.failures.count)\n",
            stderr
        )
        fflush(stderr)

        guard summary.executed > 0 else {
            fputs("No core checks matched the requested suite/filter.\n", stderr)
            Foundation.exit(2)
        }

        if summary.failures.isEmpty {
            print("All SciStation core checks passed.")
        } else {
            fputs("SciStation core checks failed; see [FAIL] entries above.\n", stderr)
            Foundation.exit(1)
        }
    }
}
