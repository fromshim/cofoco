# Omija — archived Phase 0 README

> Status: **Superseded** on 2026-09-04. Current direction: [TodoCrew product spec](../../product-spec.md).
> Historical context only. Do not use this as the current product direction.
> Original snapshot: Git tag `omija-phase0` (commit `974ca87`).
> Commands and source paths below describe the original layout, not the current product.

Omija is a worktree-native agent harness for coordinating coding agents, isolated workspaces, verification, and Git integration.

The project starts as a CLI harness and is designed to grow into a desktop Agentic Development Environment (ADE) without making Orca a permanent dependency.

## Documentation

- [Architecture overview](architecture-overview.md)
- [Phase 0: integration engine + orchestration skill](phase-0-slice-design.md)

## Integration engine

Five commands own every git operation that can lose work. They have no runtime
dependencies and no build step: Node 24 runs the TypeScript sources directly.

```text
omija preflight   --run <id> --base <ref>
omija stage       --run <id> --task <id> --branch <branch>
omija scope-check --run <id> --branch <branch> --allow <glob>...
omija preview     --run <id> --order <task-id,task-id,...>
omija apply       --run <id> --base <ref>
```

State lives in git refs, not a database:

```text
refs/omija/base/<run-id>                frozen base commit
refs/omija/staging/<run-id>/<task-id>   copy of a task branch head
refs/omija/integration/<run-id>         candidate history
refs/omija/archive/<run-id>/<task-id>   kept after apply
refs/omija/lane/<run-id>/<task-id>      task contract: agent, scope, verify
```

```bash
pnpm install
pnpm test        # real git operations against throwaway repositories
pnpm typecheck
```

## Orchestration skill

[Original orchestration skill](orchestration-skill.md) drives Orca worktrees and workers, and calls
the commands above for anything involving git. The Orca dependency lives only in
that file, so replacing it later means rewriting prose rather than code.

## Status

The integration engine is done and covered by tests that run real git against
throwaway repositories: scope enforcement, staging, conflict reporting, linear
preview, base-drift refusal, and fast-forward apply.

The orchestration skill is written but has not yet driven real Claude and Codex
workers through a full run. That is the next thing to do, and it is what decides
which of the assumptions in
[the Phase 0 design](phase-0-slice-design.md) §13 hold.

After that comes the run view: `omija status <run-id>` draws one lane per
worktree from the refs alone, so the answer to "how far is each lane" stops
being something a person assembles from an Orca sidebar and `git log`. It reads
refs and nothing else, which keeps the Orca dependency inside the skill. See
[Architecture overview](architecture-overview.md) §7.1 and Phase 3.5.

Not yet: task dependencies, running without Orca, cross-provider review cycles,
budget and model routing, live process state in the run view, desktop.
