# Cofoco

**Todos shared by you and your agents.**

Cofoco (planned app package/current CLI: `cofoco`) is a local-first desktop todo companion. A pet keeps coarse commitments visible in a speech bubble while you switch between personal work, projects and agent sessions.

The list has three states: **안 함 → 하는 중 → 완료**. Optional one-level **Steps** hold milestones; **Notes** hold context. Personal and logical projects are flat scopes with optional folder bindings. All is a view.

Connected agents can capture agreed Todos, start work and maintain Steps. Important changes to an existing Todo become reviewable proposals. Users control the list through the pet app.

## Current status

**V1 specification and UI baseline are approved; the native macOS runtime experiment passed.** The Swift Todo/Step/Note/Project core, first hosted local service, minimal owner CLI and authenticated MCP adapter are implemented. An isolated Claude Code session created, listed, started and reread one real Todo through MCP; a second initialization also succeeded without restarting the service. Provider setup is still manual. The pet app and Codex CLI integration are not implemented/verified. Initial delivery targets one Mac.

The isolated [runtime experiment](experiments/macos-runtime/README.md) builds a SwiftUI/AppKit test window and bundled Swift/SQLite helper. The preserved [Omija Git engine](packages/git-engine/README.md) also remains executable; its 26 tests do not validate Cofoco features.

## Start here

- [Product specification](docs/product-spec.md): Todo/Step/Note, scopes, states, approval policy and UI behavior.
- [Architecture](docs/architecture.md): service ownership, revision/events, proposals, permissions and MCP contract.
- [V1 backlog and acceptance](docs/vertical-slice-1.md): coarse development Todos, Steps and acceptance evidence.
- [UI direction and interactive wireframe](docs/ui-direction.md): owner-approved pet, bubble, details and approval-flow baseline.
- [Native macOS runtime decision](docs/decisions/0004-macos-runtime.md): chosen stack, reproducible evidence and remaining implementation gates.
- [First local MCP integration](docs/local-integration.md): package boundaries, isolated Claude Code evidence and remaining setup/security gates.
- [V1 behavior contract](docs/decisions/0002-todocrew-v1.md): user decisions and design defaults.
- [Product name decision](docs/decisions/0003-product-name-cofoco.md): Cofoco wordmark, future CLI identity, and preserved paths.
- [Current handoff](docs/handoffs/omija-to-todocrew.md): concise context for continuing sessions.
- [Changelog](CHANGELOG.md).

Next work: complete provider setup/removal and a second-provider check, then the approved native pet UI and real two-provider dogfooding. IDE/Git GUI, agent supervision, cloud/mobile/team features and other desktop OS releases are deferred.

## Development today

Node.js 24+ and pnpm are required for the preserved engine:

```bash
pnpm install --frozen-lockfile
pnpm test
pnpm typecheck
```

These commands only cover `packages/git-engine`. The root package remains the preserved engine; the Cofoco executable is a separate Swift package.

The standalone Swift core has its own test suite:

```bash
swift test --package-path packages/cofoco-core
swift test --package-path packages/cofoco-service
swift test --package-path packages/cofoco-cli
```

See [the core implementation notes](docs/core-service.md) and [local integration notes](docs/local-integration.md) for tested boundaries and remaining work. In a restricted sandbox, SwiftPM may need `--disable-sandbox` and a writable scratch/module-cache path.

For the separate native feasibility experiment, use the [build/verification instructions](experiments/macos-runtime/README.md). Its locally ad-hoc-signed `.app` has no external runtime dependency; developer verification uses Python 3. It is not a release installer or the production Todo app.

The local checkout remains `omija`; saved projects, other sessions and external installations are not implicitly renamed.

## Original Omija

Git tag `omija-phase0` at commit `974ca87` preserves the original implementation. [Historical ADE docs and inactive skill](docs/archive/omija-ade/README.md) are not the current roadmap. [ADR 0001](docs/decisions/0001-pivot-omija-to-agentodo.md) records the earlier AgenTODO working name; [ADR 0002](docs/decisions/0002-todocrew-v1.md) establishes the V1 behavior contract and [ADR 0003](docs/decisions/0003-product-name-cofoco.md) sets the current product name.
