# macOS runtime experiment

This folder contains disposable runtime spikes. It is not the Cofoco feature app and is not a production installer. The prototype window is paired with a separately compiled Swift helper using the macOS SQLite library.

## Build and verify

Run from any working directory; the scripts resolve the repository from their own paths and quote all paths. Each build gets a new ignored output directory under `.build`, whose app path deliberately contains spaces. No app is installed in `~/Applications` and no shell, provider, or user-wide configuration is changed.

```sh
APP_PATH="$(bash experiments/macos-runtime/scripts/build.sh)"
bash experiments/macos-runtime/scripts/verify.sh "$APP_PATH"
```

The build targets the host architecture and declares macOS 14.0 as the deployment floor. It uses the selected Xcode macOS SDK and only system frameworks/libraries: SwiftUI, AppKit, Foundation, and SQLite3. Both Swift binaries use `-parse-as-library -O`; a module cache is isolated beside the build output. The generated app is named `CofocoRuntimeSpike.app`, with executable `Contents/MacOS/CofocoRuntimeSpike`, helper `Contents/Helpers/cofoco-service-spike`, `LSUIElement=true`, and a spike-only bundle identifier.

`verify.sh` takes the explicit app path emitted by `build.sh`. Its checks are identified as PKG-01 through PKG-09. They validate bundle metadata, the app and nested-helper ad-hoc signatures, architecture and minimum OS load commands, system-library dependencies, app geometry self-test, SQLite service self-test, a separate-process service test, and a bounded app-to-helper smoke test. The service self-test creates isolated temporary fixtures; its `--data-dir` argument is not used. The process test exercises a bundled helper through a temporary data directory. The GUI smoke has a 12-second outer timeout and exits nonzero if the app does not finish.

The experiment runs on the current macOS host. The declared macOS 14.0 floor is a build compatibility target, not evidence from a macOS 14 machine. Only the host architecture is emitted and tested.

## Signing boundary

The helper is signed first, then the app receives a local ad-hoc signature, so nested code integrity can be checked by `codesign`. The host has no available code-signing identity. This does not establish a developer identity, hardened-runtime release configuration, Gatekeeper acceptance for downloaded apps, or notarization. Apple’s distribution flow requires a valid Developer ID signature and hardened runtime before notarization; neither public signing nor notarization is tested here. See [Apple’s notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Framework choice context

The spike exercises a SwiftUI shell with AppKit window control, including `NSVisualEffectView` system material and accessory activation. Apple documents SwiftUI/AppKit interoperability and that accessory activation corresponds to `LSUIElement=1` ([AppKit integration](https://developer.apple.com/documentation/swiftui/appkit-integration), [accessory activation policy](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory)).

Tauri is a credible web-UI alternative: its macOS app uses the system WebKit view, supports bundled sidecar executables, and has a documented macOS bundle/signing path ([prerequisites](https://v2.tauri.app/start/prerequisites/), [sidecars](https://v2.tauri.app/develop/sidecar/), [app bundle](https://v2.tauri.app/distribute/macos-application-bundle/)). It keeps the web frontend model and adds a Rust host/build pipeline. Electron uses a Chromium/Node main-and-renderer process model and a separate packaging toolchain ([process model](https://www.electronjs.org/docs/latest/tutorial/process-model), [packaging](https://www.electronjs.org/docs/latest/tutorial/tutorial-packaging)). Those two alternatives were reviewed from their official documentation only; neither was installed, built, or benchmarked in this experiment.
