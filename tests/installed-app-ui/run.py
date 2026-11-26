"""Run the standalone Xcode UI test against the verified installation path."""

import argparse
import os
from pathlib import Path
import plistlib
import subprocess


PROJECT = Path(__file__).resolve().with_name("InstalledAppUI.xcodeproj")
DESTINATION = "platform=macOS,arch=arm64"


def build_runner(build_dir):
    products = build_dir / "Build" / "Products"
    specifications = list(products.glob("InstalledAppUI_*.xctestrun"))
    if not specifications:
        subprocess.run([
            "xcodebuild", "-project", str(PROJECT), "-scheme", "InstalledAppUI",
            "-destination", DESTINATION, "-derivedDataPath", str(build_dir),
            "-quiet", "build-for-testing",
        ], check=True)
        specifications = list(products.glob("InstalledAppUI_*.xctestrun"))
    if len(specifications) != 1:
        raise RuntimeError(f"Expected one Xcode UI test specification in {products}")
    return specifications[0]


def configure(specification, environment, phase):
    with specification.open("rb") as stream:
        settings = plistlib.load(stream)

    targets = []

    def find_targets(value):
        if isinstance(value, dict):
            if "TestBundlePath" in value:
                targets.append(value)
            for item in value.values():
                find_targets(item)
        elif isinstance(value, list):
            for item in value:
                find_targets(item)

    find_targets(settings)
    if len(targets) != 1:
        raise RuntimeError("The installed app UI runner must contain exactly one test target")
    targets[0].setdefault("EnvironmentVariables", {}).update(environment)
    # Keep the generated and configured files adjacent so __TESTROOT__ is unchanged.
    configured = specification.with_name(f"InstalledApp-{phase}.xctestrun")
    with configured.open("wb") as stream:
        plistlib.dump(settings, stream)
    return configured


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("fixture", type=Path)
    parser.add_argument("phase", choices=["initial", "upgraded"])
    parser.add_argument("archive", choices=["zip", "dmg"])
    args = parser.parse_args()

    fixture = args.fixture.resolve(strict=True)
    profile = fixture / "installed-ui-profile"
    (profile / "home").mkdir(parents=True, exist_ok=True)
    (profile / "tmp").mkdir(parents=True, exist_ok=True)
    specification = build_runner(fixture / "installed-ui-build")
    configured = configure(specification, {
        "SCI_STATION_INSTALLED_UI_APP": str(args.app.resolve(strict=True)),
        "SCI_STATION_INSTALLED_UI_PROFILE": str(profile),
        "SCI_STATION_INSTALLED_UI_ROOT": str(fixture / "research-root"),
        "SCI_STATION_INSTALLED_UI_REGISTRY": str(fixture / "workspace-registry"),
    }, args.phase)
    result_dir = Path(os.environ.get("SCI_STATION_INSTALLED_UI_RESULTS_DIR", str(fixture)))
    result_dir.mkdir(parents=True, exist_ok=True)
    result_bundle = result_dir / f"{args.archive}-{args.phase}.xcresult"
    try:
        subprocess.run([
            "xcodebuild", "-xctestrun", str(configured), "-destination", DESTINATION,
            "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
            "-maximum-test-execution-time-allowance", "120",
            "-resultBundlePath", str(result_bundle),
            "test-without-building",
        ], check=True, timeout=180)
    except subprocess.TimeoutExpired:
        raise SystemExit("Installed-app XCTest timed out. Check the graphical session's Xcode automation mode.") from None


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
