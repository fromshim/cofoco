# ADR 0003 — Cofoco product identity

Status: **Accepted; implementation pending**  
Date: 2026-09-25

## Context

The product name TodoCrew was judged difficult to pronounce. The product is a shared, local-first todo companion: a person and their AI agents use one durable list across projects. The owner selected **Cofoco** as the new product name after considering short names built around collaboration and focus.

## Decision

- Product name and wordmark: **Cofoco**; the planned app package and future CLI use lowercase `cofoco`.
- Leave the current root `package.json` unchanged; it belongs to the preserved Git-engine workspace and is not the planned Cofoco application package.
- Use the `cofoco_` prefix for the planned MCP tool names. These are specification names only; no Cofoco CLI or MCP implementation exists yet.
- The GitHub repository is [`fromshim/cofoco`](https://github.com/fromshim/cofoco).
- Preserve the local checkout path `/Users/seungboshim/Projects/fromshim/omija` and existing directory/document paths, including `design-system/todocrew/`, `docs/wireframes/todocrew-v1.html`, and `docs/handoffs/omija-to-todocrew.md`. Their names are existing workspace context, not the current product name.
- Update active product, architecture, backlog, UI direction, design guidance, handoff, and wireframe display text to Cofoco. Leave historical decisions, archived Omija materials, and exact image-generation records under their original names for provenance.
- This is a naming decision, not trademark, domain, or distribution-rights clearance. The V1 behavior contract in [ADR 0002](0002-todocrew-v1.md) remains in force; this decision changes no product behavior.

## Consequences

New product-facing text should use Cofoco. The older TodoCrew references in ADR 0002 and earlier records describe the name that was current when those decisions were written. No feature implementation or migration of the preserved Git-engine package is implied by the documentation update.
