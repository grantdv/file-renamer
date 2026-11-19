import AppKit

/// Single source of truth: settings, watched folders, pipeline queue, pending suggestions, history.
public final class Store {
    public static let shared = Store()

    // persisted
    public private(set) var settings: AppSettings
    // live
    public private(set) var pending: [Suggestion] = []
    public private(set) var records: [RenameRecord] = []
    public private(set) var events: [ActivityEvent] = []   // activity log, capped

    private let dir: URL
    private var processed: Set<String> = []
    private var inFlight: Set<String> = []
    private var watchers: [FolderWatcher] = []
    private var queue: [URL] = []
    private var pumping = false
    private var lastBatchID: UUID?

    private var settingsURL: URL { dir.appendingPathComponent("settings.json") }
    private var stateURL: URL { dir.appendingPathComponent("state.json") }

    private init() {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Application Support/FileRenamer")
        dir = base
        settings = AppSettings()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        if let d = try? Data(contentsOf: settingsURL),
           let s = try? JSONDecoder().decode(AppSettings.self, from: d) {
            settings = s
        } else {
            settings = AppSettings()
        }
        if let d = try? Data(contentsOf: stateURL),
           let st = try? JSONDecoder().decode(StoreState.self, from: d) {
            processed = Set(st.processed)
            records = st.records
            events = st.events
        }
        for r in records { processed.insert(r.newPath) }
    }

    private struct StoreState: Codable {
        var processed: [String]
        var records: [RenameRecord]
        var events: [ActivityEvent]

        init(processed: [String], records: [RenameRecord], events: [ActivityEvent]) {
            self.processed = processed
            self.records = records
            self.events = events
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            processed = try c.decodeIfPresent([String].self, forKey: .processed) ?? []
            records = try c.decodeIfPresent([RenameRecord].self, forKey: .records) ?? []
            events = try c.decodeIfPresent([ActivityEvent].self, forKey: .events) ?? []
        }
    }

    // MARK: - Persistence

    /// Replace settings wholesale (used by the Settings window).
    public func saveSettings(with newSettings: AppSettings) {
        settings = newSettings
        saveSettings()
        restartWatchers()
        UI.shared.refresh()
    }

    func saveSettings() {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(settings).write(to: settingsURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
        } catch {
            NSLog("FileRenamer: failed to save settings: \(error)")
        }
    }

    func saveState() {
        do {
            let enc = JSONEncoder()
            try enc.encode(StoreState(processed: Array(processed), records: records, events: events))
                .write(to: stateURL, options: .atomic)
        } catch {
            NSLog("FileRenamer: failed to save state: \(error)")
        }
    }

    // MARK: - Activity log

    func log(_ kind: String, _ message: String) {
        events.append(ActivityEvent(date: Date(), kind: kind, message: message))
        if events.count > 300 { events = Array(events.suffix(300)) }
        saveState()
        UI.shared.refresh()
    }

    public func clearActivity() {
        events = []
        saveState()
        UI.shared.refresh()
    }

    // MARK: - Folders

    public func addFolder(_ url: URL) {
        var f = settings.folders
        if !f.contains(where: { $0.path == url.path }) {
            f.append(FolderConfig(path: url.path, autoApprove: false))
            log("folder", "watching \(url.lastPathComponent) (new files only)")
        }
        setFolders(f)
    }

    public func removeFolder(path: String) {
        log("folder", "stopped watching \(URL(fileURLWithPath: path).lastPathComponent)")
        setFolders(settings.folders.filter { $0.path != path })
    }

    public func toggleAutoApprove(path: String) {
        settings.folders = settings.folders.map {
            $0.path == path ? FolderConfig(path: $0.path, autoApprove: !$0.autoApprove, activatedAt: $0.activatedAt) : $0
        }
        saveSettings()
        UI.shared.refresh()
    }

    private func setFolders(_ folders: [FolderConfig]) {
        settings.folders = folders
        saveSettings()
        restartWatchers()
        UI.shared.refresh()
    }

    public func setPaused(_ p: Bool) {
        settings.paused = p
        saveSettings()
        log("status", p ? "paused" : "resumed")
    }

