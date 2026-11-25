"""Exercise the packaged app and isolated AppKit gestures on a macOS login session."""
import contextlib
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "tests" / "macos-close-driver.m"


def free_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def healthy(port):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/health", timeout=.4) as reply:
            return json.load(reply)["name"] == "sci-station"
    except (OSError, urllib.error.URLError):
        return False


def wait_ready(proc, port):
    for _ in range(200):
        if proc.poll() is not None:
            break
        if healthy(port):
            return
        time.sleep(.1)
    raise RuntimeError("Owned test service failed to start")


@contextlib.contextmanager
def launch(binary, directory, port, mode, gesture=None):
    command = [str(binary), mode, "-port", str(port), "-data-dir", str(directory)]
    env = os.environ.copy()
    env.pop("SCI_STATION_TEST_GESTURE", None)
    if gesture:
        marker = directory.parent / f"{gesture}-invoked"
        marker.unlink(missing_ok=True)
        env["SCI_STATION_TEST_GESTURE"] = gesture
        env["SCI_STATION_TEST_GESTURE_MARKER"] = str(marker)
    # Keep stderr attached to the CI log. Kill only this fixture if it hangs.
    with subprocess.Popen(command, env=env) as proc:
        try:
            yield proc
            if gesture and (not marker.exists() or marker.read_text() != gesture):
                raise RuntimeError(f"Test app exited before invoking {gesture}")
        finally:
            if proc.poll() is None:
                proc.kill()


def clean_exit(proc):
    status = proc.wait(timeout=35)
    if status != 0:
        raise RuntimeError(f"Unexpected fixture exit code {status}")


def released(directory, port):
    with socket.socket() as probe:
        if probe.connect_ex(("127.0.0.1", port)) == 0:
            raise RuntimeError("HTTP port remained active after closing its owner")
    with (directory / ".studio-process.lock").open("rb") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)


def main():
    bundle = Path(sys.argv[1]).resolve(strict=True)
    binary = bundle / "Contents/MacOS/sci-station"
    with tempfile.TemporaryDirectory(prefix="sci-close-", dir="/tmp") as tmp:
        tmp = Path(tmp)
        quit_app = tmp / "quit"
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-DSCI_REQUEST_QUIT", "-framework", "AppKit",
                        str(DRIVER), "-o", str(quit_app)], check=True)
        port = free_port()
        directory = tmp / "packaged-data"
        with launch(binary, directory, port, "app") as proc:
            wait_ready(proc, port)
            # A SIGTERM can bypass the native Quit route. Request termination
            # through AppKit, scoped to this subprocess PID.
            for _ in range(100):
                if subprocess.run([str(quit_app), str(proc.pid)]).returncode == 0:
                    break
                time.sleep(.1)
            else:
                raise RuntimeError("AppKit could not send Quit to the packaged app")
            clean_exit(proc)
        released(directory, port)
        print("PASS packaged app Quit, process, port and data lock", flush=True)

        # Build the same desktop entry point with a test-only AppKit driver.
        # Re-sign the copied bundle and keep the supplied release binary intact.
        fixture = tmp / "Sci-Station.app"
        shutil.copytree(bundle, fixture)
        test_binary = fixture / "Contents/MacOS/sci-station"
        driver_obj = tmp / "gestures.o"
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-mmacosx-version-min=12.0",
                        "-c", str(DRIVER), "-o", str(driver_obj)], check=True)
        subprocess.run(["go", "build", "-tags", "production", "-trimpath", "-ldflags",
                        f"-linkmode external -extldflags={driver_obj}", "-o", str(test_binary), "."],
                       cwd=ROOT, check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(fixture)], check=True)
        for gesture in ("red", "cmd-w", "cmd-q"):
            with launch(test_binary, directory, port, "app", gesture) as proc:
                wait_ready(proc, port)
                clean_exit(proc)
            released(directory, port)
            print(f"PASS {gesture}, process, port and data lock", flush=True)

        # Reuse the exact port and data directory to exercise a real second
        # process. Closing its window must leave the original server usable.
        with launch(binary, directory, port, "serve") as owner:
            wait_ready(owner, port)
            with launch(test_binary, directory, port, "app", "red") as attached:
                clean_exit(attached)
            if owner.poll() is not None or not healthy(port):
                raise RuntimeError("The attached window stopped the server it borrowed")
            owner.send_signal(signal.SIGTERM)
            clean_exit(owner)
        released(directory, port)
        print("PASS attached window preserves server ownership", flush=True)


if __name__ == "__main__":
    main()
