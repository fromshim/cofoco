# TodoCrew

**Todos shared by you and your agents.**

TodoCrew (`todocrew` package/future CLI) is a local-first desktop todo companion. A pet keeps coarse commitments visible in a speech bubble while you switch between personal work, projects and agent sessions.

The list has three states: **안 함 → 하는 중 → 완료**. Optional one-level **Steps** hold milestones; **Notes** hold context. Personal and logical projects are flat scopes with optional folder bindings. All is a view.

Connected agents can capture agreed Todos, start work and maintain Steps. Important changes to an existing Todo become reviewable proposals. Users control the list through the pet app.

## Current status

**V1 specification is finalized; TodoCrew features are not implemented.** There is no todo database, daemon, MCP server, new CLI or pet UI yet. Initial delivery/validation targets one Mac with local Claude Code and Codex CLI.

The only executable code is the preserved [Omija Git engine](packages/git-engine/README.md). Its 26 tests do not validate TodoCrew features.

## Start here

- [Product specification](docs/product-spec.md): Todo/Step/Note, scopes, states, approval policy and UI behavior.
- [Architecture](docs/architecture.md): service ownership, revision/events, proposals, permissions and MCP contract.
- [V1 backlog and acceptance](docs/vertical-slice-1.md): coarse development Todos, Steps and acceptance evidence.
- [V1 reconciliation decision](docs/decisions/0002-todocrew-v1.md): conflicts resolved, user decisions and design defaults.
- [Current handoff](docs/handoffs/omija-to-todocrew.md): concise context for continuing sessions.
- [Changelog](CHANGELOG.md).

Next work: UI direction/wireframes, then the runtime spike and core/MCP implementation, pet implementation, and real two-provider dogfooding. IDE/Git GUI, agent supervision, cloud/mobile/team features and other desktop OS releases are deferred.

## Development today

Node.js 24+ and pnpm are required for the preserved engine:

```bash
pnpm install --frozen-lockfile
pnpm test
pnpm typecheck
```

These commands only cover `packages/git-engine`. There is no root `bin` entry until the actual TodoCrew CLI exists.

The local checkout remains `omija`; saved projects, other sessions and external installations are not implicitly renamed.

## Original Omija

Git tag `omija-phase0` at commit `974ca87` preserves the original implementation. [Historical ADE docs and inactive skill](docs/archive/omija-ade/README.md) are not the current roadmap. [ADR 0001](docs/decisions/0001-pivot-omija-to-agentodo.md) records the earlier AgenTODO working name; [ADR 0002](docs/decisions/0002-todocrew-v1.md) establishes the current contract.
