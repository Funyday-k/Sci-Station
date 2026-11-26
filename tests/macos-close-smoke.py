"""Exercise the packaged app and isolated AppKit gestures on a macOS login session."""
import concurrent.futures
import contextlib
import fcntl
import http.server
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "tests" / "macos-close-driver.m"
# The service gets eight seconds to drain. Allow two more for AppKit and scheduling.
EXIT_DEADLINE = 10
LOCAL = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def free_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def api(port, path, payload=None, timeout=3):
    origin = f"http://127.0.0.1:{port}"
    request = urllib.request.Request(origin + path, data=None if payload is None else json.dumps(payload).encode(),
                                     headers={"Origin": origin, "Content-Type": "application/json", "X-Roundtable": "1"})
    try:
        with LOCAL.open(request, timeout=timeout) as reply:
            return json.load(reply)
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"{path} returned {exc.code}: {exc.read(256)!r}") from exc


def healthy(port):
    try:
        return api(port, "/api/health", timeout=.4)["name"] == "sci-station"
    except (OSError, urllib.error.URLError):
        return False


def wait_for(proc, description, predicate, timeout=30):
    deadline = time.monotonic() + timeout
    while proc.poll() is None and time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.025)
    raise RuntimeError(f"PID {proc.pid}: {description}, exit={proc.poll()}")


@contextlib.contextmanager
def launch(binary, directory, port, mode, gesture=None):
    # Go, CFPreferences, and Magpie must all see an empty user environment.
    test_home = directory.parent / "home"
    test_home.mkdir(exist_ok=True)
    system_settings = test_home / ".config/magpie/settings.json"
    if not system_settings.exists():
        system_settings.parent.mkdir(parents=True)
        system_settings.write_text(json.dumps({"port": free_port()}))
    env = {"SCI_STATION_WORKSPACE_REGISTRY": str(directory.parent / "registry"), "HOME": str(test_home), "CFFIXED_USER_HOME": str(test_home),
           "XDG_CONFIG_HOME": str(test_home / ".config"), "PATH": "/usr/bin:/bin"}
    marker = directory.parent / "gesture"
    for path in (marker, marker.with_suffix(".ready"), marker.with_suffix(".go")):
        path.unlink(missing_ok=True)
    if gesture:
        env["SCI_STATION_TEST_DISPLAY"] = os.getenv("SCI_STATION_TEST_DISPLAY", "secondary")
        env.update(SCI_STATION_TEST_GESTURE=gesture, SCI_STATION_TEST_GESTURE_MARKER=str(marker))
    command = [str(binary), mode, "-port", str(port), "-data-dir", str(directory)]
    with subprocess.Popen(command, env=env) as proc:
        try:
            wait_for(proc, "service did not start", lambda: healthy(port))
            if gesture:
                wait_for(proc, "window did not appear", marker.with_suffix(".ready").exists)
            yield proc, marker
        finally:
            if proc.poll() is None:
                proc.kill()


def clean_exit(proc, started):
    status = proc.wait(timeout=max(.01, EXIT_DEADLINE - (time.monotonic() - started)))
    elapsed = time.monotonic() - started
    if status != 0 or elapsed > EXIT_DEADLINE:
        raise RuntimeError(f"PID {proc.pid} exited with {status} after {elapsed:.2f}s")
    return elapsed


def perform_gesture(proc, marker, gesture):
    marker.with_suffix(".go").touch()
    # A sheet may still be opening. Time the actual action separately.
    deadline = time.monotonic() + 10
    while not marker.exists() and time.monotonic() < deadline and proc.poll() is None:
        time.sleep(.01)
    if not marker.exists() or marker.read_text() != gesture:
        raise RuntimeError(f"PID {proc.pid} did not issue {gesture}")
    return clean_exit(proc, time.monotonic() - max(0, time.time() - marker.stat().st_mtime))


def released(directory, port):
    with socket.socket() as probe:
        if probe.connect_ex(("127.0.0.1", port)) == 0:
            raise RuntimeError("HTTP port remained active after closing its owner")
    with (directory / ".studio-process.lock").open("rb") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)


