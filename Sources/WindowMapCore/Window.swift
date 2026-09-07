import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
public func _AXUIElementGetWindow(_ element: AXUIElement, _ windowId: UnsafeMutablePointer<CGWindowID>) -> AXError

public func normalizeTitle(_ s: String) -> String {
    s.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

public struct Window {
    public let id: CGWindowID
    public let app: NSRunningApplication
    public let title: String
    public let axElement: AXUIElement
    public let bundleId: String?
    public let appName: String?
    public let frame: CGRect

    public init(id: CGWindowID, app: NSRunningApplication, title: String, axElement: AXUIElement, bundleId: String? = nil, frame: CGRect = .zero) {
        self.id = id; self.app = app; self.title = normalizeTitle(title); self.axElement = axElement
        self.bundleId = bundleId ?? app.bundleIdentifier
        self.appName = app.localizedName
        self.frame = frame
    }
}
