import Foundation

public struct AppInfo {
    public let bundleID: String
    public let name: String
    public let nameLowercased: String
    public let path: String

    public init(bundleID: String, name: String, path: String) {
        self.bundleID = bundleID
        self.name = name
        self.nameLowercased = name.lowercased()
        self.path = path
    }
}

private var appCache: [AppInfo]?
private var appCacheTime: CFAbsoluteTime = 0
private let appCacheTTL: CFAbsoluteTime = 60

public func listApps(paths: [String]) -> [AppInfo] {
    let now = CFAbsoluteTimeGetCurrent()
    if let cache = appCache, now - appCacheTime < appCacheTTL { return cache }

    var seen = Set<String>()
    var result: [AppInfo] = []
    for raw in paths {
        let expanded = (raw as NSString).expandingTildeInPath
        for app in scanApps(in: expanded) where !seen.contains(app.bundleID) {
            seen.insert(app.bundleID)
            result.append(app)
        }
    }
    result.sort { $0.nameLowercased < $1.nameLowercased }
    appCache = result
    appCacheTime = now
    return result
}

private func scanApps(in directory: String) -> [AppInfo] {
    guard let enumerator = FileManager.default.enumerator(
        at: URL(fileURLWithPath: directory),
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else { return [] }

    var apps: [AppInfo] = []
    for case let url as URL in enumerator {
        guard url.pathExtension == "app" else { continue }
        enumerator.skipDescendants()
        if let app = appFromBundle(at: url) { apps.append(app) }
    }
    return apps
}

private func appFromBundle(at url: URL) -> AppInfo? {
    let plist = url.appendingPathComponent("Contents/Info.plist")
    guard let data = try? Data(contentsOf: plist),
          let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let bundleID = dict["CFBundleIdentifier"] as? String else { return nil }
    let name = (dict["CFBundleDisplayName"] as? String)
        ?? (dict["CFBundleName"] as? String)
        ?? url.deletingPathExtension().lastPathComponent
    return AppInfo(bundleID: bundleID, name: name, path: url.path)
}

// MARK: – MRU

public class AppMRU {
    private let fileURL: URL
    private static let maxEntries = 20
    private var cached: [String]?

    public init(storageDir: URL) {
        self.fileURL = storageDir.appendingPathComponent("app-mru.json")
    }

    public func mruBundleIDs() -> [String] {
        if let c = cached { return c }
        guard let data = try? Data(contentsOf: fileURL),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            cached = []; return []
        }
        cached = ids
        return ids
    }

    public func record(_ bundleID: String) {
        var ids = mruBundleIDs()
        ids.removeAll { $0 == bundleID }
        ids.insert(bundleID, at: 0)
        if ids.count > Self.maxEntries { ids = Array(ids.prefix(Self.maxEntries)) }
        cached = ids
        if let data = try? JSONEncoder().encode(ids) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
