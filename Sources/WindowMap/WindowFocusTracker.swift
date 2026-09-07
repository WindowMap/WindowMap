import AppKit
import ApplicationServices
import Logging

private let log = Log(module: "WindowFocusTracker")

final class WindowFocusTracker: NSObject {
    private let callback: (CGWindowID) -> Void
    private var observers: [pid_t: AXObserver] = [:]
    private var pendingCallback: DispatchWorkItem?

    init(onFocusChanged: @escaping (CGWindowID) -> Void) {
        self.callback = onFocusChanged
        super.init()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            addObserver(for: app)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    private func addObserver(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        var observer: AXObserver?
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<WindowFocusTracker>.fromOpaque(refcon).takeUnretainedValue().scheduleCallback()
        }, &observer) == .success, let obs = observer else { return }
        let axApp = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(obs, axApp, kAXFocusedWindowChangedNotification as CFString, selfPtr)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
        log.info("observing \(app.localizedName ?? "pid:\(pid)")")
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular else { return }
        addObserver(for: app)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if let obs = observers.removeValue(forKey: app.processIdentifier) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
            log.info("removed \(app.localizedName ?? "pid:\(app.processIdentifier)")")
        }
    }

    private func scheduleCallback() {
        pendingCallback?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard AXIsProcessTrusted() else {
                log.error("Accessibility permission revoked — exiting")
                exit(1)
            }
            guard let wid = focusedWindowId() else { return }
            log.debug("focus → \(wid)")
            self.callback(wid)
        }
        pendingCallback = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }
}
