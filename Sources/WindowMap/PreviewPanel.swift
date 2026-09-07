import AppKit
import Logging
import WindowMapCore

private let log = Log(module: "PreviewPanel")

private class CachedPreview: NSObject {
    let image: CGImage; let frame: NSRect
    init(_ image: CGImage, _ frame: NSRect) { self.image = image; self.frame = frame }
}

class PreviewPanel: NSPanel {
    private let imageView = NSImageView()
    private var task: Task<Void, Never>?
    private var preWarmTask: Task<Void, Never>?
    private let imageCache = NSCache<NSNumber, CachedPreview>()

    var cacheLimit: Int {
        get { imageCache.countLimit }
        set { imageCache.countLimit = newValue }
    }

    convenience init() {
        self.init(contentRect: .zero,
                  styleMask: [.nonactivatingPanel, .borderless],
                  backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = true
        level = .floating

        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]

        let content = NSView()
        content.wantsLayer = true
        content.addSubview(imageView)
        contentView = content
    }

    func applyBorderStyle(width: CGFloat, radius: CGFloat, curve: String) {
        contentView?.layer?.borderWidth = width
        contentView?.layer?.borderColor = width > 0 ? NSColor.controlAccentColor.cgColor : nil
        contentView?.layer?.cornerRadius = radius
        contentView?.layer?.cornerCurve = curve == "continuous" ? .continuous : .circular
        contentView?.layer?.masksToBounds = radius > 0
    }

    func show(windowId: CGWindowID) {
        task?.cancel()
        let key = NSNumber(value: windowId)
        if let cached = imageCache.object(forKey: key) {
            log.debug("show \(windowId): cache HIT")
            displayPreview(cached)
            return
        }
        log.debug("show \(windowId): cache MISS — capturing async")
        task = Task { @MainActor in
            let result = await captureWindow(windowId)
            guard !Task.isCancelled else {
                log.debug("show \(windowId): capture cancelled")
                return
            }
            guard let (image, frame) = result else {
                log.debug("show \(windowId): capture FAILED")
                return
            }
            log.debug("show \(windowId): captured \(image.width)×\(image.height) — showing")
            let preview = CachedPreview(image, frame)
            self.imageCache.setObject(preview, forKey: key)
            self.displayPreview(preview)
        }
    }

    private func displayPreview(_ cached: CachedPreview) {
        setFrame(cached.frame, display: false)
        imageView.image = NSImage(cgImage: cached.image, size: cached.frame.size)
        orderFront(nil)
    }

    func cache(windowId: CGWindowID, image: CGImage, frame: NSRect) {
        log.debug("cache \(windowId): \(image.width)×\(image.height)")
        imageCache.setObject(CachedPreview(image, frame), forKey: NSNumber(value: windowId))
    }

    func preWarm(windowIds: [CGWindowID]) {
        preWarmTask?.cancel()
        preWarmTask = Task { @MainActor in
            guard let scWindows = await fetchShareableWindows() else { return }
            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                for id in windowIds {
                    guard !Task.isCancelled else { break }
                    let key = NSNumber(value: id)
                    guard imageCache.object(forKey: key) == nil else { continue }
                    guard let scWindow = scWindows[id] else { continue }
                    if inFlight >= 4 {
                        await group.next()
                        inFlight -= 1
                    }
                    inFlight += 1
                    group.addTask {
                        guard let (image, frame) = await captureWindow(scWindow) else { return }
                        await MainActor.run {
                            self.imageCache.setObject(CachedPreview(image, frame),
                                                      forKey: NSNumber(value: id))
                        }
                    }
                }
            }
        }
    }

    func hide() {
        task?.cancel()
        task = nil
        orderOut(nil)
    }

    func dismiss() {
        preWarmTask?.cancel()
        preWarmTask = nil
        imageCache.removeAllObjects()
        hide()
    }
}
