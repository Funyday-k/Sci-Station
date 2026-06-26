import pytest

from sci_station_agent.mcp_client.sci_station_gateway import ApprovalRequired, SciStationGatewayClient


class RecordingRequester:
    def __init__(self, responses):
        self.responses = list(responses)
        self.requests = []

    def request(self, method: str, params: dict) -> dict:
        self.requests.append((method, params))
        assert self.responses, f"Unexpected JSON-RPC request: {method} {params}"
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


def test_gateway_lists_tools_with_swift_mcp_contract() -> None:
    requester = RecordingRequester([
        {
            "tools": [
                {
                    "name": "read_note",
                    "description": "Read a note",
                    "inputSchema": {"type": "object"},
                    "annotations": {"readOnly": True},
                }
            ]
        }
    ])
    client = SciStationGatewayClient(requester)

    result = client.list_tools()

    assert requester.requests == [("tools/list", {})]
    assert result["tools"][0]["name"] == "read_note"
    assert result["tools"][0]["annotations"]["readOnly"] is True


def test_gateway_calls_tool_with_name_and_arguments_contract() -> None:
    requester = RecordingRequester([
        {
            "content": [{"type": "text", "text": "remote:paper"}],
            "structuredContent": {"query": "paper"},
            "isError": False,
        }
    ])
    client = SciStationGatewayClient(requester)

    result = client.call_tool("lookup", {"query": "paper"})

    assert requester.requests == [("tools/call", {"name": "lookup", "arguments": {"query": "paper"}})]
    assert result["content"][0]["text"] == "remote:paper"
    assert result["structuredContent"]["query"] == "paper"


def test_gateway_defaults_missing_arguments_to_empty_object() -> None:
    requester = RecordingRequester([{"content": [], "isError": False}])
    client = SciStationGatewayClient(requester)

    client.call_tool("ping")

    assert requester.requests == [("tools/call", {"name": "ping", "arguments": {}})]


def test_gateway_surfaces_swift_approval_required_payload() -> None:
    approval_payload = {
        "status": "approval_required",
        "approvalRequest": {
            "id": "approval-1",
            "tool": "create_todo",
            "targetPaths": ["tasks/todos.yaml"],
            "risk": "writes_workspace",
        },
    }
    requester = RecordingRequester([approval_payload])
    client = SciStationGatewayClient(requester)

    with pytest.raises(ApprovalRequired) as raised:
        client.call_tool("create_todo", {"title": "Review MCP contract"})

    assert requester.requests == [
        ("tools/call", {"name": "create_todo", "arguments": {"title": "Review MCP contract"}})
    ]
    assert raised.value.result == approval_payload
