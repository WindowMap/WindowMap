import AppKit
import Logging

struct WindowEntry: Codable {
    var windowId: UInt32
    var title: String
    var customTitle: String?
    var bundleId: String?
    var frame: [Int]?
    var lastSeenAt: Date?
}

private func frameArray(_ r: CGRect) -> [Int] {
    [Int(r.origin.x), Int(r.origin.y), Int(r.width), Int(r.height)]
}

private func frameKey(_ f: [Int]) -> String { f.map(String.init).joined(separator: ",") }

struct WindowsFile: Codable {
    var windowEntries: [WindowEntry]
}

struct SpaceFile: Codable {
    var contexts: [Context]
    var activeContextId: String?
    var activeWorkspaceId: String?
    var lastSeen: Date?
}

public struct Context: Codable {
    public var id: UUID = UUID()
    public var name: String
    public var workspaces: [Workspace]
    public init(name: String, workspaces: [Workspace] = [Workspace(name: "Workspace0")]) {
        self.name = name; self.workspaces = workspaces
    }
}

public class Store {
    private let log = Log(module: "Store")
    private var windowEntries: [WindowEntry] = []
    private var spaceContexts: [Int: [Context]] = [:]
    private var spaceActiveContext: [Int: UUID] = [:]
    private var spaceActiveWorkspace: [Int: UUID] = [:]
    private var spaceLastSeen: [Int: Date] = [:]
    private var currentSpace = 0
    private let dir: URL
    private var saveTask: DispatchWorkItem?

    public init(storageDir: URL) {
        dir = storageDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
        if spaceContexts[currentSpace] == nil { setSpace(currentSpace) }
    }

    public func setSpace(_ spaceId: Int) {
        if spaceId != currentSpace {
            log.info("setSpace: \(currentSpace) → \(spaceId)")
        }
        currentSpace = spaceId
        spaceLastSeen[spaceId] = Date()
        if spaceContexts[spaceId] == nil {
            spaceContexts[spaceId] = [Context(name: "Context0")]
        }
        if spaceActiveContext[spaceId] == nil {
            spaceActiveContext[spaceId] = spaceContexts[spaceId]?.first?.id
        }
    }

    // MARK: – Active-context workspace accessor

    public func workspaces() -> [Workspace] {
        let idx = resolvedContextIndex()
        guard let ctxs = spaceContexts[currentSpace], idx < ctxs.count else {
            return [Workspace(name: "Workspace0")]
        }
        return ctxs[idx].workspaces
    }

    private func setWorkspaces(_ newValue: [Workspace]) {
        let idx = resolvedContextIndex()
        guard var ctxs = spaceContexts[currentSpace], idx < ctxs.count else { return }
        ctxs[idx].workspaces = newValue
        spaceContexts[currentSpace] = ctxs
    }

    // MARK: – Context API

    public func contexts() -> [Context] {
        spaceContexts[currentSpace] ?? []
    }

    public func activeContextId() -> UUID? {
        let idx = resolvedContextIndex()
        guard let ctxs = spaceContexts[currentSpace], idx < ctxs.count else { return nil }
        return ctxs[idx].id
    }

    public func setActiveContext(id: UUID) {
        guard let ctxs = spaceContexts[currentSpace],
              ctxs.contains(where: { $0.id == id }) else { return }
        spaceActiveContext[currentSpace] = id
        flush()
    }

    @discardableResult
    public func addContext(name: String) -> UUID {
        var ctxs = spaceContexts[currentSpace] ?? []
        let ctx = Context(name: name)
        ctxs.insert(ctx, at: 0)
        spaceContexts[currentSpace] = ctxs
        spaceActiveContext[currentSpace] = ctx.id
        flush()
        return ctx.id
    }

    public func renameContext(id: UUID, name: String) {
        guard var ctxs = spaceContexts[currentSpace],
              let index = ctxs.firstIndex(where: { $0.id == id }) else { return }
        ctxs[index].name = name
        spaceContexts[currentSpace] = ctxs
        flush()
    }

    public func deleteContext(id: UUID) {
        guard isContextDeletable(id: id),
              var ctxs = spaceContexts[currentSpace],
              let index = ctxs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = spaceActiveContext[currentSpace] == id
        ctxs.remove(at: index)
        spaceContexts[currentSpace] = ctxs
        if wasActive {
            let newIdx = min(index, ctxs.count - 1)
            spaceActiveContext[currentSpace] = ctxs[newIdx].id
        }
        flush()
    }

