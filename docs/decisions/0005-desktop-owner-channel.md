# ADR 0005 — Reuse authenticated owner HTTP for the native app

Date: 2026-10-01
Status: **Chosen implementation default; isolated app/service smoke verified**

ADR 0004 proposed a private bootstrap pipe and later owner channel during the runtime spike. Step 3 already implemented a versioned loopback owner API with a separate Keychain capability and the shared core policy. Step 4 reuses that API for the native app instead of creating a second command/event transport.

- The app/helper use `127.0.0.1:57321`, schema version 1 and the `owner-local` Keychain account. Integration credentials cannot access owner endpoints or review proposals.
- No secret is placed in the helper command line, provider configuration or local mutation journal. Helper arguments contain only the database path and optional actual parent PID.
- Existing host/origin validation, core revisions/receipts, owner approval and integration scope boundaries are preserved. A cwd or provider name never confers owner authority.
- The app uses snapshot + two-second durable cursor polling, not push subscriptions. It seeds the cursor before the snapshot and journals unread events/cursor together. The product's eventual local feedback contract does not require a particular transport.
- Same-OS-user shell access is outside the credential isolation boundary, as already documented. Release-grade Keychain ACL/signing and broader local IPC hardening remain validation gates.

This supersedes only ADR 0004's planned owner pipe choice; its native framework, helper, SQLite, packaging and compatibility decisions remain unchanged. There is still one shared mutation service/store, not a new UI database or MCP approval bypass.
