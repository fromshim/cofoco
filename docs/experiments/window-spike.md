# Cofoco macOS window spike

Date: 2026-09-28. Scope: disposable SwiftUI/AppKit window and lifecycle experiment, not the approved Cofoco UI implementation.

## Tested result

The [native window source](../../experiments/macos-runtime/window/main.swift) compiled optimized for the host arm64 Mac with macOS 14.0 deployment target. The [packaged candidate](</Users/seungboshim/Projects/fromshim/omija/experiments/macos-runtime/.build/run.TV5aRi/packaging output with spaces/CofocoRuntimeSpike.app>) passed the bounded app-to-helper smoke: `panel_visible=true`, `panel_key=false`, `helper_ready=true`, `screen_count=1`, followed by `termination=helper_exited` and process exit 0. The helper used the bundle's `Contents/Helpers` executable and an isolated temporary data directory.

The coordinator independently reran the final package verification successfully. A negative test of the copied final executable without its helper returned `helper_ready=false` and exit 1 within the timeout.

The coordinator operated the final candidate through desktop automation: the floating material panel appeared; `+` opened and focused the field; ASCII typing, Command-A and pasting `Cofoco 입력 검증` worked. Clicking the pet hid the bubble while the exact app/helper PIDs remained alive, then restored the bubble with the input preserved. These are tool-observed checks, separate from the automated smoke and from the owner's design approval. A drag gesture was exercised, but actual displacement was not independently measured. An earlier build lacked standard Edit responder commands and paste timed out; adding the responder-chain menu fixed the final-candidate check. Korean IME composition and every Edit command are not claimed tested.

The `--self-test` geometry checks passed four cases: bottom-right anchor within a visible frame, negative-origin screen coordinates, clamping to the visible frame, and pointer-based screen selection. They use synthetic rectangles. Only one physical display was present in the automated smoke, so actual multi-display movement, display disconnect and Spaces/full-screen behavior are unverified.

## Runtime choices exercised

- A borderless, transparent `NSPanel` hosts the SwiftUI probe. The panel is floating, initially nonactivating, and can become key only for explicit text entry. The app runs as an accessory (`LSUIElement=true`) with a menu-bar status item for restore, move-to-next-display, and Quit.
- The panel chooses a screen by pointer position and clamps to its visible frame. Dragging updates a bottom-right anchor. Actual second-display behavior still needs testing on a multi-display Mac.
- SwiftUI exposes labels for the pet toggle, capture control, and text field. `NSWorkspace` supplies Reduce Motion and Reduce Transparency settings and a change notification; the probe renders a system-color fallback when transparency is reduced. It does not yet test VoiceOver reading order, keyboard navigation of every control, or actual settings toggles.
- The app launches one bundled service child, reads a versioned JSON readiness line on a private pipe, authenticates a loopback health check, and leaves the service running while the bubble is hidden. Explicit Quit sends SIGTERM and waits up to three seconds in this disposable probe. The original `terminateLater`/main-queue callback attempt hung inside AppKit's nested termination event loop; bounded synchronous stop passed. A production app should move draining off the UI thread and report timeout/recovery rather than freeze interaction for that interval.
- No Todo data, pet animation art, approval flow, persistent positioning, notification presentation, or real MCP connection is implemented here. The hare SF Symbol and `RUNTIME SPIKE` label are test placeholders, not distributable product art.

The combination supports selecting SwiftUI for the bubble and AppKit for macOS window/menu behavior on the tested host. It does not yet establish a shipping accessibility verdict or macOS 14 runtime compatibility. [Apple's AppKit integration guidance](https://developer.apple.com/documentation/swiftui/appkit-integration) and [activation policy documentation](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory) describe the relevant platform APIs.