    public func isContextDeletable(id: UUID) -> Bool {
        guard let ctxs = spaceContexts[currentSpace],
              ctxs.count > 1,
              let ctx = ctxs.first(where: { $0.id == id }) else { return false }
        return ctx.workspaces.allSatisfy { $0.windowIds.isEmpty }
    }

    private func resolvedContextIndex() -> Int {
        guard let activeId = spaceActiveContext[currentSpace],
              let ctxs = spaceContexts[currentSpace],
              let idx = ctxs.firstIndex(where: { $0.id == activeId }) else { return 0 }
        return idx
    }

    /// Returns the index of the context whose workspaces contain the given window ID,
    /// or nil if no context owns it.
    public func setActiveFocus(windowId: UInt32) {
        guard let ctxs = spaceContexts[currentSpace] else { return }
        for ctx in ctxs {
            if let ws = ctx.workspaces.first(where: { $0.windowIds.contains(windowId) }) {
                guard spaceActiveContext[currentSpace] != ctx.id ||
                      spaceActiveWorkspace[currentSpace] != ws.id else { return }
                spaceActiveContext[currentSpace] = ctx.id
                spaceActiveWorkspace[currentSpace] = ws.id
                return
            }
        }
    }

    public func contextId(containingWindowId windowId: UInt32) -> UUID? {
        guard let ctxs = spaceContexts[currentSpace] else { return nil }
        return ctxs.first(where: { $0.workspaces.contains(where: { $0.windowIds.contains(windowId) }) })?.id
    }

    private func allWindowIds(in contexts: [Context]) -> Set<UInt32> {
        Set(contexts.flatMap { $0.workspaces.flatMap { $0.windowIds } })
    }

    // MARK: – Window ingestion

    public func update(windows liveWindows: [Window]) {
        log.info("update with \(liveWindows.count) windows on space \(currentSpace)")
        guard !liveWindows.isEmpty else { return }
        let liveIds = Set(liveWindows.map { $0.id })
        let (idRemap, matchedLiveIds) = remapIds(liveWindows: liveWindows, liveIds: liveIds)
        applyRemap(idRemap)
        createFreshEntries(liveWindows: liveWindows, matchedLiveIds: matchedLiveIds)
        pruneOldEntries()

        appendUnassignedWindows(liveWindows)
        scheduleSave()
    }

