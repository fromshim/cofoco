import AppKit
import SwiftUI

// A disposable macOS runtime experiment. It intentionally contains no Todo feature state.
private enum SpikeGeometry {
    static let bubbleSize = NSSize(width: 352, height: 450)
    static let petSize = NSSize(width: 94, height: 94)
    static let edgeInset: CGFloat = 16

    static func clampedOrigin(visibleFrame: NSRect, size: NSSize, preferred: NSPoint) -> NSPoint {
        let minimumX = visibleFrame.minX + edgeInset
        let minimumY = visibleFrame.minY + edgeInset
        let maximumX = max(minimumX, visibleFrame.maxX - edgeInset - size.width)
        let maximumY = max(minimumY, visibleFrame.maxY - edgeInset - size.height)
        return NSPoint(x: min(max(preferred.x, minimumX), maximumX),
                       y: min(max(preferred.y, minimumY), maximumY))
    }

    static func bottomRightOrigin(visibleFrame: NSRect, size: NSSize) -> NSPoint {
        clampedOrigin(visibleFrame: visibleFrame,
                      size: size,
                      preferred: NSPoint(x: visibleFrame.maxX - edgeInset - size.width,
                                         y: visibleFrame.minY + edgeInset))
    }

    static func screenIndex(containing point: NSPoint, frames: [NSRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }
}

@MainActor
private final class SpikeModel: ObservableObject {
    @Published var bubbleVisible = true
    @Published var composerVisible = false
    @Published var typedText = ""
    @Published var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @Published var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    @Published var helperStatus = "Starting local service…"
}

private struct SystemMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct SpikeView: View {
    @ObservedObject var model: SpikeModel
    let toggleBubble: () -> Void
    let showComposer: () -> Void
    let dragPet: (CGSize) -> Void
    let finishDrag: () -> Void
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if model.bubbleVisible {
                bubble
                    .frame(width: 324, height: 332)
                    .background {
                        if model.reduceTransparency {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor))
                        } else {
                            SystemMaterial()
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.primary.opacity(model.reduceTransparency ? 0.18 : 0.08), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.15), radius: 16, y: 5)
                    .accessibilityElement(children: .contain)
            }
            Button(action: toggleBubble) {
                Image(systemName: "hare.fill")
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 88, height: 88)
                    .background {
                        Circle()
                            .fill(model.reduceTransparency
                                  ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                                  : AnyShapeStyle(.regularMaterial))
                    }
            }
            .buttonStyle(.plain)
            .help(model.bubbleVisible ? "Hide Todo bubble" : "Show Todo bubble")
            .accessibilityLabel(model.bubbleVisible ? "Hide Todo bubble" : "Show Todo bubble")
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { dragPet($0.translation) }
                    .onEnded { _ in finishDrag() }
            )
        }
        .padding(8)
        .frame(width: model.bubbleVisible ? SpikeGeometry.bubbleSize.width : SpikeGeometry.petSize.width,
               height: model.bubbleVisible ? SpikeGeometry.bubbleSize.height : SpikeGeometry.petSize.height,
               alignment: .bottomTrailing)
        .onChange(of: model.composerVisible) { _, showing in
            if showing { DispatchQueue.main.async { composerFocused = true } }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Todo")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("RUNTIME SPIKE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
            Text("Window, focus and service lifecycle test")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(model.helperStatus)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if model.composerVisible {
                Text("Personal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Type to test focus…", text: $model.typedText)
                    .textFieldStyle(.plain)
                    .focused($composerFocused)
                    .padding(.vertical, 8)
                    .accessibilityLabel("Todo input focus test")
            } else {
                Button(action: showComposer) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Open focus test input")
                .accessibilityLabel("Open focus test input")
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
    }
}

@MainActor
private final class SpikePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class RuntimeController: NSObject, NSApplicationDelegate {
    private let model = SpikeModel()
    private var panel: SpikePanel!
    private var statusItem: NSStatusItem!
    private var screenIndex = 0
    private var helper: Process?
    private var helperPipe: Pipe?
    private var readinessBuffer = Data()
    private var helperReady = false
    private var helperStopped = true
    private var dragStartOrigin: NSPoint?
    private var anchor: NSPoint?
    private(set) var smokePassed = false
    private let smokeTest: Bool

