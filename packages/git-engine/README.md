# Git integration engine — parked Omija implementation

Status: **preserved, not part of TodoCrew V1**.

This directory contains the original Omija TypeScript source and 26 tests, moved together without source changes. Relative imports continue to resolve. The original layout and docs are recoverable from Git tag `omija-phase0` (`974ca87`).

The engine provides `preflight`, `stage`, `scope-check`, `preview`, and `apply`. It does not provide a todo store, MCP server, or agent process supervisor.

## Maintenance

From the repository root:

```bash
pnpm test:git-engine
pnpm typecheck
node packages/git-engine/src/cli.ts --help
```

The last command shows the **legacy** CLI. It still identifies itself as `omija`; no public `omija` or `todocrew` binary is installed by the root package. Do not interpret its help as the new product's command surface.

`refs/omija/*`, `<git-common-dir>/omija/preview`, `OmijaError`, and fixture names are intentionally unchanged. Existing external Git data has not been scanned or migrated. Introducing a TodoCrew Git interface later requires an explicit compatibility decision and real integration validation.

This is a logical source boundary, not yet a separately published package or pnpm workspace. A manifest/dependency split is unnecessary until there is an active consumer.

See the [pivot decision](../../docs/decisions/0001-pivot-omija-to-agentodo.md) and [historical design](../../docs/archive/omija-ade/phase-0-slice-design.md).