    private func remapIds(liveWindows: [Window], liveIds: Set<UInt32>) -> (idRemap: [UInt32: UInt32], matchedLiveIds: Set<UInt32>) {
        let now = Date()
        var idRemap: [UInt32: UInt32] = [:]
        var matchedLiveIds = Set<UInt32>()
        let otherSpaceWindowIds = spaceContexts
            .filter { $0.key != currentSpace }
            .values.reduce(into: Set<UInt32>()) { $0.formUnion(allWindowIds(in: $1)) }

        // Step 1: Direct ID match
        var entryIndex: [UInt32: Int] = [:]
        for (i, e) in windowEntries.enumerated() { entryIndex[e.windowId] = i }

        var directMatched = 0
        var bundleMismatch = 0
        var unmatched = 0
        for w in liveWindows where !w.title.isEmpty {
            if let idx = entryIndex[w.id] {
                if let entryBundleId = windowEntries[idx].bundleId, entryBundleId != w.bundleId {
                    log.info("remap: bundleId mismatch for \(w.id) — entry=\(windowEntries[idx].bundleId ?? "nil") live=\(w.bundleId ?? "nil")")
                    bundleMismatch += 1
                    windowEntries.remove(at: idx)
                    entryIndex.removeValue(forKey: w.id)
                } else {
                    directMatched += 1
                    windowEntries[idx].title = w.title
                    windowEntries[idx].bundleId = w.bundleId
                    windowEntries[idx].frame = frameArray(w.frame)
                    windowEntries[idx].lastSeenAt = now
                    matchedLiveIds.insert(w.id)
                }
            } else {
                unmatched += 1
            }
        }
        log.info("remap step1: direct=\(directMatched) bundleMismatch=\(bundleMismatch) unmatched=\(unmatched) entries=\(windowEntries.count)")

        // Steps 2–4: match orphan entries to unmatched windows by key (unique 1:1 only)
        let orphanEntries: [(index: Int, entry: WindowEntry)] = windowEntries.enumerated().compactMap { i, e in
            guard !liveIds.contains(e.windowId), !otherSpaceWindowIds.contains(e.windowId) else { return nil }
            return (i, e)
        }
        let unmatchedWindows = liveWindows.filter { !$0.title.isEmpty && !matchedLiveIds.contains($0.id) }
        var matchedOrphanIndices = Set<Int>()
        var matchedWindowIds = Set<UInt32>()

        func matchByKey(entryKey: (WindowEntry) -> String?, windowKey: (Window) -> String?, updateTitle: Bool) {
            var byEntry: [String: [(index: Int, entry: WindowEntry)]] = [:]
            for o in orphanEntries where !matchedOrphanIndices.contains(o.index) {
                guard let k = entryKey(o.entry) else { continue }
                byEntry[k, default: []].append(o)
            }
            var byWindow: [String: [Window]] = [:]
            for w in unmatchedWindows where !matchedWindowIds.contains(w.id) {
                guard let k = windowKey(w) else { continue }
                byWindow[k, default: []].append(w)
            }
            for (k, orphans) in byEntry {
                guard orphans.count == 1, let windows = byWindow[k], windows.count == 1 else { continue }
                let o = orphans[0]; let w = windows[0]
                idRemap[o.entry.windowId] = w.id
                windowEntries[o.index].windowId = w.id
                if updateTitle { windowEntries[o.index].title = w.title }
                windowEntries[o.index].frame = frameArray(w.frame)
                windowEntries[o.index].lastSeenAt = now
                matchedOrphanIndices.insert(o.index)
                matchedWindowIds.insert(w.id)
                matchedLiveIds.insert(w.id)
            }
        }

        matchByKey(
            entryKey: { "\($0.bundleId ?? "")\t\($0.title)" },
            windowKey: { "\($0.bundleId ?? "")\t\($0.title)" },
            updateTitle: false
        )
        matchByKey(
            entryKey: { $0.bundleId },
            windowKey: { $0.bundleId },
            updateTitle: true
        )
        matchByKey(
            entryKey: { guard let bid = $0.bundleId, let f = $0.frame else { return nil }; return "\(bid)\t\(frameKey(f))" },
            windowKey: { guard let bid = $0.bundleId else { return nil }; return "\(bid)\t\(frameKey(frameArray($0.frame)))" },
            updateTitle: true
        )

        return (idRemap, matchedLiveIds)
    }

    private func applyRemap(_ idRemap: [UInt32: UInt32]) {
        guard var ctxs = spaceContexts[currentSpace] else { return }
        for ci in ctxs.indices {
            for wi in ctxs[ci].workspaces.indices {
                ctxs[ci].workspaces[wi].windowIds = ctxs[ci].workspaces[wi].windowIds.map { id in
                    idRemap[id] ?? id
                }
            }
        }
        spaceContexts[currentSpace] = ctxs
    }

    private func createFreshEntries(liveWindows: [Window], matchedLiveIds: Set<UInt32>) {
        let now = Date()
        for w in liveWindows where !w.title.isEmpty && !matchedLiveIds.contains(w.id) {
            windowEntries.append(WindowEntry(windowId: w.id, title: w.title, bundleId: w.bundleId, frame: frameArray(w.frame), lastSeenAt: now))
        }
    }

    private func pruneOldEntries() {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        windowEntries.removeAll { ($0.lastSeenAt ?? .distantPast) < cutoff }
    }

    private func appendUnassignedWindows(_ liveWindows: [Window]) {
        let assigned = allWindowIds(in: spaceContexts[currentSpace] ?? [])
        var ws = workspaces()
        let targetIdx = spaceActiveWorkspace[currentSpace]
            .flatMap { id in ws.firstIndex(where: { $0.id == id }) } ?? 0
        var appendedCount = 0
        for w in liveWindows where !w.title.isEmpty && !assigned.contains(w.id) {
            ws[targetIdx].windowIds.append(w.id)
            appendedCount += 1
            log.info("appendUnassigned: \(w.id) (\(w.bundleId ?? "?")) → \(ws[targetIdx].name)")
        }
        if appendedCount > 0 {
            log.info("appendUnassigned: \(appendedCount) window(s) to \(ws[targetIdx].name)")
        }
        setWorkspaces(ws)
    }

