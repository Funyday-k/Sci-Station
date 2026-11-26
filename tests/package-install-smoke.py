"""Verify an installed workstation binary against disposable fixture data."""
import fcntl
from hashlib import sha256
import json
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request


LOCAL = urllib.request.build_opener(urllib.request.ProxyHandler({}))
TASK_PATH = "/api/research/tasks"


def exercise(bundle, fixture, step):
    root = fixture / ("restored-root" if step == "rollback" else "research-root")
    executable = bundle / "Contents" / "MacOS" / "sci-station"
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    origin = f"http://127.0.0.1:{port}"
    registry_identity = sha256(str(root).encode()).hexdigest()

    def api(path, payload=None):
        request = urllib.request.Request(
            origin + path,
            data=json.dumps(payload).encode() if payload is not None else None,
            headers={"Origin": origin, "Content-Type": "application/json", "X-Roundtable": "1"},
        )
        with LOCAL.open(request, timeout=2) as response:
            return json.load(response)

    # The CLI receives a disposable research root, registry, and provider config.
    env = {
        "SCI_STATION_WORKSPACE_REGISTRY": str(fixture / "workspace-registry"),
        "XDG_CONFIG_HOME": str(fixture / "empty-provider-config"),
        "CFFIXED_USER_HOME": str(fixture),
        "PATH": "/usr/bin:/bin",
    }
    command = [str(executable), "serve", "-data-dir", str(root), "-port", str(port)]
    with subprocess.Popen(command, cwd=fixture, env=env) as child:
        try:
            deadline = time.monotonic() + 20
            while child.poll() is None and time.monotonic() < deadline:
                try:
                    health = api("/api/health")
                    if health.get("name") != "sci-station" or health.get("workspace") != registry_identity:
                        raise RuntimeError("The test port belongs to a different process or workspace")
                    break
                except urllib.error.URLError:
                    time.sleep(.05)
            else:
                raise RuntimeError("Installed workstation process did not become healthy")

            fixture_record = fixture / "original-task.json"
            if step == "initial":
                assert api(TASK_PATH) == []
                task = api(TASK_PATH, {"title": "Installed workstation fixture", "dueDate": "2026-11-25"})
                fixture_record.write_text(json.dumps(task), encoding="utf-8")
            else:
                task = json.loads(fixture_record.read_text(encoding="utf-8"))
                assert api(f"{TASK_PATH}/{task['id']}") == task, "the original task was changed"
                assert api(TASK_PATH) == [task], "unexpected tasks in the fixture"
                if step == "upgraded":
                    upgraded = api(TASK_PATH, {"title": "Written after upgrade"})
                    saved = api(f"{TASK_PATH}/{upgraded['id']}")
                    assert saved == upgraded and saved["id"] != task["id"]
        finally:
            if child.poll() is None:
                child.send_signal(signal.SIGTERM)
            try:
                status = child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
                raise
        assert status == 0, f"installed process exited with {status}"

    with socket.socket() as probe:
        assert probe.connect_ex(("127.0.0.1", port)) != 0, "HTTP port was not released"
    with (root / ".studio-process.lock").open("rb") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
    print(f"PASS installed workstation {step}: persisted fixture, process exit, port and lock", flush=True)


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[3] not in {"initial", "upgraded", "rollback"}:
        raise SystemExit("Usage: package-install-smoke.py /path/to/Sci-Station.app /path/to/fixture initial|upgraded|rollback")
    exercise(Path(sys.argv[1]).resolve(strict=True), Path(sys.argv[2]).resolve(strict=True), sys.argv[3])