    /// Explicitly name EVERY eligible file in a watched folder, including files
    /// that existed before the folder was added, and files that already look
    /// human-named. This is the only way pre-existing files get touched.
    public func renameAllFiles(in path: String) {
        log("scan", "naming all files in \(URL(fileURLWithPath: path).lastPathComponent)…")
        scan(path, force: true)
    }

    /// Name files the user explicitly picked (Finder Services / “Rename Files…” menu).
    /// Explicit selection means force-naming: even human-looking names get renamed.
    public func renameSelectedFiles(_ paths: [String]) async -> (done: Int, skipped: Int) {
        var done = 0, skipped = 0
        let batchID = UUID()
        for p in paths {
            let url = URL(fileURLWithPath: p)
            guard url.isRegularFile else { skipped += 1; continue }
            guard !processed.contains(p) else { skipped += 1; continue }
            guard Naming.kind(of: url.pathExtension) != .unsupported else {
                log("skipped", "\(url.lastPathComponent): unsupported file type")
                skipped += 1
                continue
            }
            let auto = settings.folders.first { p.hasPrefix($0.path + "/") || p == $0.path }?.autoApprove ?? false
            switch await NamingEngine.propose(for: url, settings: settings, autoApprove: auto, batchID: batchID, forceNaming: true) {
            case .suggestion(let s):
                if auto {
                    if rename(s) { done += 1 } else { skipped += 1 }
                } else {
                    pending.append(s)
                    UI.shared.refresh()
                    done += 1
                }
            case .skipped(let why):
                log("skipped", "\(url.lastPathComponent): \(why)")
                skipped += 1
            }
        }
        saveState()
        return (done, skipped)
    }

    // MARK: - Watchers

    public func restartWatchers() {
        watchers.forEach { $0.stop() }
        watchers = settings.folders.map { f in
            FolderWatcher(folder: URL(fileURLWithPath: f.path)) { [weak self] in
                self?.scan(f.path)
            }
        }
        watchers.forEach { $0.start() }
        // Existing files are NOT scanned automatically — that's the explicit
        // “Scan existing files…” action per folder. Only new files are picked up.
    }

    // MARK: - Pipeline

    private func scan(_ folderPath: String, force: Bool = false) {
        guard !settings.paused else { return }
        guard let folder = settings.folders.first(where: { $0.path == folderPath }) else { return }
        let url = URL(fileURLWithPath: folderPath)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ) else {
            log("error", "could not read folder \(url.lastPathComponent) (permission?)")
            return
        }