    init(smokeTest: Bool) { self.smokeTest = smokeTest }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeMainMenu()
        makePanel()
        makeStatusItem()
        observeSettings()
        selectScreenAtPointer()
        placePanel()
        panel.orderFrontRegardless() // Does not activate the app or focus the composer.
        startBundledHelper()

        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if smokeTest {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.finishSmokeTest() }
        }
    }

    private func makeMainMenu() {
        let main = NSMenu()
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Edit")
        for (title, selector, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.keyEquivalentModifierMask = .command
            submenu.addItem(item)
        }
        main.addItem(edit)
        main.setSubmenu(submenu, for: edit)
        NSApp.mainMenu = main
    }

    private func makePanel() {
        let rect = NSRect(origin: .zero, size: SpikeGeometry.bubbleSize)
        panel = SpikePanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: SpikeView(model: model,
            toggleBubble: { [weak self] in self?.toggleBubble() },
            showComposer: { [weak self] in self?.openComposer() },
            dragPet: { [weak self] in self?.dragPet(by: $0) },
            finishDrag: { [weak self] in self?.dragStartOrigin = nil }))
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hare", accessibilityDescription: "Cofoco runtime spike")
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show / Hide Bubble", action: #selector(toggleFromMenu), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let move = NSMenuItem(title: "Move to Next Display", action: #selector(moveToNextDisplay), keyEquivalent: "")
        move.target = self
        menu.addItem(move)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Cofoco Spike", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func observeSettings() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                           object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                self?.model.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            }
        }
    }

    private func selectScreenAtPointer() {
        let frames = NSScreen.screens.map(\.frame)
        screenIndex = SpikeGeometry.screenIndex(containing: NSEvent.mouseLocation, frames: frames) ?? 0
    }

    private func placePanel() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        screenIndex = min(screenIndex, screens.count - 1)
        let visible = screens[screenIndex].visibleFrame
        let size = model.bubbleVisible ? SpikeGeometry.bubbleSize : SpikeGeometry.petSize
        let preferred = anchor.map { NSPoint(x: $0.x - size.width, y: $0.y) }
            ?? SpikeGeometry.bottomRightOrigin(visibleFrame: visible, size: size)
        let origin = SpikeGeometry.clampedOrigin(visibleFrame: visible, size: size, preferred: preferred)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        anchor = NSPoint(x: origin.x + size.width, y: origin.y)
    }

    private func dragPet(by translation: CGSize) {
        if dragStartOrigin == nil { dragStartOrigin = panel.frame.origin }
        guard let start = dragStartOrigin else { return }
        let size = panel.frame.size
        let preferred = NSPoint(x: start.x + translation.width, y: start.y - translation.height)
        let petCenter = NSPoint(x: preferred.x + size.width - SpikeGeometry.petSize.width / 2,
                                y: preferred.y + SpikeGeometry.petSize.height / 2)
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        if let destination = SpikeGeometry.screenIndex(containing: petCenter, frames: screens.map(\.frame)) {
            screenIndex = destination
        }
        let origin = SpikeGeometry.clampedOrigin(visibleFrame: screens[screenIndex].visibleFrame,
                                                  size: size, preferred: preferred)
        panel.setFrameOrigin(origin)
        anchor = NSPoint(x: origin.x + size.width, y: origin.y)
    }

    private func toggleBubble() {
        model.bubbleVisible.toggle()
        placePanel()
        if model.bubbleVisible { panel.orderFrontRegardless() }
    }

    private func openComposer() {
        model.composerVisible = true
        panel.makeKeyAndOrderFront(nil) // Only an explicit user action requests typing focus.
    }

    @objc private func toggleFromMenu() { toggleBubble() }
    @objc private func moveToNextDisplay() {
        guard !NSScreen.screens.isEmpty else { return }
        screenIndex = (screenIndex + 1) % NSScreen.screens.count
        anchor = nil
        placePanel()
        panel.orderFrontRegardless()
    }
    @objc private func screenParametersChanged() { selectScreenAtPointer(); placePanel() }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        helperPipe?.fileHandleForReading.readabilityHandler = nil
        guard let helper, helper.isRunning else {
            helperStopped = true
            return .terminateNow
        }
        helper.terminate()
        // This disposable probe waits briefly for its own child. AppKit's
        // terminateLater nested loop did not drain our main-queue reply.
        let deadline = Date().addingTimeInterval(3)
        while helper.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        helperStopped = !helper.isRunning
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard smokeTest else { return }
        print("{\"termination\":\"\(helperStopped ? "helper_exited" : "helper_timeout")\"}")
        fflush(stdout)
        exit(smokePassed && helperStopped ? 0 : 1)
    }

    private func startBundledHelper() {
        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cofoco-service-spike")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            model.helperStatus = "Helper absent (standalone window test)"
            return
        }
        let dataURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cofoco-window-spike-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
            let child = Process()
            let pipe = Pipe()
            child.executableURL = helperURL
            child.arguments = ["--data-dir", dataURL.path, "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)]
            child.standardOutput = pipe
            child.standardError = Pipe()
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let bytes = handle.availableData
                DispatchQueue.main.async { [weak self] in self?.receiveHelperOutput(bytes) }
            }
            try child.run()
            helper = child
            helperPipe = pipe
            helperStopped = false
        } catch {
            model.helperStatus = "Helper launch failed: \(error.localizedDescription)"
        }
    }

    private func receiveHelperOutput(_ bytes: Data) {
        guard !bytes.isEmpty else { return }
        readinessBuffer.append(bytes)
        guard let newline = readinessBuffer.firstIndex(of: 10) else { return }
        let line = readinessBuffer.prefix(upTo: newline)
        readinessBuffer.removeSubrange(...newline)
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["status"] as? String == "ready",
              object["protocol_version"] as? Int == 1,
              let port = object["port"] as? Int,
              (1...65535).contains(port),
              object["token"] as? String != nil else {
            model.helperStatus = "Unexpected helper handshake"
            return
        }
        helperReady = false
        model.helperStatus = "Checking service health…"
        let token = object["token"] as! String
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/health")!)
        request.setValue("127.0.0.1:\(port)", forHTTPHeaderField: "Host")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let valid = (response as? HTTPURLResponse)?.statusCode == 200
                && (data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["protocol_version"] as? Int == 1
            DispatchQueue.main.async { [weak self] in
                self?.helperReady = valid
                self?.model.helperStatus = valid ? "Service healthy on 127.0.0.1:\(port)" : "Service health failed"
            }
        }.resume()
    }

    private func finishSmokeTest() {
        let result: [String: Any] = [
            "panel_visible": panel.isVisible,
            "panel_key": panel.isKeyWindow,
            "helper_ready": helperReady,
            "screen_count": NSScreen.screens.count,
            "reduce_motion": model.reduceMotion,
            "reduce_transparency": model.reduceTransparency,
        ]
        let encoded = (try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])) ?? Data()
        print(String(decoding: encoded, as: UTF8.self))
        fflush(stdout)
        smokePassed = panel.isVisible && !panel.isKeyWindow && helperReady
        NSApp.terminate(nil)
    }
}

