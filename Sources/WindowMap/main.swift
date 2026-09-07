import AppKit
import Carbon.HIToolbox
import Logging
import SpreadsheetKit
import WindowMapCore
import WindowMapApp

let appLog = Log(module: "App")

setvbuf(stderr, nil, _IOLBF, 0)

let lockPath = NSTemporaryDirectory() + "windowmap.lock"
let lockFd = open(lockPath, O_CREAT | O_WRONLY, 0o644)
guard lockFd >= 0, flock(lockFd, LOCK_EX | LOCK_NB) == 0 else {
    appLog.error("another instance is already running")
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let home = ProcessInfo.processInfo.environment["WINDOWMAP_HOME"]
    ?? NSHomeDirectory() + "/.config/windowmap"

let configDir = URL(fileURLWithPath: home, isDirectory: true)
let configFileURL = configDir.appendingPathComponent("config.toml")

var retainedController: PanelController?
var retainedWatcher: ConfigWatcher?
var retainedFocusTracker: WindowFocusTracker?

func startApp() {
    let config = Config.load(from: configFileURL)
    if let level = config.logLevel { Log.setLevel(level) }
    let store = Store(storageDir: configDir)
    let controller = PanelController(store: store, config: config, listWindows: listWindows)
    controller.panel.keys = translateKeybindings(from: config)
    controller.panel.tabSwitchOnHover = config.tabSwitch == "hover"
    controller.panel.tabHoverDelay = Double(config.tabHoverDelay) / 1000
    controller.onBeforeShow = {
        store.setSpace(currentSpaceId())
        invalidateWindowCache()
    }
    controller.onConfirm = { focusWindow($0) }
    controller.onCloseWindow = { closeWindow($0) }
    controller.onVerifyWindowClosed = { window in
        invalidateWindowCache()
        return listWindows().contains { $0.id == window.id }
    }

    let previewPanel = PreviewPanel()
    previewPanel.cacheLimit = config.previewCacheLimit
    let wallpaperPanel = WallpaperPanel()

    controller.onCapturePreview = { @MainActor wid in
        if let (image, frame) = await captureWindow(wid) {
            previewPanel.cache(windowId: wid, image: image, frame: frame)
        }
    }

    controller.onShowPreview = { focusedId, priorityOrder in
        previewPanel.applyBorderStyle(
            width: CGFloat(controller.config.previewBorder),
            radius: CGFloat(controller.config.previewBorderRadius),
            curve: controller.config.previewBorderCurve
        )
        wallpaperPanel.showCached()
        Task { await wallpaperPanel.refresh() }
        previewPanel.preWarm(windowIds: priorityOrder)
    }

    controller.onSelectionChanged = { window in
        if let w = window {
            previewPanel.show(windowId: w.id)
        } else {
            previewPanel.hide()
        }
    }

    let mru = AppMRU(storageDir: configDir)
    let launcher = LauncherPanel(mru: mru)
    controller.onStartLauncher = {
        controller.suspendForLauncher()
        launcher.show(paths: controller.config.launcherPaths, opacity: controller.config.panelOpacity)
    }
    var browseTap: EventTapHandle? = nil
    var quickTap: EventTapHandle? = nil
    var switcherTap: EventTapHandle? = nil
    var gestureTap: EventTapHandle? = nil
    var dismissGestureTap: EventTapHandle? = nil
    var allTaps: [EventTapHandle] { [browseTap, quickTap, switcherTap].compactMap { $0 } }

    let switcher = SwitcherPanel(titleLookup: { [weak store] wid in store?.title(for: wid) })

    func disableAllTaps() { allTaps.forEach { $0.disable() } }
    func enableAllTaps() { allTaps.forEach { $0.enable() } }

    func dismissPreviewAndReenable() {
        wallpaperPanel.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            previewPanel.dismiss()
        }
        enableAllTaps()
    }

    func browseToggle() {
        guard let screen = NSScreen.main else { return }
        disableAllTaps()
        controller.toggleAsync(on: screen)
    }

    controller.panel.onDismiss = dismissPreviewAndReenable
    launcher.onCancel = {
        controller.resumeFromLauncher()
    }
    launcher.onConfirm = {
        controller.dismissFromLauncher()
    }

    switcher.onConfirm = { focusWindow($0) }
    switcher.onSelectionChanged = { win in previewPanel.show(windowId: win.id) }
    switcher.onDismiss = dismissPreviewAndReenable

    // Browse trigger (supports comma-separated combos)
    func registerBrowseTap(_ trigger: String) {
        browseTap?.destroy()
        browseTap = nil
        guard let keys = parseHotkeys(trigger) else {
            if !trigger.isEmpty { appLog.error("invalid trigger: \"\(trigger)\"") }
            return
        }
        appLog.info("browse trigger: \(keys.count) combos")
        browseTap = registerHotkey(keys: keys, onKeyDown: { ensureGestureTaps(); browseToggle() })
    }

    // Quick trigger (supports comma-separated combos: "opt+tab,opt+k")
    func registerQuickTap(_ trigger: String) {
        quickTap?.destroy()
        quickTap = nil
        guard let keys = parseHotkeys(trigger) else {
            if !trigger.isEmpty { appLog.error("invalid quick_trigger: \"\(trigger)\"") }
            return
        }
        quickTap = registerHotkey(
            keys: keys,
            onKeyDown: {
                guard let screen = NSScreen.main else { return }
                if controller.panel.isVisible && controller.panel.state.quickSession {
                    if controller.config.mruOrder { controller.panel.cycleQuickMode() }
                    return
                }
                disableAllTaps()
                ensureGestureTaps()
                controller.showQuick(on: screen)
            },
            onModifierUp: {
                controller.panel.confirmIfVisible()
            }
        )
    }

    // Switcher trigger
    func registerSwitcherTap(_ trigger: String) {
        switcherTap?.destroy()
        switcherTap = nil
        guard let keys = parseHotkeys(trigger) else {
            if !trigger.isEmpty { appLog.error("invalid switcher trigger: \"\(trigger)\"") }
            return
        }
        switcherTap = registerHotkey(
            keys: keys,
            onKeyDown: {
                guard NSScreen.main != nil else { return }
                if switcher.isVisible {
                    switcher.cycleQuickMode()
                    return
                }
                disableAllTaps()
                ensureGestureTaps()
                invalidateWindowCache()
                let windows = listWindows()
                guard !windows.isEmpty else { enableAllTaps(); return }
                store.setSpace(currentSpaceId())
                switcher.keys = controller.panel.keys
                let autoSelectId = windows[windows.count > 1 ? 1 : 0].id
                let tap = switcherTap
                Task { @MainActor in
                    if let (image, frame) = await captureWindow(autoSelectId) {
                        previewPanel.cache(windowId: autoSelectId, image: image, frame: frame)
                    }
                    await wallpaperPanel.refresh()
                    wallpaperPanel.showCached()
                    switcher.show(
                        windows: windows,
                        visibleRows: controller.config.switcherVisibleRows,
                        width: controller.config.switcherWidth,
                        opacity: controller.config.panelOpacity
                    )
                    switcher.cycleQuickMode()
                    previewPanel.preWarm(windowIds: windows.map(\.id))
                    tap?.confirmIfModifierReleased()
                }
            },
            onModifierUp: {
                switcher.confirmIfVisible()
            }
        )
    }

    func ensureGestureTaps() {
        if let tap = gestureTap { destroyGestureTap(tap) }
        gestureTap = nil
        if let tap = dismissGestureTap { destroyGestureTap(tap) }
        dismissGestureTap = nil

        let gesture = controller.config.gesture
        let dismissGesture = controller.config.dismissGesture

        if !gesture.isEmpty, let gc = parseGestureConfig(gesture) {
            gestureTap = registerGestureTrigger(config: gc) {
                guard !controller.panel.isVisible else { return }
                controller.onShown = {
                    controller.onShown = nil
                    let row = controller.panel.state.selectedRow
                    let col = controller.panel.state.selectedColumn
                    if let view = controller.panel.spreadsheetView.findView(id: "row-\(col)-\(row)") {
                        let frame = view.convert(view.bounds, to: nil)
                        let screenFrame = controller.panel.convertToScreen(frame)
                        let primaryH = NSScreen.screens.first?.frame.height ?? screenFrame.midY
                        CGWarpMouseCursorPosition(CGPoint(x: screenFrame.midX, y: primaryH - screenFrame.midY))
                    }
                }
                browseToggle()
            }
        }

        if !dismissGesture.isEmpty, let gc = parseGestureConfig(dismissGesture) {
            dismissGestureTap = registerGestureTrigger(config: gc) {
                if controller.panel.isVisible { controller.panel.dismiss() }
                else if switcher.isVisible { switcher.dismiss() }
            }
        }

        let openResult = gestureTap != nil ? "ok" : (gesture.isEmpty ? "disabled" : "FAILED")
        let dismissResult = dismissGestureTap != nil ? "ok" : (dismissGesture.isEmpty ? "disabled" : "FAILED")
        appLog.info("gesture taps — open: \(openResult), dismiss: \(dismissResult)")
    }

    registerBrowseTap(config.trigger)
    registerQuickTap(config.quickTrigger)
    registerSwitcherTap(config.switcherTrigger)
    ensureGestureTaps()

    controller.onQuickShown = {
        quickTap?.confirmIfModifierReleased()
    }

    // HID gesture taps (cghidEventTap) silently stop receiving events after
    // sleep/wake on ad-hoc signed apps. Recreating taps in the same process
    // doesn't help — macOS blocks HID trust for the entire process after
    // unclean power events. Exiting lets launchd KeepAlive restart us with
    // fresh trust. All state is persisted to JSON, so nothing is lost.
    NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
    ) { _ in
        appLog.info("system wake detected — exiting for restart")
        exit(0)
    }

    let watcher = ConfigWatcher(fileURL: configFileURL) { newConfig in
        if let level = newConfig.logLevel { Log.setLevel(level) }
        controller.config = newConfig
        controller.panel.keys = translateKeybindings(from: newConfig)
        controller.panel.tabSwitchOnHover = newConfig.tabSwitch == "hover"
        controller.panel.tabHoverDelay = Double(newConfig.tabHoverDelay) / 1000
        switcher.keys = controller.panel.keys
        previewPanel.cacheLimit = newConfig.previewCacheLimit
        appLog.info("config reloaded — re-registering all hotkeys")
        registerBrowseTap(newConfig.trigger)
        registerQuickTap(newConfig.quickTrigger)
        registerSwitcherTap(newConfig.switcherTrigger)
        ensureGestureTaps()
    }
    watcher.start()

    let focusTracker = WindowFocusTracker { wid in
        store.setSpace(currentSpaceId())
        store.setActiveFocus(windowId: wid)
    }

    URLHandler.shared.onURL = { url in
        controller.panel.infoText = url.absoluteString
        browseToggle()
    }

    retainedController = controller
    retainedWatcher = watcher
    retainedFocusTracker = focusTracker
}

func waitForAccessibilityThenStart() {
    let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    if AXIsProcessTrustedWithOptions(prompt) {
        if !CGPreflightScreenCaptureAccess() {
            appLog.warning("Screen Recording permission not granted — window previews disabled. Grant in System Settings → Privacy & Security → Screen Recording")
        }
        startApp()
        return
    }
    appLog.warning("waiting for Accessibility permission — grant it in System Settings → Privacy & Security → Accessibility")
    DispatchQueue.global().async {
        while !AXIsProcessTrusted() {
            Thread.sleep(forTimeInterval: 1.0)
        }
        appLog.info("Accessibility permission granted")
        DispatchQueue.main.async {
            if !CGPreflightScreenCaptureAccess() {
                appLog.warning("Screen Recording permission not granted — window previews disabled. Grant in System Settings → Privacy & Security → Screen Recording")
            }
            startApp()
        }
    }
}

app.delegate = URLHandler.shared
NSAppleEventManager.shared().setEventHandler(
    URLHandler.shared, andSelector: #selector(URLHandler.handleURL(_:withReply:)),
    forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))

DispatchQueue.main.async { waitForAccessibilityThenStart() }
app.run()
