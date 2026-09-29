# Cofoco macOS app packaging spike

Date: 2026-09-28. This is a locally built runtime experiment, not a Cofoco release package.

## Artifact and reproducible commands

Run [the build script](../../experiments/macos-runtime/scripts/build.sh) from any working directory. It prints the full `.app` path as its final stdout line. Pass that exact path to [the verification script](../../experiments/macos-runtime/scripts/verify.sh). Each build creates a new ignored directory under `experiments/macos-runtime/.build`, with spaces in the app path. It never installs to Applications or edits provider configuration.

Verified final candidate: [CofocoRuntimeSpike.app](</Users/seungboshim/Projects/fromshim/omija/experiments/macos-runtime/.build/run.TV5aRi/packaging output with spaces/CofocoRuntimeSpike.app>).

```sh
APP_PATH="$(bash experiments/macos-runtime/scripts/build.sh)"
bash experiments/macos-runtime/scripts/verify.sh "$APP_PATH"
```

The tested bundle layout is:

```text
CofocoRuntimeSpike.app/
  Contents/Info.plist
  Contents/MacOS/CofocoRuntimeSpike
  Contents/Helpers/cofoco-service-spike
```

The native app uses SwiftUI with AppKit window control; the child uses Foundation and system SQLite3. Both binaries are optimized for the host arm64 architecture, built against macOS SDK 26.5, with `LC_BUILD_VERSION minos 14.0`. This proves the compiler accepted that deployment target on the current macOS 26.5.2 host, not that it runs on a macOS 14 machine or Intel Mac.

## Checks and results

| Check | Result on current host |
|---|---|
| Info.plist and layout | Passed: app executable, nested helper, `APPL`, spike bundle ID, `LSUIElement=true`, minimum OS 14.0 |
| Code integrity | Passed: helper signed first, then app; `codesign --verify --deep --strict` validated both local ad-hoc signatures |
| Architecture/load commands | Passed: both arm64, minimum OS 14.0 |
| Linked libraries | Passed: `otool -L` resolved every direct dependency under `/System/Library` or `/usr/lib`, including `/usr/lib/libsqlite3.dylib`; no Homebrew, Node, or packaged third-party runtime appeared |
| Window geometry self-test | Passed four deterministic positioning/screen-selection checks; does not validate physical display appearance |
| SQLite service self-test | Passed atomic state/event/receipt, retry, conflict, rollback, restart reopen, v1 backup/migration, and future-schema refusal on temporary fixtures; see [service spike](service-spike.md) |
| Bundled helper process test | Passed: authenticated local health, three rejection cases, duplicate-instance lock, SIGTERM, parent-exit detection |
| App-to-helper GUI smoke | Passed on the final candidate: visible panel, not key at rest, one screen, healthy bundled helper, and `termination=helper_exited`. The 12-second outer timeout did not fire. An earlier build reached the visible/healthy state but hung in AppKit's `terminateLater` handshake; the spike now uses a bounded synchronous child stop. |

The process and GUI checks require access to the local loopback listener; this execution sandbox initially returned EPERM on `bind`, then allowed the checks under local-network approval. The service `--self-test` uses its own temporary fixtures and ignores `--data-dir`, so no path-with-spaces storage claim comes from that self-test. The app bundle path itself contains spaces and was used successfully for build, signing, metadata, and helper process checks.

## Distribution boundary

The package is locally ad-hoc signed and not notarized. There is no Developer ID identity on this host. The experiment does not establish hardened runtime entitlements, Gatekeeper acceptance for downloaded software, installation/update behavior, minimum-OS runtime compatibility, or provider integration. Those require release-specific validation. Apple documents the [Developer ID and notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