def assert_note(port, notes_url, note):
    saved = api(port, notes_url + "/" + note["id"])
    if (saved["title"], saved["body"]) != (note["title"], note["body"]):
        raise RuntimeError("Committed note changed after relaunch")


class BlockedModel(http.server.BaseHTTPRequestHandler):
    """A loopback-only model whose response cannot finish before cancellation."""
    def do_GET(self):
        if self.path != "/v1/models":
            self.send_error(404)
            return
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"data":[{"id":"codex/close-fixture"}]}')

    def do_POST(self):
        if self.path != "/v1/chat/completions":
            self.send_error(404)
            return
        self.rfile.read(int(self.headers["Content-Length"]))
        self.server.started.set()
        self.connection.settimeout(20)
        if self.connection.recv(1) == b"":
            self.server.disconnected.set()

    def log_message(self, *args):
        pass


def process_gone(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    return False


def active_close(binary, directory, port, gesture, project, gateway, notes_url, note, pool):
    # Exercise two independent cancellation paths: a real meeting with a blocked
    # loopback transport and a diagnostics request with a CLI and its child.
    cli = directory.parent / "codex"
    pids = directory.parent / "fixture.pids"
    pids.unlink(missing_ok=True)
    cli.write_text('#!/bin/sh\ntrap "" TERM\n/bin/sleep 30 &\nprintf "%s %s" "$$" "$!" > "$(dirname "$0")/fixture.pids"\nwait\n')
    cli.chmod(0o700)
    gateway.started.clear()
    gateway.disconnected.clear()
    with launch(binary, directory, port, "app", gesture) as (proc, marker):
        assert_note(port, notes_url, note)
        api(port, "/api/studio/settings", {"models": {"codex": "close-fixture"}, "magpie_port": gateway.server_port})
        session = api(port, "/api/studio/sessions", {"topic": f"Test {gesture}", "project": project, "seats": ["codex"]})
        url = "/api/studio/sessions/" + session["id"]
        api(port, url + "/run", {"target": "codex", "expected_round": 0, "allow_edits": False})
        wait_for(proc, "model request did not start", gateway.started.is_set)
        request = pool.submit(api, port, "/api/studio/diagnostics",
                              {"target": "codex", "codex_transport": "direct", "cli_paths": {"codex": str(cli)}}, 15)
        wait_for(proc, "CLI process tree did not start", lambda: pids.exists() and len(pids.read_text().split()) == 2)
        tree = list(map(int, pids.read_text().split()))
        if any(process_gone(pid) for pid in tree):
            raise RuntimeError("CLI tree exited before the gesture")
        elapsed = perform_gesture(proc, marker, gesture)
        # The closed request can return cancellation or lose its connection.
        with contextlib.suppress(RuntimeError, OSError):
            request.result(timeout=2)
        if not gateway.disconnected.wait(1) or not all(process_gone(pid) for pid in tree):
            raise RuntimeError(f"Model connection or CLI tree {tree} survived shutdown")
        owner = proc.pid
    released(directory, port)
    # Check that the process durably finalized the interrupted turn before exit.
    archive = json.loads((directory / "studio" / (session["id"] + ".json")).read_bytes())
    if archive["status"] != "partial" or len(archive["rounds"]) != 1:
        raise RuntimeError(f"Unexpected on-disk session after shutdown: {archive['status']}")
    with launch(binary, directory, port, "app", "launch-q") as (proc, marker):
        assert_note(port, notes_url, note)
        restored = api(port, url)
        if restored["status"] != archive["status"] or restored["rounds"] != archive["rounds"]:
            raise RuntimeError("Relaunch changed the saved meeting or replayed a turn")
        perform_gesture(proc, marker, "launch-q")
    released(directory, port)
    print(f"PASS active {gesture}: PID {owner} exited in {elapsed:.2f}s, CLI tree {tree} released, "
          f"port {port} and lock reacquired, note and meeting restored by PID {proc.pid}", flush=True)


def main():
    bundle = Path(sys.argv[1]).resolve(strict=True)
    plist = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    executable = Path("Contents/MacOS") / plist["CFBundleExecutable"]
    binary = bundle / executable
    with tempfile.TemporaryDirectory(prefix="sci-close-", dir="/tmp") as tmp:
        tmp = Path(tmp).resolve()
        quit_app = tmp / "quit"
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-DSCI_REQUEST_QUIT", "-framework", "AppKit",
                        str(DRIVER), "-o", str(quit_app)], check=True)
        port = free_port()
        directory = tmp / "packaged-data"
        with launch(binary, directory, port, "app") as (proc, _):
            project = api(port, "/api/research/projects", {"name": "Close smoke fixture"})
            notes_url = "/api/research/projects/" + project["id"] + "/notes"
            note = api(port, notes_url, {"title": "Committed before shutdown", "body": "Offline fixture"})
            wait_for(proc, "AppKit could not request Quit",
                     lambda: subprocess.run([str(quit_app), str(proc.pid)]).returncode == 0)
            elapsed = clean_exit(proc, time.monotonic())
        released(directory, port)
        print(f"PASS packaged app Quit, PID {proc.pid} exited in {elapsed:.2f}s, port and data lock released", flush=True)

        # Link the AppKit driver only into a signed copy, built with the same deployment target.
        fixture = tmp / "Sci-Station.app"
        shutil.copytree(bundle, fixture)
        test_binary = fixture / executable
        driver_obj = tmp / "gestures.o"
        target = plist["LSMinimumSystemVersion"]
        deployment = f"-mmacosx-version-min={target}"
        subprocess.run(["xcrun", "clang", "-fobjc-arc", deployment,
                        "-c", str(DRIVER), "-o", str(driver_obj)], check=True)
        build_env = dict(os.environ, MACOSX_DEPLOYMENT_TARGET=target, CGO_CFLAGS=deployment, CGO_LDFLAGS=deployment)
        subprocess.run(["go", "build", "-tags", "production", "-trimpath", "-ldflags",
                        f"-linkmode external -extldflags={driver_obj}", "-o", str(test_binary), "./cmd/sci-station"],
                       cwd=ROOT, env=build_env, check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(fixture)], check=True)
        for gesture in ("red", "cmd-w", "cmd-q", "launch-q"):
            with launch(test_binary, directory, port, "app", gesture) as (proc, marker):
                assert_note(port, notes_url, note)
                elapsed = perform_gesture(proc, marker, gesture)
            released(directory, port)
            print(f"PASS idle {gesture}: PID {proc.pid} exited in {elapsed:.2f}s, port and data lock released", flush=True)

        with concurrent.futures.ThreadPoolExecutor() as pool:
            with http.server.ThreadingHTTPServer(("127.0.0.1", 0), BlockedModel) as server:
                server.started, server.disconnected = threading.Event(), threading.Event()
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()
                try:
                    for gesture in ("red", "cmd-w", "cmd-q"):
                        active_close(test_binary, directory, port, gesture, project["path"], server, notes_url, note, pool)
                finally:
                    server.shutdown()
                    thread.join()

            with launch(test_binary, directory, port, "app", "picker-q") as (proc, marker):
                pending = pool.submit(api, port, "/api/studio/pick-project", {}, 15)
                elapsed = perform_gesture(proc, marker, "picker-q")
                selection = pending.result(timeout=2)
                if selection.get("path") != "":
                    raise RuntimeError("Quit accepted an open folder picker")
            released(directory, port)
            print(f"PASS Quit with native folder sheet: PID {proc.pid} exited in {elapsed:.2f}s", flush=True)

        with launch(binary, directory, port, "serve") as (owner, _):
            assert_note(port, notes_url, note)
            with launch(test_binary, directory, port, "app", "red") as (attached, marker):
                perform_gesture(attached, marker, "red")
            if owner.poll() is not None or not healthy(port):
                raise RuntimeError("The attached window stopped the server it borrowed")
            started = time.monotonic()
            owner.send_signal(signal.SIGTERM)
            clean_exit(owner, started)
        released(directory, port)
        print("PASS attached window preserves server ownership", flush=True)


if __name__ == "__main__":
    main()
