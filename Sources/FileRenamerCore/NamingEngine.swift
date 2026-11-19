import Foundation

/// Outcome of attempting to name a file.
enum NamingResult {
    case suggestion(Suggestion)
    case skipped(String)
}

/// Turns a new file into a naming suggestion, routing to the configured providers.
enum NamingEngine {
    /// - Parameter forceNaming: when true (explicit “Rename all files…” or a
    ///   file picked in Finder), files that already look human-named are renamed too.
    static func propose(for url: URL, settings: AppSettings, autoApprove: Bool, batchID: UUID,
                        forceNaming: Bool = false) async -> NamingResult {
        let style = settings.naming
        let ext = url.pathExtension.lowercased()
        let kind = Naming.kind(of: ext)
        guard kind != .unsupported else { return .skipped("unsupported file type (.\(ext))") }

        // Skip files that already carry a human name — the user clearly named them.
        if !forceNaming, Naming.looksAutoNamed(url.lastPathComponent) {
            return .skipped("already has a human name")
        }

        // Date prefix per the naming style.
        let datePart: String?
        switch style.datePrefix {
        case .all: datePart = Naming.datePrefix(for: url, format: style.dateFormat)
        case .images: datePart = (kind == .image) ? Naming.datePrefix(for: url, format: style.dateFormat) : nil
        case .off: datePart = nil
        }
        let dateStr = datePart.map { $0 + "-" } ?? ""

        if kind == .image {
            let fallbackName = "\(dateStr)photo.\(ext)"
            func dateFallback() -> NamingResult {
                fallbackName == url.lastPathComponent
                    ? .skipped("vision provider unavailable and fallback name unchanged")
                    : .suggestion(Suggestion(url: url, proposedName: fallbackName,
                                             source: "date-fallback", autoApprove: autoApprove, batchID: batchID))
            }
            guard let prov = settings.provider(id: settings.imageProviderID), prov.supportsVision else {
                return dateFallback()
            }
            guard let data = downscaleJPEG(path: url.path) else { return dateFallback() }
            do {
                let raw = try await AI.ask(prov, prompt: Naming.imagePrompt(style), imageB64: data.base64EncodedString())
                let stem = Naming.sanitize(raw, style: style.caseStyle)
                guard !stem.isEmpty else { return dateFallback() }
                let name = "\(dateStr)\(stem).\(ext)"
                guard name != url.lastPathComponent else { return .skipped("suggested name unchanged") }
                return .suggestion(Suggestion(url: url, proposedName: name, source: prov.name, autoApprove: autoApprove, batchID: batchID))
            } catch {
                return dateFallback()
            }
        }

        // Text
        guard let prov = settings.provider(id: settings.textProviderID) else {
            return .skipped("no text provider configured")
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return .skipped("not readable as text")
        }
        // skip files that are not mostly human-readable text
        let bad = content.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && ($0.value < 0x20 || $0.value == 0xFFFD) }.count
        if bad * 20 > content.count { return .skipped("binary content") }
        let head = String(content.prefix(4000))
        guard !head.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .skipped("empty file")
        }
        do {
            let raw = try await AI.ask(prov, prompt: Naming.textPrompt(head, style: style))
            let stem = Naming.sanitize(raw, style: style.caseStyle)
            guard !stem.isEmpty else { return .skipped("provider returned no usable name") }
            let name = "\(dateStr)\(stem).\(extCasePreserved(url: url, ext: ext))"
            guard name != url.lastPathComponent else { return .skipped("suggested name unchanged") }
            return .suggestion(Suggestion(url: url, proposedName: name, source: prov.name, autoApprove: autoApprove, batchID: batchID))
        } catch {
            return .skipped("provider error: \(error.localizedDescription)")
        }
    }

    /// Keep the original extension casing (".JSON" stays ".JSON").
    static func extCasePreserved(url: URL, ext: String) -> String {
        let orig = url.pathExtension
        guard !orig.isEmpty, orig.lowercased() == ext else { return ext }
        return orig
    }
}