    // MARK: – Update and group

    public func updateAndGroup(for windows: [Window], mruOrder: Bool = true) -> [(Workspace, [Window])] {
        update(windows: windows)
        return groupCurrentWorkspaces(windows: windows, mruOrder: mruOrder)
    }

    public func groupCurrentWorkspaces(windows: [Window], mruOrder: Bool = true) -> [(Workspace, [Window])] {
        let ws = workspaces()
        if mruOrder { return groupByWorkspace(workspaces: ws, windows: windows) }
        let live = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        return ws.map { workspace in
            (workspace, workspace.windowIds.compactMap { live[$0] })
        }
    }

    private func groupByWorkspace(workspaces ws: [Workspace], windows: [Window]) -> [(Workspace, [Window])] {
        var windowToWorkspace: [UInt32: UUID] = [:]
        for workspace in ws {
            for wid in workspace.windowIds { windowToWorkspace[wid] = workspace.id }
        }

        var seen: [Workspace] = []
        var seenSet: Set<UUID> = []
        for w in windows {
            if let wsId = windowToWorkspace[w.id], seenSet.insert(wsId).inserted,
               let workspace = ws.first(where: { $0.id == wsId }) {
                seen.append(workspace)
            }
        }
        let ordered = seen + ws.filter { !seenSet.contains($0.id) }
        return ordered.map { workspace in
            let ids = Set(workspace.windowIds)
            return (workspace, windows.filter { ids.contains($0.id) })
        }
    }

    // MARK: – Workspace CRUD

    public func setActiveWorkspace(id: UUID) {
        guard workspaces().contains(where: { $0.id == id }) else { return }
        spaceActiveWorkspace[currentSpace] = id
    }

    @discardableResult
    public func addWorkspace(name: String) -> UUID {
        log.info("addWorkspace: \(name)")
        let ws = Workspace(name: name)
        var all = workspaces()
        all.insert(ws, at: 0)
        setWorkspaces(all)
        flush()
        return ws.id
    }

    public func removeWorkspace(id: UUID) {
        var all = workspaces()
        guard all.count > 1 else { return }
        let name = all.first(where: { $0.id == id })?.name ?? "unknown"
        log.info("removeWorkspace: \(name)")
        all.removeAll { $0.id == id }
        setWorkspaces(all)
        if spaceActiveWorkspace[currentSpace] == id {
            spaceActiveWorkspace.removeValue(forKey: currentSpace)
        }
        flush()
    }

