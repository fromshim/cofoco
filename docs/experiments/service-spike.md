# Cofoco macOS service and SQLite spike

Date: 2026-09-28. Scope: disposable technical experiment; no Cofoco feature code or acceptance-matrix completion.

## Verified on this Mac

- Apple Swift 6.3.3 compiled a Foundation/Darwin/SQLite3 executable with system `libsqlite3` (runtime SQLite 3.51.0). No package dependency was needed for this experiment.
- `--self-test` used a fresh temporary directory and passed: state, event, and receipt in one `BEGIN IMMEDIATE` transaction; same actor/key/payload returned the original receipt; changed payload with the same key failed; stale revision failed; injected failure after the state update rolled back state, event, and receipt; a no-op made a receipt but no event; reopening a separate SQLite connection retained the state/event/receipt and replayed the receipt.
- A version 1 database with a committed Todo in WAL mode migrated to version 2. The pre-migration copy made through `sqlite3_backup_*` retained version 1 and the Todo. A database with `user_version=99` was refused rather than downgraded. This is schema-mechanism evidence, not a production schema design or restored-backup drill.
- Two service processes pointed at the same temporary directory: the second failed with `already_running` while the first held an advisory `flock`. A process-boundary test received an authenticated 200 health response, 403 responses for missing bearer, wrong Host, and wrong Origin, clean exit after SIGTERM, and exit within the polling window after its parent process disappeared. The listener bound only to `127.0.0.1`.

Build and rerun:

```sh
swiftc -module-cache-path /private/tmp/cofoco-swift-module-cache -parse-as-library experiments/macos-runtime/service/main.swift -o /private/tmp/cofoco-service-spike -lsqlite3
/private/tmp/cofoco-service-spike --self-test
python3 experiments/macos-runtime/service/test_runtime.py /private/tmp/cofoco-service-spike
```

The local sandbox denied loopback `bind` with EPERM until the process-boundary test received local-network execution approval. `--self-test` did not need it. Both tests remove their fixture directories. The latter never prints the ephemeral bearer value.

## Implementation direction supported by the spike

The packaged macOS app can launch one child service at `Contents/Helpers/cofoco-service-spike` in the packaging experiment, supplying an application-data path and `--parent-pid <app PID>`. The child emits exactly one JSON readiness line on its private stdout pipe: `status`, `protocol_version`, `pid`, `port`, and an ephemeral `token`. Hiding the pet should leave the app and child alive. Explicit Quit should stop the child and wait for committed work to finish; the probe exited cleanly on SIGTERM. If the app disappears unexpectedly, the child checks both `getppid()` and liveness each second and exits. The parent must reconnect/restart deliberately; this experiment does not implement a startup supervisor, PID-reuse defense, or crash restart policy. The file lock is advisory and blocks a second cooperating service, not arbitrary SQLite writers.

For the product service, one writer should own the store and expose a versioned application API to UI, CLI, and MCP. Use `BEGIN IMMEDIATE` for mutation batches and enforce actor/key fingerprints, revision comparisons, provenance, durable events and receipts in one transaction. The experiment has only one fixture Todo/status operation; it does not implement authorization, approvals, Steps, Notes, event subscriptions, or the full domain. The reopen test is **not** a forced-process-crash test or full A18 evidence.

The hand-written HTTP parser here accepts one bounded health request to test loopback binding, bearer, Host/Origin checks, and protocol readiness. It is not an MCP server or a production HTTP parser. Future MCP implementation should use a maintained HTTP host and the [official Swift MCP SDK transport](https://github.com/modelcontextprotocol/swift-sdk) rather than expand this parser; verify the chosen release, installed Claude/Codex clients, Streamable HTTP behavior, reconnect, request limits, and security handling together. The owner app's private child pipe can deliver its ephemeral health capability. A provider-facing MCP grant must be separate from trusted owner approval and scoped by integration; cwd cannot grant authority. A global registration shares its grant across all using sessions.

For persistent provider credentials, the chosen default is a macOS Keychain generic-password item per integration, with only a non-secret credential reference, grant scopes, and revocation state in the SQLite store. Validate signed app/helper access groups and the setup flow in implementation. The owner capability needs a separate channel and must never be accepted from an MCP payload. This is a design choice, not a tested Keychain implementation. The temporary readiness bearer must not be logged; the spike prints it only to the parent-readable stdout pipe.

Migration policy for implementation: refuse future schema versions; take a consistent SQLite online backup before each version change; migrate schema and `user_version` in a transaction; retain backup until the new version passes integrity and application checks; document a restore command and rehearse it on a copy. The spike verifies backup contents and atomic schema transactions, but not restore after an injected migration failure. System SQLite compatibility on this Mac does not establish the minimum supported macOS version or packaging/signing behavior.

## Primary references

- [SQLite transaction control](https://www.sqlite.org/lang_transaction.html): `BEGIN IMMEDIATE`, commit, rollback, and single-writer behavior.
- [SQLite PRAGMA `user_version`](https://sqlite.org/pragma.html#pragma_user_version): application-owned schema number.
- [SQLite Online Backup API](https://www.sqlite.org/c3ref/backup_finish.html): consistent copy of a live database, including committed WAL content.
- [Apple `flock(2)` manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/flock.2.html): advisory, nonblocking file lock.
- [Apple Keychain generic-password items](https://developer.apple.com/documentation/security/ksecclassgenericpassword): proposed credential storage.
- [Official Swift MCP SDK](https://github.com/modelcontextprotocol/swift-sdk): future transport integration candidate, not compiled in this spike.
