from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from .server import SidecarServer
from .transport.stdio_jsonrpc import StdioJsonRpcTransport


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="sci-station-agent")
    parser.add_argument("--fixture", default=os.environ.get("SCI_STATION_FAKE_SIDECAR_FIXTURE"))
    parser.add_argument("--development", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    fixture_path = Path(args.fixture).expanduser().resolve() if args.fixture else None
    server = SidecarServer(fixture_path=fixture_path, development_mode=args.development)
    transport = StdioJsonRpcTransport(sys.stdin.buffer, sys.stdout.buffer)

    for message in transport.iter_messages():
        response = server.handle(message)
        if response is not None:
            transport.send(response)
        server.flush_notifications(transport)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
