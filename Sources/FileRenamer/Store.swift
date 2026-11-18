import AppKit

/// Single source of truth: settings, watched folders, pipeline queue, pending suggestions, history.
final class Store {
    static let shared = Store()

    // persisted
    private(set) var settings: AppSettings
    // live
    private(set) var pending: [Suggestion] = []
    private(set) var records: [RenameRecord] = []

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
        }
        for r in records { processed.insert(r.newPath) }
    }

    private struct StoreState: Codable {
        var processed: [String]
        var records: [RenameRecord]
    }

    // MARK: - Persistence

    /// Replace settings wholesale (used by the Settings window).
    func saveSettings(with newSettings: AppSettings) {
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
            try enc.encode(StoreState(processed: Array(processed), records: records))
                .write(to: stateURL, options: .atomic)
        } catch {
            NSLog("FileRenamer: failed to save state: \(error)")
        }
    }

    // MARK: - Folders

    func addFolder(_ url: URL) {
        var f = settings.folders
        if !f.contains(where: { $0.path == url.path }) {
            f.append(FolderConfig(path: url.path, autoApprove: false))
        }
        setFolders(f)
    }

    func removeFolder(path: String) {
        setFolders(settings.folders.filter { $0.path != path })
    }

    func toggleAutoApprove(path: String) {
        settings.folders = settings.folders.map {
            $0.path == path ? FolderConfig(path: $0.path, autoApprove: !$0.autoApprove) : $0
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

    func setPaused(_ p: Bool) {
        settings.paused = p
        saveSettings()
        UI.shared.refresh()
    }

    // MARK: - Watchers

    func restartWatchers() {
        watchers.forEach { $0.stop() }
        watchers = settings.folders.map { f in
            FolderWatcher(folder: URL(fileURLWithPath: f.path)) { [weak self] in
                self?.scan(f.path)
            }
        }
        watchers.forEach { $0.start() }
        // pick up files that are already there
        settings.folders.forEach { scan($0.path) }
    }

    // MARK: - Pipeline

    private func scan(_ folderPath: String) {
        guard !settings.paused else { return }
        guard let folder = settings.folders.first(where: { $0.path == folderPath }) else { return }
        let url = URL(fileURLWithPath: folderPath)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ) else { return }

        let batchID = UUID()
        var enqueued = false
        for item in items {
            guard item.isRegularFile, !item.lastPathComponent.hasPrefix(".") else { continue }
            let p = item.path
            guard !processed.contains(p), !inFlight.contains(p) else { continue }
            guard Naming.kind(of: item.pathExtension) != .unsupported else { continue }
            queue.append(item)
            enqueued = true
        }
        if enqueued { pump(batchID: batchID, auto: folder.autoApprove) }
    }

    private func pump(batchID: UUID, auto: Bool) {
        guard !pumping else { return }
        pumping = true
        Task { @MainActor [weak self] in
            while let url = self?.queue.first {
                self?.queue.removeFirst()
                self?.processNext(url, batchID: batchID, auto: auto)
            }
            self?.pumping = false
            self?.saveState()
        }
    }

    @MainActor
    private func processNext(_ url: URL, batchID: UUID, auto: Bool) {
        guard url.isRegularFile, !processed.contains(url.path) else { return }
        inFlight.insert(url.path)
        let settings = self.settings
        let folderPath = url.deletingLastPathComponent().path
        let folderAuto = settings.folders.first { $0.path == folderPath }?.autoApprove ?? auto
        Task { @MainActor [weak self] in
            if let s = await NamingEngine.propose(for: url, settings: settings, autoApprove: folderAuto, batchID: batchID) {
                self?.handle(s)
            }
            self?.inFlight.remove(url.path)
        }
    }

    @MainActor
    private func handle(_ s: Suggestion) {
        if s.autoApprove {
            rename(s)
        } else {
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
            NSLog("FileRenamer: rename failed: \(error)")
            return false
        }
        pending.removeAll { $0.id == s.id }
        processed.insert(s.url.path)
        processed.insert(target.path)
        lastBatchID = s.batchID
        records.append(RenameRecord(oldPath: s.url.path, newPath: target.path, batchID: s.batchID, date: Date()))
        if records.count > 500 { records = Array(records.suffix(500)) }
        saveState()
        if s.autoApprove {
            UI.shared.notify("Renamed “\(s.oldName)” → “\(target.lastPathComponent)”")
        }
        UI.shared.refresh()
        return true
    }

    func approveAll() {
        for s in pending { rename(s) }
    }

    func approve(_ id: UUID) {
        guard let s = pending.first(where: { $0.id == id }) else { return }
        rename(s)
    }

    func undoLastBatch() {
        guard let b = lastBatchID else { return }
        for r in records.filter({ $0.batchID == b }).reversed() {
            try? FileManager.default.moveItem(atPath: r.newPath, toPath: r.oldPath)
            processed.insert(r.oldPath)
        }
        records.removeAll { $0.batchID == b }
        lastBatchID = nil
        saveState()
        UI.shared.refresh()
    }

    var hasUndoableBatch: Bool { lastBatchID != nil }

    // MARK: - One-click import of a pre-existing local setup (convenience, not required)

    func autoImportProviders() -> Int {
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
