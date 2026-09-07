import AppKit
import Logging

private let log = Log(module: "WallpaperPanel")

class WallpaperPanel: NSPanel {
    private let imageView = NSImageView()
    private var cachedImage: NSImage?
    private var lastRefreshed: CFAbsoluteTime = 0

    convenience init() {
        self.init(contentRect: .zero,
                  styleMask: [.nonactivatingPanel, .borderless],
                  backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating

        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        contentView = imageView
    }

    func showCached() {
        guard let screen = NSScreen.main else { return }
        let image = cachedImage ?? loadDesktopImage(screen: screen)
        guard let image else { return }
        setFrame(screen.frame, display: false)
        imageView.image = image
        orderFront(nil)
    }

    func refresh() async {
        guard cachedImage == nil || CFAbsoluteTimeGetCurrent() - lastRefreshed > 30,
              let screen = NSScreen.main,
              let image = await captureDesktop(screen: screen) else { return }
        log.debug("refreshed wallpaper")
        cachedImage = image
        lastRefreshed = CFAbsoluteTimeGetCurrent()
        if isVisible { imageView.image = image }
    }

    func hide() {
        orderOut(nil)
    }
}
