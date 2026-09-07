import AppKit
import ApplicationServices
import Logging
import ScreenCaptureKit
import WindowMapCore

// MARK: - Cache

private var cachedWindows: [Window]?
private var cachedCGWindowInfo: [CGWindowID: CGWindowInfo]?
private var cacheTimestamp: CFAbsoluteTime = 0
private let cacheTTL: CFAbsoluteTime = 1.0

func invalidateWindowCache() {
    cachedWindows = nil
    cachedCGWindowInfo = nil
}

// MARK: - CGWindowInfo

private struct CGWindowInfo {
    var zOrder: Int
    var title: String?
    var layer: Int
}

private func getCGWindowInfoMap() -> [CGWindowID: CGWindowInfo] {
    let now = CFAbsoluteTimeGetCurrent()
    if let cached = cachedCGWindowInfo, now - cacheTimestamp < cacheTTL { return cached }

    let options: CGWindowListOption = [.excludeDesktopElements, .optionOnScreenOnly]
    guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return [:]
    }
    var result: [CGWindowID: CGWindowInfo] = [:]
    for (index, info) in windowList.enumerated() {
        guard let windowId = info[kCGWindowNumber as String] as? CGWindowID else { continue }
        result[windowId] = CGWindowInfo(
            zOrder: windowList.count - index,
            title: info[kCGWindowName as String] as? String,
            layer: info[kCGWindowLayer as String] as? Int ?? 0
        )
    }
    cachedCGWindowInfo = result
    cacheTimestamp = now
    return result
}

// MARK: - List

func listWindows() -> [Window] {
    let now = CFAbsoluteTimeGetCurrent()
    if let cached = cachedWindows, now - cacheTimestamp < cacheTTL { return cached }

    let myPid = ProcessInfo.processInfo.processIdentifier
    let cgWindowInfo = getCGWindowInfoMap()
    var results: [Window] = []

    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != myPid {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
              let axWindows = ref as? [AXUIElement] else { continue }

        for axWindow in axWindows {
            var winId: CGWindowID = 0
            guard _AXUIElementGetWindow(axWindow, &winId) == .success, winId != 0 else { continue }

            if let info = cgWindowInfo[winId], info.layer > 0 { continue }

            var titleRef: AnyObject?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            var title = titleRef as? String ?? ""
            if title.isEmpty, let cgTitle = cgWindowInfo[winId]?.title { title = cgTitle }

            var subroleRef: AnyObject?
            if AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subroleRef) == .success,
               let subrole = subroleRef as? String,
               !["AXStandardWindow", "AXDialog"].contains(subrole) { continue }

            var size = CGSize.zero
            var sizeRef: AnyObject?
            if AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
               let axVal = sizeRef {
                AXValueGetValue(axVal as! AXValue, .cgSize, &size)
                if size.width < 100 || size.height < 50 { continue }
            }

            var pos = CGPoint.zero
            var posRef: AnyObject?
            if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
               let axVal = posRef {
                AXValueGetValue(axVal as! AXValue, .cgPoint, &pos)
            }

            let frame = CGRect(origin: pos, size: size)
            results.append(Window(id: winId, app: app, title: title, axElement: axWindow, frame: frame))
        }
    }

    results.sort { (cgWindowInfo[$0.id]?.zOrder ?? 0) > (cgWindowInfo[$1.id]?.zOrder ?? 0) }
    cachedWindows = results
    cacheTimestamp = now
    return results
}

// MARK: - Space ID

@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> UInt32
@_silgen_name("CGSGetActiveSpace")   private func CGSGetActiveSpace(_ cid: UInt32) -> Int

func currentSpaceId() -> Int { CGSGetActiveSpace(CGSMainConnectionID()) }

// MARK: - Focus / Close

@discardableResult
func focusWindow(_ window: Window) -> Bool {
    AXUIElementSetAttributeValue(window.axElement, kAXMainAttribute as CFString, kCFBooleanTrue)
    AXUIElementPerformAction(window.axElement, kAXRaiseAction as CFString)
    return window.app.activate()
}

func closeWindow(_ window: Window) {
    var btnRef: AnyObject?
    guard AXUIElementCopyAttributeValue(window.axElement, kAXCloseButtonAttribute as CFString, &btnRef) == .success else { return }
    AXUIElementPerformAction(btnRef as! AXUIElement, kAXPressAction as CFString)
}

func focusedWindowId() -> CGWindowID? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref) == .success else { return nil }
    var wid: CGWindowID = 0
    _ = _AXUIElementGetWindow(ref as! AXUIElement, &wid)
    return wid > 0 ? wid : nil
}

// MARK: - Capture

func fetchShareableWindows() async -> [CGWindowID: SCWindow]? {
    guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return nil }
    return Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { _, new in new })
}

private let log = Log(module: "Windows")

func captureWindow(_ windowId: CGWindowID) async -> (CGImage, NSRect)? {
    guard let scWindows = await fetchShareableWindows() else {
        log.debug("\(windowId): fetchShareableWindows failed")
        return nil
    }
    guard let scWindow = scWindows[windowId] else {
        log.debug("\(windowId): not found in \(scWindows.count) shareable windows")
        return nil
    }
    return await captureWindow(scWindow)
}

func captureWindow(_ scWindow: SCWindow) async -> (CGImage, NSRect)? {
    guard !Task.isCancelled else { return nil }
    let primaryH = NSScreen.screens.first?.frame.height ?? 0
    let mid = NSPoint(x: scWindow.frame.midX, y: primaryH - scWindow.frame.midY)
    let scale = NSScreen.screens.first(where: { $0.frame.contains(mid) })?.backingScaleFactor ?? 2.0
    let filter = SCContentFilter(desktopIndependentWindow: scWindow)
    let config = SCStreamConfiguration()
    config.width = Int(scWindow.frame.width * scale)
    config.height = Int(scWindow.frame.height * scale)
    config.scalesToFit = false
    config.showsCursor = false
    guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
    let frame = NSRect(x: scWindow.frame.origin.x,
                       y: primaryH - scWindow.frame.origin.y - scWindow.frame.height,
                       width: scWindow.frame.width, height: scWindow.frame.height)
    return (image, frame)
}

@MainActor func captureDesktop(screen: NSScreen) async -> NSImage? {
    guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
          let scWindow = content.windows.first(where: {
              $0.owningApplication?.bundleIdentifier == "com.apple.dock"
              && $0.title?.hasPrefix("Wallpaper-") == true
          }) else { return nil }
    let scale = screen.backingScaleFactor
    let filter = SCContentFilter(desktopIndependentWindow: scWindow)
    let config = SCStreamConfiguration()
    config.width = Int(screen.frame.width * scale)
    config.height = Int(screen.frame.height * scale)
    config.scalesToFit = false
    config.showsCursor = false
    guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
    return NSImage(cgImage: cg, size: screen.frame.size)
}

func loadDesktopImage(screen: NSScreen) -> NSImage? {
    guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
          let data = try? Data(contentsOf: url, options: .uncached),
          data.count > 1024 else { return nil }
    return NSImage(data: data)
}
