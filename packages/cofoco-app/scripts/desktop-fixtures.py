#!/usr/bin/env python3
"""Isolated desktop smoke fixtures; never prints a Keychain bearer secret.

Start the DEBUG app with the same com.fromshim.cofoco.desktop-smoke.*
Keychain namespace first. This is a local MCP protocol client, not a real
Claude/Codex provider integration and not an owner-approval bypass.
"""
import argparse
import json
import subprocess
import urllib.request
import uuid

parser = argparse.ArgumentParser()
parser.add_argument("mode", choices=["propose", "capture", "inspect", "revoke"])
parser.add_argument("--keychain-service", required=True)
args = parser.parse_args()
if not args.keychain_service.startswith("com.fromshim.cofoco.desktop-smoke."):
    parser.error("an isolated desktop-smoke Keychain namespace is required")

def secret(account):
    result = subprocess.run(["security", "find-generic-password", "-s", args.keychain_service,
                             "-a", account, "-w"], capture_output=True, check=True)
    return result.stdout.decode().strip()

owner = secret("owner-local")

def request(method, path, body=None, token=owner):
    headers = {"Authorization": "Bearer " + token, "Accept": "application/json"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request("http://127.0.0.1:57321" + path,
        data=None if body is None else json.dumps(body).encode(), headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.load(response)

todos = request("GET", "/v1/owner/todos?include_deleted=true")["todos"]
fixtures = [todo for todo in todos if todo["title"].startswith("앱 UI")]
if not fixtures:
    raise SystemExit("Create the '앱 UI 스모크 테스트' fixture in the isolated app first.")

if args.mode in ["propose", "capture"]:
    integration = "desktop-smoke-agent"
    request("POST", "/v1/owner/integrations", {"id": integration, "scopes": ["personal"],
             "idempotency_key": str(uuid.uuid4())})
    token = integration + "." + secret("integration:" + integration)
    request("POST", "/mcp", {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "isolated-desktop-smoke", "version": "1"}}}, token)
    target = fixtures[0]
    tool = "cofoco_update_todo" if args.mode == "propose" else "cofoco_create_todo"
    arguments = {"id": target["id"], "expected_revision": target["revision"],
        "title": "앱 UI 승인 완료", "reason": "네이티브 승인 화면 검증", "idempotency_key": str(uuid.uuid4())}
    if args.mode == "capture":
        arguments = {"scope": "personal", "explicitly_agreed": True, "title": "앱 UI 백그라운드 변경",
                     "reason": "격리된 알림 복구 검증", "idempotency_key": str(uuid.uuid4())}
    result = request("POST", "/mcp", {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {
        "name": tool, "arguments": arguments}}, token)
    outcome = json.loads(result["result"]["content"][0]["text"])
    if args.mode == "capture":
        assert outcome["outcome"] == "created", outcome
        print(json.dumps(outcome, ensure_ascii=False))
        raise SystemExit(0)
    assert outcome["outcome"] == "proposed", outcome
    assert request("GET", "/v1/owner/todos/" + target["id"])["todo"]["title"] == target["title"]
    print(json.dumps({"todo_id": target["id"], "proposal_id": outcome["proposal_id"],
                      "outcome": "proposed; original unchanged"}, ensure_ascii=False))
elif args.mode == "inspect":
    for todo in fixtures:
        detail = request("GET", "/v1/owner/todos/" + todo["id"])["todo"]
        print(json.dumps(detail, ensure_ascii=False))
    print(json.dumps(request("GET", "/v1/owner/proposals"), ensure_ascii=False))
else:
    result = request("DELETE", "/v1/owner/integrations/desktop-smoke-agent",
                     {"idempotency_key": str(uuid.uuid4())})
    print(json.dumps(result, ensure_ascii=False))