        let batchID = UUID()
        var enqueued = 0
        for item in items {
            guard item.isRegularFile, !item.lastPathComponent.hasPrefix(".") else { continue }
            let p = item.path
            guard !processed.contains(p), !inFlight.contains(p) else { continue }
            guard Naming.kind(of: item.pathExtension) != .unsupported else { continue }
            // Default: only files that arrived AFTER the folder was added.
            // “Rename all files in folder…” (force) bypasses this gate.
            if !force,
               let attrs = try? FileManager.default.attributesOfItem(atPath: p),
               let birth = attrs[.creationDate] as? Date,
               birth < folder.activatedAt {
                continue
            }
            queue.append(item)
            enqueued += 1
        }
        if enqueued > 0 {
            log("queued", "\(enqueued) file\(enqueued == 1 ? "" : "s") in \(url.lastPathComponent)")
            pump(batchID: batchID, auto: folder.autoApprove, force: force)
        }
    }

    /// Process the queue strictly one file at a time (rate limits, and so a
    /// big “rename all” run doesn't fire hundreds of AI calls at once).
    private func pump(batchID: UUID, auto: Bool, force: Bool) {
        guard !pumping else { return }
        pumping = true
        Task { @MainActor [weak self] in
            while let url = self?.queue.first {
                self?.queue.removeFirst()
                await self?.processNext(url, batchID: batchID, auto: auto, force: force)
            }
            self?.pumping = false
            self?.saveState()
        }
    }

    @MainActor
    private func processNext(_ url: URL, batchID: UUID, auto: Bool, force: Bool) async {
        guard url.isRegularFile, !processed.contains(url.path) else { return }
        inFlight.insert(url.path)
        let settings = self.settings
        let folderPath = url.deletingLastPathComponent().path
        let folderAuto = settings.folders.first { $0.path == folderPath }?.autoApprove ?? auto
        switch await NamingEngine.propose(for: url, settings: settings, autoApprove: folderAuto, batchID: batchID, forceNaming: force) {
        case .suggestion(let s):
            handle(s)
        case .skipped(let why):
            log("skipped", "\(url.lastPathComponent): \(why)")
        }
        inFlight.remove(url.path)
    }

    @MainActor
    private func handle(_ s: Suggestion) {
        if s.autoApprove {
            rename(s)
        } else {
            log("proposed", "\(s.oldName) → \(s.proposedName) (awaiting approval)")
            pending.append(s)
            UI.shared.refresh()
        }
    }

    // MARK: - Actions

    @discardableResult
    func rename(_ s: Suggestion) -> Bool {
        var target = s.newURL
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = s.url.deletingLastPathComponent()
                .appendingPathComponent(s.proposedName.replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression) + "-\(n)")
            n += 1
        }
        do {
            try FileManager.default.moveItem(at: s.url, to: target)
        } catch {
            log("error", "rename failed for \(s.oldName): \(error.localizedDescription)")
            return false
        }
        pending.removeAll { $0.id == s.id }
        processed.insert(s.url.path)
        processed.insert(target.path)
        lastBatchID = s.batchID
        records.append(RenameRecord(oldPath: s.url.path, newPath: target.path, batchID: s.batchID, date: Date()))
        if records.count > 500 { records = Array(records.suffix(500)) }
        log("renamed", "\(s.oldName) → \(target.lastPathComponent)  (\(s.source))")
        saveState()
        if s.autoApprove {
            UI.shared.notify("Renamed “\(s.oldName)” → “\(target.lastPathComponent)”")
        }
        UI.shared.refresh()
        return true
    }

    public func approveAll() {
        for s in pending { rename(s) }
    }

    public func approve(_ id: UUID) {
        guard let s = pending.first(where: { $0.id == id }) else { return }
        rename(s)
    }

    public func undoLastBatch() {
        guard let b = lastBatchID else { return }
        let batch = records.filter({ $0.batchID == b })
        for r in batch.reversed() {
            try? FileManager.default.moveItem(atPath: r.newPath, toPath: r.oldPath)
            processed.insert(r.oldPath)
        }
        records.removeAll { $0.batchID == b }
        lastBatchID = nil
        log("undone", "reverted batch of \(batch.count) rename\(batch.count == 1 ? "" : "s")")
        saveState()
        UI.shared.refresh()
    }

    public var hasUndoableBatch: Bool { lastBatchID != nil }

    // MARK: - One-click import of a pre-existing local setup (convenience, not required)

    public func autoImportProviders() -> Int {
        var added = 0
        // 1) Local OpenAI-compatible server from a pi models.json, if present
        if let (base, key, model) = Self.detectLocalEndpoint(),
           !settings.providers.contains(where: { $0.baseURL == base }) {
            let p = Provider(name: "Local LLM", baseURL: base, apiKey: key, model: model, supportsVision: false)
            settings.providers.append(p)
            if settings.textProviderID == nil { settings.textProviderID = p.id }
            added += 1
        }
        // 2) An OpenAI key from env or a local key file, if present
        if let key = Self.detectOpenAIKey(),
           !settings.providers.contains(where: { $0.baseURL.hasSuffix("api.openai.com") }) {
            let p = Provider(name: "OpenAI", baseURL: "https://api.openai.com/v1", apiKey: key, model: "gpt-4o", supportsVision: true)
            settings.providers.append(p)
            if settings.imageProviderID == nil { settings.imageProviderID = p.id }
            added += 1
        }
        if added > 0 { saveSettings() }
        return added
    }

    private static func detectLocalEndpoint() -> (String, String, String)? {
        let path = NSString(string: "~/.pi/agent/models.json").expandingTildeInPath
        guard let txt = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        func grab(_ key: String) -> String? {
            guard let r = txt.range(of: "\"\(key)\"\\s*:\\s*\"", options: .regularExpression) else { return nil }
            let rest = txt[r.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { return nil }
            return String(rest[..<end])
        }
        guard let base = grab("baseUrl"), let key = grab("apiKey"), let model = grab("id") else { return nil }
        return (base, key, model)
    }

    private static func detectOpenAIKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.isEmpty { return env }
        let path = NSString(string: "~/new_openai_key").expandingTildeInPath
        guard let t = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let k = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return k.isEmpty ? nil : k
    }
}
