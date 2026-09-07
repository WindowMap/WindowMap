import AppKit
import Carbon.HIToolbox
import Logging

private let log = Log(module: "URLHandler")

class URLHandler: NSObject, NSApplicationDelegate {
    static let shared = URLHandler()
    var onURL: ((URL) -> Void)?

    @objc func handleURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }
        log.info("received URL: \(url.absoluteString)")
        copyToClipboard(url.absoluteString)
        onURL?(url)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            log.info("received URL: \(url.absoluteString)")
            copyToClipboard(url.absoluteString)
            onURL?(url)
        }
    }

    private func copyToClipboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
