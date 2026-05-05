from __future__ import annotations

from typing import Protocol


class JsonRpcRequester(Protocol):
    def request(self, method: str, params: dict) -> dict: ...


class SciStationGatewayClient:
    def __init__(self, requester: JsonRpcRequester) -> None:
        self.requester = requester

    def list_tools(self) -> dict:
        return self.requester.request("tools/list", {})

    def call_tool(self, name: str, arguments: dict | None = None) -> dict:
        result = self.requester.request("tools/call", {"name": name, "arguments": arguments or {}})
        if result.get("status") == "approval_required":
            raise ApprovalRequired(result)
        return result


class ApprovalRequired(RuntimeError):
    def __init__(self, result: dict) -> None:
        super().__init__("Swift approval is required for this tool call.")
        self.result = result
