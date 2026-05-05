from __future__ import annotations

import json
from typing import BinaryIO, Iterator

from .schemas import JsonDict


class StdioJsonRpcTransport:
    def __init__(self, reader: BinaryIO, writer: BinaryIO) -> None:
        self.reader = reader
        self.writer = writer

    def iter_messages(self) -> Iterator[JsonDict]:
        while True:
            line = self.reader.readline()
            if not line:
                return
            stripped = line.strip()
            if not stripped:
                continue
            yield json.loads(stripped.decode("utf-8"))

    def send(self, message: JsonDict) -> None:
        data = json.dumps(message, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"
        self.writer.write(data)
        self.writer.flush()

    def send_notification(self, method: str, params: JsonDict) -> None:
        self.send({"jsonrpc": "2.0", "method": method, "params": params})