private enum SelfTest {
    static func run() -> Int32 {
        let screenA = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let screenB = NSRect(x: -1280, y: 100, width: 1280, height: 800)
        let pet = SpikeGeometry.petSize
        let bubble = SpikeGeometry.bubbleSize
        let a = SpikeGeometry.bottomRightOrigin(visibleFrame: screenA, size: bubble)
        let b = SpikeGeometry.bottomRightOrigin(visibleFrame: screenB, size: pet)
        let clamped = SpikeGeometry.clampedOrigin(visibleFrame: screenB, size: bubble,
                                                   preferred: NSPoint(x: 4000, y: -4000))
        let tests: [(String, Bool)] = [
            ("right-bottom anchor", a.x == 1072 && a.y == 16),
            ("negative-origin display", b.x == -110 && b.y == 116),
            ("visible-frame clamp", clamped.x == -368 && clamped.y == 116),
            ("pointer display selection", SpikeGeometry.screenIndex(containing: NSPoint(x: -500, y: 300), frames: [screenA, screenB]) == 1),
        ]
        for (name, passed) in tests { print("\(passed ? "PASS" : "FAIL") \(name)") }
        return tests.allSatisfy(\.1) ? 0 : 1
    }
}

@main
private enum CofocoRuntimeSpike {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") { exit(SelfTest.run()) }
        let app = NSApplication.shared
        let controller = RuntimeController(smokeTest: CommandLine.arguments.contains("--smoke-test"))
        app.delegate = controller
        app.run()
        if CommandLine.arguments.contains("--smoke-test") { exit(controller.smokePassed ? 0 : 1) }
    }
}
