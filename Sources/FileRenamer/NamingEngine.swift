import Foundation

/// Turns a new file into a naming suggestion, routing to the configured providers.
enum NamingEngine {
    static func propose(for url: URL, settings: AppSettings, autoApprove: Bool, batchID: UUID) async -> Suggestion? {
        let ext = url.pathExtension.lowercased()
        switch Naming.kind(of: ext) {

        case .image:
            let dateFallback = {
                Suggestion(url: url,
                           proposedName: "\(Naming.datePrefix(for: url))-photo.\(ext)",
                           source: "date-fallback",
                           autoApprove: autoApprove,
                           batchID: batchID)
            }
            guard let prov = settings.provider(id: settings.imageProviderID), prov.supportsVision else {
                return dateFallback()
            }
            guard let data = downscaleJPEG(path: url.path) else { return dateFallback() }
            do {
                let raw = try await AI.ask(prov, prompt: Naming.imagePrompt, imageB64: data.base64EncodedString())
                let stem = Naming.sanitize(raw)
                guard !stem.isEmpty else { return dateFallback() }
                let name = "\(Naming.datePrefix(for: url))-\(stem).\(ext)"
                guard name != url.lastPathComponent else { return nil }
                return Suggestion(url: url, proposedName: name, source: prov.name, autoApprove: autoApprove, batchID: batchID)
            } catch {
                return dateFallback()
            }

        case .text:
            guard let prov = settings.provider(id: settings.textProviderID) else { return nil }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            // skip files that are not mostly human-readable text
            let bad = content.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && ($0.value < 0x20 || $0.value == 0xFFFD) }.count
            if bad * 20 > content.count { return nil }
            let head = String(content.prefix(4000))
            guard !head.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            do {
                let raw = try await AI.ask(prov, prompt: Naming.textPrompt(head))
                let stem = Naming.sanitize(raw)
                guard !stem.isEmpty else { return nil }
                let name = "\(stem).\(NamingEngine.extCasePreserved(url: url, ext: ext))"
                guard name != url.lastPathComponent else { return nil }
                return Suggestion(url: url, proposedName: name, source: prov.name, autoApprove: autoApprove, batchID: batchID)
            } catch {
                return nil // local server down etc. — file stays queued? No: leave untouched for now.
            }

        case .unsupported:
            return nil
        }
    }

    /// Keep the original extension casing (".JSON" stays ".JSON").
    static func extCasePreserved(url: URL, ext: String) -> String {
        let orig = url.pathExtension
        guard !orig.isEmpty, orig.lowercased() == ext else { return ext }
        return orig
    }
}
