import Foundation
import Logging
import WindowMapCore

class ConfigWatcher {
    private let log = Log(module: "ConfigWatcher")
    private let fileURL: URL
    private let dirURL: URL
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private let onChange: (Config) -> Void

    init(fileURL: URL, onChange: @escaping (Config) -> Void) {
        self.fileURL = fileURL
        self.dirURL = fileURL.deletingLastPathComponent()
        self.onChange = onChange
    }

    func start() {
        source?.cancel()
        source = nil
        if FileManager.default.fileExists(atPath: fileURL.path) {
            watchFile()
        } else {
            watchDirectory()
        }
    }

    // MARK: - Watch strategies

    /// Watches the config file directly via kqueue for write, delete, and
    /// rename events. Falls back to directory watching if the file descriptor
    /// cannot be opened.
    private func watchFile() {
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { watchDirectory(); return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in self?.handleEvent() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    /// Watches the parent directory for write events. When the config file
    /// appears, switches to file-level watching.
    private func watchDirectory() {
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let fd = open(dirURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in
            guard let self, FileManager.default.fileExists(atPath: fileURL.path) else { return }
            source?.cancel()
            watchFile()
            scheduleReload()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    // MARK: - Event handling

    /// Handles a file-system event by cancelling the current source,
    /// scheduling a debounced reload, and re-establishing the watch after
    /// 200ms. The delay handles editors that delete+recreate files on save.
    private func handleEvent() {
        source?.cancel()
        scheduleReload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.start() }
    }

    /// Debounces reload calls by 100ms to coalesce rapid writes.
    private func scheduleReload() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    /// Calls Config.reload and invokes the onChange callback on success.
    /// Logs warnings on failure; the previous config remains active.
    private func reload() {
        let (config, warnings) = Config.reload(from: fileURL)
        for w in warnings { log.warning(w) }
        guard let config else { return }
        onChange(config)
    }
}