    public func renameWorkspace(id: UUID, name: String) {
        var all = workspaces()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].name = name
        setWorkspaces(all)
        flush()
    }

    public func moveWorkspace(id: UUID, toContext targetCtxId: UUID) {
        guard var ctxs = spaceContexts[currentSpace] else { return }
        var workspace: Workspace?
        for ci in ctxs.indices {
            if let wi = ctxs[ci].workspaces.firstIndex(where: { $0.id == id }) {
                workspace = ctxs[ci].workspaces.remove(at: wi)
                break
            }
        }
        guard let ws = workspace,
              let targetIdx = ctxs.firstIndex(where: { $0.id == targetCtxId }) else { return }
        log.info("moveWorkspace: \(ws.name) to \(ctxs[targetIdx].name)")
        ctxs[targetIdx].workspaces.insert(ws, at: 0)
        spaceContexts[currentSpace] = ctxs
        flush()
    }

    // MARK: – Window operations

    public func removeWindow(_ windowId: UInt32) {
        log.info("removeWindow: \(windowId)")
        guard var ctxs = spaceContexts[currentSpace] else { return }
        for ci in ctxs.indices {
            for wi in ctxs[ci].workspaces.indices {
                ctxs[ci].workspaces[wi].windowIds.removeAll { $0 == windowId }
            }
        }
        spaceContexts[currentSpace] = ctxs
        flush()
    }

    public func moveWindow(_ windowId: UInt32, toWorkspace targetId: UUID) {
        guard var ctxs = spaceContexts[currentSpace] else { return }
        var targetCtxIdx: Int?
        var targetWsIdx: Int?
        for ci in ctxs.indices {
            for wi in ctxs[ci].workspaces.indices {
                ctxs[ci].workspaces[wi].windowIds.removeAll { $0 == windowId }
                if ctxs[ci].workspaces[wi].id == targetId {
                    targetCtxIdx = ci
                    targetWsIdx = wi
                }
            }
        }
        guard let ci = targetCtxIdx, let wi = targetWsIdx else { return }
        log.debug("moveWindow \(windowId) to \(ctxs[ci].workspaces[wi].name)")
        ctxs[ci].workspaces[wi].windowIds.append(windowId)
        spaceContexts[currentSpace] = ctxs
        flush()
    }

    public func title(for windowId: UInt32) -> String? {
        windowEntries.first(where: { $0.windowId == windowId })?.customTitle
    }

    public func setTitle(_ title: String?, for windowId: UInt32) {
        if let idx = windowEntries.firstIndex(where: { $0.windowId == windowId }) {
            windowEntries[idx].customTitle = title
        } else if let title {
            windowEntries.append(WindowEntry(windowId: windowId, title: "", customTitle: title, lastSeenAt: Date()))
        }
        flush()
    }

    // MARK: – Persistence

    private var windowsFileURL: URL { dir.appendingPathComponent("windows.json") }
    private func spaceFileURL(_ spaceId: Int) -> URL { dir.appendingPathComponent("space-\(spaceId).json") }

    private func load() {
        loadWindows()
        loadAllSpaces()
    }

    private func loadWindows() {
        guard let data = try? Data(contentsOf: windowsFileURL),
              let file = try? JSONDecoder().decode(WindowsFile.self, from: data) else { return }
        var byId: [UInt32: Int] = [:]
        var deduped: [WindowEntry] = []
        for var entry in file.windowEntries {
            entry.lastSeenAt = entry.lastSeenAt ?? Date()
            if let idx = byId[entry.windowId] {
                if deduped[idx].customTitle == nil, entry.customTitle != nil { deduped[idx] = entry }
            } else {
                byId[entry.windowId] = deduped.count
                deduped.append(entry)
            }
        }
        windowEntries = deduped
    }

    private func loadAllSpaces() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for fileURL in files {
            let name = fileURL.lastPathComponent
            guard name.hasPrefix("space-"), name.hasSuffix(".json"),
                  let spaceId = Int(name.dropFirst(6).dropLast(5)) else { continue }
            guard let data = try? Data(contentsOf: fileURL),
                  let space = try? JSONDecoder().decode(SpaceFile.self, from: data) else { continue }
            spaceContexts[spaceId] = space.contexts
            if let id = space.activeContextId, let uuid = UUID(uuidString: id) {
                spaceActiveContext[spaceId] = uuid
            }
            if let id = space.activeWorkspaceId, let uuid = UUID(uuidString: id) {
                spaceActiveWorkspace[spaceId] = uuid
            }
            spaceLastSeen[spaceId] = space.lastSeen ?? Date()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.flush() }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    func flush() {
        saveTask?.cancel(); saveTask = nil
        let enc = JSONEncoder(); enc.outputFormatting = .prettyPrinted
        if let data = try? enc.encode(WindowsFile(windowEntries: windowEntries)) {
            try? data.write(to: windowsFileURL)
        }
        let file = SpaceFile(
            contexts: spaceContexts[currentSpace] ?? [],
            activeContextId: spaceActiveContext[currentSpace]?.uuidString,
            activeWorkspaceId: spaceActiveWorkspace[currentSpace]?.uuidString,
            lastSeen: spaceLastSeen[currentSpace])
        if let data = try? enc.encode(file) {
            try? data.write(to: spaceFileURL(currentSpace))
        }
        // Prune stale spaces
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        for (spaceId, lastSeen) in spaceLastSeen where spaceId != currentSpace && lastSeen < cutoff {
            spaceContexts.removeValue(forKey: spaceId)
            spaceActiveContext.removeValue(forKey: spaceId)
            spaceActiveWorkspace.removeValue(forKey: spaceId)
            spaceLastSeen.removeValue(forKey: spaceId)
            try? FileManager.default.removeItem(at: spaceFileURL(spaceId))
        }
    }
}
