import AppKit
import Darwin
import SwiftUI

@MainActor
private final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var panel: PetPanel!
    private var statusItem: NSStatusItem!
    private var helper: Process?
    private var dragOrigin: NSPoint?
    private var lastLaunchAttempt = Date.distantPast
    private var instanceDescriptor: Int32 = -1
    private var quitting = false
    private var globalPointerMonitor: Any?
    private var localPointerMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try FileManager.default.createDirectory(at: AppPaths.root, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }
        catch { NSApp.terminate(nil); return }
        instanceDescriptor = Darwin.open(AppPaths.root.appendingPathComponent("app.lock").path, O_CREAT | O_RDWR, 0o600)
        guard instanceDescriptor >= 0, flock(instanceDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.fromshim.cofoco")
                .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
                running.activate()
            }
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        makeMainMenu()
        makePanel()
        makeStatusItem()
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.updatePointerPassThrough()
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.updatePointerPassThrough()
            return event
        }
        model.requestServiceStart = { [weak self] in self?.startServiceIfNeeded() }
        startServiceIfNeeded()
        model.start()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appearanceChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        if let helper, helper.isRunning { helper.terminate() }
        if instanceDescriptor >= 0 { Darwin.close(instanceDescriptor) }
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        guard let helper, helper.isRunning else { return .terminateNow }
        quitting = true
        model.stop()
        helper.terminationHandler = { @Sendable _ in
            Task { @MainActor in NSApp.reply(toApplicationShouldTerminate: true) }
        }
        helper.terminate()
        Task {
            try? await Task.sleep(for: .seconds(3))
            if helper.isRunning {
                Darwin.kill(helper.processIdentifier, SIGKILL)
            }
        }
        return .terminateLater
    }

    private func makePanel() {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        model.maximumPanelHeight = visible.height - 16
        panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: model.panelHeight),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(rootView: CofocoView(model: model,
            toggleBubble: { [weak self] in self?.toggleBubble() },
            dragPet: { [weak self] translation in self?.dragPet(translation) },
            finishDrag: { [weak self] in self?.finishDrag() },
            bubbleVisibilityChanged: { [weak self] in self?.resizePanel() }))
        let saved = AppPaths.preferences
        let preferred = saved.object(forKey: "cofoco.petRight") == nil
            ? NSPoint(x: visible.maxX - 362, y: visible.minY + 12)
            : NSPoint(x: saved.double(forKey: "cofoco.petRight") - panel.frame.width,
                      y: saved.double(forKey: "cofoco.petBottom"))
        panel.setFrameOrigin(clamped(preferred, size: panel.frame.size))
        panel.orderFrontRegardless()
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.grid.2x2", accessibilityDescription: "Cofoco")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "할 일 열기", action: #selector(showTodos), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "설정", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func makeMainMenu() {
        let main = NSMenu()
        let app = NSMenuItem(title: "Cofoco", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Cofoco")
        let add = NSMenuItem(title: "새 할 일", action: #selector(newTodo), keyEquivalent: "n")
        add.target = self
        appMenu.addItem(add)
        let settings = NSMenuItem(title: "설정", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        let all = NSMenuItem(title: "전체 보기", action: #selector(showAll), keyEquivalent: "a")
        all.keyEquivalentModifierMask = [.command, .shift]
        all.target = self
        appMenu.addItem(all)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Cofoco 종료", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        main.addItem(app); main.setSubmenu(appMenu, for: app)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            editMenu.addItem(item)
        }
        main.addItem(edit); main.setSubmenu(editMenu, for: edit)
        NSApp.mainMenu = main
    }

    @objc private func newTodo() {
        model.screen = .list
        model.bubbleVisible = true
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { self.model.requestComposer = true }
    }

    @objc private func showAll() {
        model.setScope("all")
        showTodos()
    }

    @objc private func showTodos() {
        model.screen = .list
        model.bubbleVisible = true
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func showSettings() {
        model.screen = .settings
        model.bubbleVisible = true
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func toggleBubble() {
        model.bubbleVisible.toggle()
        if model.bubbleVisible { panel.makeKeyAndOrderFront(nil) }
    }

    private func resizePanel() {
        let old = panel.frame
        let newSize = NSSize(width: model.bubbleVisible ? 350 : 132,
                             height: model.panelHeight)
        let preferred = NSPoint(x: old.maxX - newSize.width, y: old.minY)
        panel.setFrame(NSRect(origin: clamped(preferred, size: newSize), size: newSize), display: true)
        updatePointerPassThrough()
    }

    private func updatePointerPassThrough() {
        guard panel != nil, dragOrigin == nil else { return }
        let mouse = NSEvent.mouseLocation
        let local = CGPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        panel.ignoresMouseEvents = !PanelHitRegions.contains(local, width: panel.frame.width,
            height: panel.frame.height, bubbleVisible: model.bubbleVisible,
            mainHeight: model.mainBubbleHeight, changeHeight: model.hasChangeBubble ? model.changeBubbleHeight : nil)
    }

    private func dragPet(_ translation: CGSize) {
        if dragOrigin == nil { dragOrigin = panel.frame.origin }
        guard let dragOrigin else { return }
        let size = panel.frame.size
        let preferred = NSPoint(x: dragOrigin.x + translation.width, y: dragOrigin.y - translation.height)
        panel.setFrameOrigin(clamped(preferred, size: size))
    }

    private func finishDrag() {
        dragOrigin = nil
        AppPaths.preferences.set(panel.frame.maxX, forKey: "cofoco.petRight")
        AppPaths.preferences.set(panel.frame.minY, forKey: "cofoco.petBottom")
    }

    private func clamped(_ preferred: NSPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(preferred) }) ?? panel.screen ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return preferred }
        return NSPoint(x: min(max(preferred.x, frame.minX + 8), max(frame.minX + 8, frame.maxX - size.width - 8)),
                       y: min(max(preferred.y, frame.minY + 8), max(frame.minY + 8, frame.maxY - size.height - 8)))
    }

    @objc private func screenChanged() {
        model.maximumPanelHeight = (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 780
        resizePanel()
        panel.setFrameOrigin(clamped(panel.frame.origin, size: panel.frame.size))
    }

    @objc private func appearanceChanged() { model.objectWillChange.send() }

    private func startServiceIfNeeded() {
        guard helper?.isRunning != true, Date().timeIntervalSince(lastLaunchAttempt) > 2 else { return }
        lastLaunchAttempt = Date()
        Task { [weak self] in
            guard let self, !(await AppAPI().healthy()) else { return }
            guard self.helper?.isRunning != true else { return }
            let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cofoco-service")
            #if DEBUG
            let configured = ProcessInfo.processInfo.environment["COFOCO_SERVICE_EXECUTABLE"].map { URL(fileURLWithPath: $0) }
            #else
            let configured: URL? = nil
            #endif
            let executable = configured ?? bundled
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                self.model.errorMessage = "Cofoco 서비스 실행 파일이 없어요. 앱을 다시 설치해 주세요."
                return
            }
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--database", AppPaths.root.appendingPathComponent("cofoco.sqlite3").path,
                                 "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)]
            process.standardOutput = FileHandle.nullDevice
            let errors = Pipe()
            process.standardError = errors
            errors.fileHandleForReading.readabilityHandler = { @Sendable [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { handle.readabilityHandler = nil; return }
                let message = String(decoding: data.prefix(400), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                Task { @MainActor in self?.model.errorMessage = "서비스 시작 오류: \(message)" }
            }
            do {
                try process.run()
                self.helper = process
                try? await Task.sleep(for: .milliseconds(350))
                await self.model.refresh()
            } catch { self.model.errorMessage = "로컬 서비스를 시작하지 못했어요: \(error.localizedDescription)" }
        }
    }
}

@main
struct CofocoAppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppController()
        app.delegate = delegate
        // NSApplication's delegate is weak. Keep lifecycle/launch callbacks
        // alive even when ARC shortens the last-use lifetime in optimized code.
        withExtendedLifetime(delegate) { app.run() }
    }
}
