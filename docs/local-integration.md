# Cofoco local CLI/MCP integration — first provider

Status: **initial implementation and isolated Claude Code smoke verified; provider installer pending**
Verified: 2026-09-29 on macOS arm64

Update 2026-10-01: [the native app](native-app.md) now bundles/manages this service and exposes owner approvals/settings. The first-provider evidence below remains historical; it does not prove Codex integration or an installed provider configuration. Current suites: core 27/27, service 3/3, CLI 7/7, app 11/11.

## Implemented boundary

- `packages/cofoco-service/` hosts `CofocoCore` through owner HTTP and authenticated Streamable HTTP MCP on `127.0.0.1:57321`. It alone opens SQLite. Host/Origin checks, separate owner and integration credentials, current-grant validation, per-grant SDK contexts and serialized requests are implemented.
- `packages/cofoco-cli/` builds the `cofoco` owner executable. It calls the service; it does not open SQLite. Commands: `add`, `list`, `show`, `status`, `doctor`, `open`, and `integration grant|status|revoke|auth-header`. `open` needs the future installed app. `integration grant` stores a scoped secret in Keychain without printing it. `auth-header` is for a provider subprocess and *does* print its bearer header; never paste its output into logs or documentation.
- MCP exposes context/list/get/create/update/delete/restore/Step/Note/proposal reads. Important existing-Todo changes still go through the core's proposal policy. MCP has no owner approval method. `cofoco_propose_changes` is not yet exposed; typed within-group references remain undecided.
- The service and CLI use the system Keychain namespace `com.fromshim.cofoco` normally. `COFOCO_KEYCHAIN_SERVICE` is a DEBUG-build-only test override. The owner credential and integration secret are separate; a cwd or provider name is not an authority boundary. Personal is not available to an integration without explicit `--scope personal`.

The service package pins the official Swift MCP SDK 0.12.1 and SwiftNIO 2.101.2 in `Package.resolved`. Its per-grant transport and fresh SDK context on successful re-initialize also avoid cross-client request-ID/initialization collisions seen during the first live smoke.

## Reproduce in a disposable local environment

Build the separate packages:

```bash
swift test --package-path packages/cofoco-core
swift test --package-path packages/cofoco-service
swift test --package-path packages/cofoco-cli
swift build --package-path packages/cofoco-service
swift build --package-path packages/cofoco-cli
```

For a standalone transport smoke, run `packages/cofoco-service/.build/debug/cofoco-service --database <isolated-db-path>` in one terminal. In another, `packages/cofoco-cli/.build/debug/cofoco doctor`, then `cofoco integration grant claude-local --scope personal`. That grant explicitly permits Personal Todos for every session using this credential. Prefer an individual project scope if Personal is not intended. Normal native use now starts the helper automatically; do not run competing app/manual services.

For Claude Code, use a temporary MCP config with an absolute path to the built CLI. Its [documented `headersHelper`](https://code.claude.com/docs/en/mcp) invokes the CLI each time and avoids a bearer token in the config file:

```json
{
  "mcpServers": {
    "cofoco": {
      "type": "http",
      "url": "http://127.0.0.1:57321/mcp",
      "headersHelper": "/absolute/path/to/cofoco integration auth-header claude-local"
    }
  }
}
```

This is a manual test configuration, not an idempotent installer. It must not be copied to a global provider config without reviewing the shared grant scope. `cofoco integration revoke claude-local` revokes the service grant and removes its Keychain secret, but does not yet edit a provider config file.

## Observed evidence

- `swift test` passed: core 26/26 at the previous core checkpoint; service 2/2 and CLI 7/7 after transport implementation. The service tests cover owner/MCP separation, scoped grants/revocation, retry, concurrent matching JSON-RPC IDs across grants, and repeated/malformed initialize. Core tests separately cover policy, proposal, conflict, migration and restart behavior. Rerun counts after subsequent code changes.
- A real isolated Claude Code 2.1.284 session (Haiku 4.5) invoked `cofoco_create_todo`, `cofoco_list_todos`, `cofoco_update_todo`, and `cofoco_get_todo` against one disposable local database. It created Personal Todo `E223F7FF-ED4C-4415-B230-2BD786D45AF1`, title `Cofoco stage3 smoke validation`, then started it. Independent `cofoco show --json` returned `in_progress`, revision 2.
- With the fixed service running, a separate MCP initialize succeeded; **without restarting the service**, another real Claude Code session got that exact Todo and reported its title, status and revision. This verified the previously failing repeat-initialize path.
- The test used a separate temporary database, test-only Keychain service namespace and temporary Claude MCP config. After verification, the test grant/integration secret was revoked, the test owner Keychain item was removed and the service was stopped; the disposable database/config files remain under `/private/tmp/cofoco-stage3.sszsqo` as local evidence. No repository/provider-global MCP config was installed. No Todo was added to a production Cofoco database.

## Remaining gates

Provider config install/remove with backup and idempotency; Codex CLI live integration; complete process-boundary/platform/accessibility acceptance; signed release Keychain access; second-provider concurrent Todo conflict test; normal-use acceptance. Native startup/quit, event polling and owner proposal controls now exist with isolated evidence in [Step 4](native-app.md). A configured grant is not live-agent evidence; local bundles do not imply public release readiness.
